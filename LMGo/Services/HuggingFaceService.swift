import Foundation

enum HuggingFaceError: LocalizedError {
    case invalidRepository
    case invalidSearchQuery
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case noGGUFFiles
    case noMLXRepositories

    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "Enter a valid Hugging Face repository ID (for example: mlx-community/Qwen3.5-4B-4bit)"
        case .invalidSearchQuery:
            return "Enter search keywords (for example: qwen 3.5 mlx)"
        case .invalidURL:
            return "Invalid Hugging Face URL"
        case .invalidResponse:
            return "Unexpected response from Hugging Face"
        case .httpError(let code, let message):
            return "Hugging Face HTTP \(code): \(message)"
        case .noGGUFFiles:
            return "No GGUF files found in this repository"
        case .noMLXRepositories:
            return "No mlx-community MLX repositories found for this query"
        }
    }
}

actor HuggingFaceService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchGGUFRepositories(
        query rawQuery: String,
        token: String?,
        limit: Int = 20
    ) async throws -> [HuggingFaceRepoSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            throw HuggingFaceError.invalidSearchQuery
        }

        guard var components = URLComponents(string: "https://huggingface.co/api/models") else {
            throw HuggingFaceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "full", value: "true"),
            URLQueryItem(name: "limit", value: String(max(limit * 2, 20)))
        ]
        guard let url = components.url else {
            throw HuggingFaceError.invalidURL
        }

        let request = makeRequest(url: url, token: token)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let payload = try JSONDecoder().decode([HuggingFaceSearchModelResult].self, from: data)
        guard !payload.isEmpty else { return [] }

        let hasSiblingData = payload.contains { $0.siblings != nil }
        var matches: [HuggingFaceRepoSearchResult] = []
        var seenRepoIds = Set<String>()

        if hasSiblingData {
            for item in payload {
                guard seenRepoIds.insert(item.id).inserted else { continue }
                let ggufCount = item.siblings?.reduce(into: 0) { count, sibling in
                    if sibling.rfilename.lowercased().hasSuffix(".gguf") {
                        count += 1
                    }
                } ?? 0
                guard ggufCount > 0 else { continue }

                matches.append(
                    HuggingFaceRepoSearchResult(
                        repoId: item.id,
                        downloads: item.downloads,
                        likes: item.likes,
                        lastModified: item.lastModified,
                        matchingArtifactCount: ggufCount,
                        isLikelyMLX: false
                    )
                )

                if matches.count >= limit {
                    break
                }
            }
        }

        // Fallback for API variants that do not include siblings in search response.
        if matches.isEmpty {
            seenRepoIds.removeAll(keepingCapacity: true)
            for item in payload {
                guard seenRepoIds.insert(item.id).inserted else { continue }
                do {
                    let ggufFiles = try await fetchGGUFFiles(repoId: item.id, token: token)
                    guard !ggufFiles.isEmpty else { continue }

                    matches.append(
                        HuggingFaceRepoSearchResult(
                            repoId: item.id,
                            downloads: item.downloads,
                            likes: item.likes,
                            lastModified: item.lastModified,
                            matchingArtifactCount: ggufFiles.count,
                            isLikelyMLX: false
                        )
                    )

                    if matches.count >= limit {
                        break
                    }
                } catch HuggingFaceError.noGGUFFiles {
                    continue
                } catch {
                    continue
                }
            }
        }

        return matches.sorted { lhs, rhs in
            if (lhs.downloads ?? -1) != (rhs.downloads ?? -1) {
                return (lhs.downloads ?? -1) > (rhs.downloads ?? -1)
            }
            if (lhs.likes ?? -1) != (rhs.likes ?? -1) {
                return (lhs.likes ?? -1) > (rhs.likes ?? -1)
            }
            return lhs.repoId.localizedCaseInsensitiveCompare(rhs.repoId) == .orderedAscending
        }
    }

    func searchMLXRepositories(
        query rawQuery: String,
        token: String?,
        limit: Int = 20
    ) async throws -> [HuggingFaceRepoSearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            throw HuggingFaceError.invalidSearchQuery
        }

        guard var components = URLComponents(string: "https://huggingface.co/api/models") else {
            throw HuggingFaceError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "full", value: "true"),
            URLQueryItem(name: "limit", value: String(max(limit * 3, 30)))
        ]
        guard let url = components.url else {
            throw HuggingFaceError.invalidURL
        }

        let request = makeRequest(url: url, token: token)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let payload = try JSONDecoder().decode([HuggingFaceSearchModelResult].self, from: data)
        guard !payload.isEmpty else {
            throw HuggingFaceError.noMLXRepositories
        }

        let results = payload
            .filter { isMLXCommunityRepositoryID($0.id) && isLikelyMLXRepository($0, query: query) }
            .prefix(limit)
            .map { item in
                let artifactCount = item.siblings?.count
                return HuggingFaceRepoSearchResult(
                    repoId: item.id,
                    downloads: item.downloads,
                    likes: item.likes,
                    lastModified: item.lastModified,
                    matchingArtifactCount: artifactCount,
                    isLikelyMLX: true
                )
            }

        guard !results.isEmpty else {
            throw HuggingFaceError.noMLXRepositories
        }

        return Array(results)
    }

    func fetchGGUFFiles(repoId rawRepoId: String, token: String?) async throws -> [HuggingFaceGGUFFile] {
        let repoId = rawRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRepositoryID(repoId) else {
            throw HuggingFaceError.invalidRepository
        }

        let encodedRepoId = encodedPath(repoId)
        guard let url = URL(string: "https://huggingface.co/api/models/\(encodedRepoId)") else {
            throw HuggingFaceError.invalidURL
        }

        let request = makeRequest(url: url, token: token)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let payload = try JSONDecoder().decode(HuggingFaceModelResponse.self, from: data)
        let ggufFiles = payload.siblings
            .filter { $0.rfilename.lowercased().hasSuffix(".gguf") }
            .map {
                HuggingFaceGGUFFile(
                    repoId: repoId,
                    filename: $0.rfilename,
                    sizeBytes: $0.size ?? $0.lfs?.size
                )
            }
            .sorted {
                $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
            }

        guard !ggufFiles.isEmpty else {
            throw HuggingFaceError.noGGUFFiles
        }

        return ggufFiles
    }

    func downloadGGUF(
        repoId rawRepoId: String,
        filename rawFilename: String,
        token: String?,
        to destinationURL: URL
    ) async throws -> Int64? {
        let repoId = rawRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = rawFilename.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidRepositoryID(repoId), !filename.isEmpty else {
            throw HuggingFaceError.invalidRepository
        }

        let encodedRepoId = encodedPath(repoId)
        let encodedFilename = encodedPath(filename)
        guard var components = URLComponents(
            string: "https://huggingface.co/\(encodedRepoId)/resolve/main/\(encodedFilename)"
        ) else {
            throw HuggingFaceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "download", value: "true")]
        guard let url = components.url else {
            throw HuggingFaceError.invalidURL
        }

        let request = makeRequest(url: url, token: token, timeout: 3_600)

        let (temporaryURL, response) = try await session.download(for: request)
        try validateResponse(response, data: nil)

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        if let httpResponse = response as? HTTPURLResponse,
           let lengthString = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(lengthString) {
            return length
        }

        return nil
    }

    private func isValidRepositoryID(_ repoId: String) -> Bool {
        let parts = repoId.split(separator: "/")
        return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
    }

    private func isMLXCommunityRepositoryID(_ repoId: String) -> Bool {
        repoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("mlx-community/")
    }

    private func encodedPath(_ value: String) -> String {
        value
            .split(separator: "/")
            .map { part in
                String(part).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(part)
            }
            .joined(separator: "/")
    }

    private func makeRequest(url: URL, token: String?, timeout: TimeInterval = 60) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func isLikelyMLXRepository(_ item: HuggingFaceSearchModelResult, query: String) -> Bool {
        let id = item.id.lowercased()
        if id.contains("mlx-community/") || id.contains("mlx") {
            return true
        }

        let tags = item.tags?.map { $0.lowercased() } ?? []
        if tags.contains(where: { $0.contains("mlx") }) {
            return true
        }

        let siblingNames = item.siblings?.map { $0.rfilename.lowercased() } ?? []
        if siblingNames.contains(where: { $0.contains("mlx") }) {
            return true
        }

        // Fallback when search is broad: if user asked for MLX and the repo looks like
        // a standard safetensors model repo, include it so users still get candidates.
        if query.lowercased().contains("mlx"),
           siblingNames.contains(where: { $0.hasSuffix(".safetensors") }) {
            return true
        }

        return false
    }

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HuggingFaceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            throw HuggingFaceError.httpError(httpResponse.statusCode, message)
        }
    }
}

private struct HuggingFaceModelResponse: Decodable {
    let siblings: [HuggingFaceSibling]
}

private struct HuggingFaceSearchModelResult: Decodable {
    let id: String
    let likes: Int?
    let downloads: Int?
    let lastModified: String?
    let tags: [String]?
    let siblings: [HuggingFaceSibling]?

    enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case likes
        case downloads
        case lastModified
        case tags
        case siblings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            id = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .modelId) {
            id = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing id/modelId")
            )
        }

        likes = try container.decodeIfPresent(Int.self, forKey: .likes)
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
        lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        siblings = try container.decodeIfPresent([HuggingFaceSibling].self, forKey: .siblings)
    }
}

private struct HuggingFaceSibling: Decodable {
    let rfilename: String
    let size: Int64?
    let lfs: HuggingFaceLFSInfo?
}

private struct HuggingFaceLFSInfo: Decodable {
    let size: Int64?
}
