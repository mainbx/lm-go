import Foundation

enum LocalModelBackend: String, Codable, Hashable {
    case gguf
    case mlx

    var displayName: String {
        switch self {
        case .gguf:
            return "GGUF"
        case .mlx:
            return "MLX"
        }
    }
}

struct LocalModelRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var backend: LocalModelBackend
    var repoId: String
    var filename: String
    var storedFilename: String
    var fileSizeBytes: Int64?
    var downloadedAt: Date
    var isLoaded: Bool

    init(
        id: UUID = UUID(),
        backend: LocalModelBackend = .gguf,
        repoId: String,
        filename: String,
        storedFilename: String,
        fileSizeBytes: Int64?,
        downloadedAt: Date = Date(),
        isLoaded: Bool = false
    ) {
        self.id = id
        self.backend = backend
        self.repoId = repoId
        self.filename = filename
        self.storedFilename = storedFilename
        self.fileSizeBytes = fileSizeBytes
        self.downloadedAt = downloadedAt
        self.isLoaded = isLoaded
    }

    enum CodingKeys: String, CodingKey {
        case id
        case backend
        case repoId
        case filename
        case storedFilename
        case fileSizeBytes
        case downloadedAt
        case isLoaded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        backend = try container.decodeIfPresent(LocalModelBackend.self, forKey: .backend) ?? .gguf
        repoId = try container.decode(String.self, forKey: .repoId)
        filename = try container.decode(String.self, forKey: .filename)
        storedFilename = try container.decodeIfPresent(String.self, forKey: .storedFilename) ?? ""
        fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        downloadedAt = try container.decodeIfPresent(Date.self, forKey: .downloadedAt) ?? Date()
        isLoaded = try container.decodeIfPresent(Bool.self, forKey: .isLoaded) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(backend, forKey: .backend)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(filename, forKey: .filename)
        try container.encode(storedFilename, forKey: .storedFilename)
        try container.encodeIfPresent(fileSizeBytes, forKey: .fileSizeBytes)
        try container.encode(downloadedAt, forKey: .downloadedAt)
        try container.encode(isLoaded, forKey: .isLoaded)
    }

    var modelIdentifier: String {
        switch backend {
        case .gguf:
            // Keep existing identifier format so persisted selections continue working.
            return "local://\(repoId)/\(filename)"
        case .mlx:
            return "local://mlx/\(repoId)"
        }
    }

    var displayName: String {
        switch backend {
        case .gguf:
            return filename
        case .mlx:
            return repoId.split(separator: "/").last.map(String.init) ?? repoId
        }
    }

    var requiresLocalFile: Bool {
        backend == .gguf
    }

    static func mlx(
        id: UUID = UUID(),
        repoId: String,
        downloadedAt: Date = Date(),
        isLoaded: Bool = false
    ) -> LocalModelRecord {
        LocalModelRecord(
            id: id,
            backend: .mlx,
            repoId: repoId,
            filename: "MLX",
            storedFilename: "",
            fileSizeBytes: nil,
            downloadedAt: downloadedAt,
            isLoaded: isLoaded
        )
    }
}

struct HuggingFaceGGUFFile: Identifiable, Hashable {
    let repoId: String
    let filename: String
    let sizeBytes: Int64?

    var id: String {
        "\(repoId)#\(filename)"
    }
}

struct HuggingFaceRepoSearchResult: Identifiable, Hashable {
    let repoId: String
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let matchingArtifactCount: Int?
    let isLikelyMLX: Bool

    var id: String {
        repoId
    }
}
