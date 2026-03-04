# LM Go

LM Go is a SwiftUI iOS chat app for:

- LM Studio local/remote servers
- OpenAI-compatible APIs
- On-device inference using Apple's MLX runtime

## Highlights

- Glass-style iOS UI with chat, model picker, and settings.
- Streaming chat with SSE (`/v1/chat/completions`).
- `<think>...</think>` parsing with collapsible reasoning UI.
- Live compact thinking preview while generation is in progress.
- Auto-continue when a response is truncated (length/max-tokens finish reasons).
- Runtime model controls for LM Studio (`load`, `unload`, select loaded model).
- On-device MLX model support with Hugging Face search/add flow.
- On-device inference path uses Apple MLX (Metal-accelerated on Apple Silicon).
- Built-in MLX memory panel in Settings (`Active`, `Cache`, `Peak`) with `Refresh` and `Clear Cache`.
- Embeddings test panel in Settings.
- Multi-server configuration with persisted active server/model.

## Current Platform Targets

- Xcode `26.3+`
- Swift `6.0`
- iOS deployment target `26.2`

## Local MLX Status

- `mlx-swift-lm` is pinned to revision `e33eba8513595bde535719c48fedcb10ade5af57` to support `qwen3_5` model type.
- Hugging Face MLX discovery/add flow is intentionally restricted to `mlx-community/*` repos.
- Default suggested repo is `mlx-community/Qwen3.5-4B-4bit`.
- Local on-device generation runs through Apple MLX (`MLX`, `MLXLLM`, `MLXLMCommon`).

## Run In Xcode

1. Open `LMGo.xcodeproj`.
2. Select the `LMGo` scheme.
3. Run on simulator or device.

## Run From Command Line

```bash
# Simulator build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project LMGo.xcodeproj -scheme LMGo -configuration Debug \
-destination 'generic/platform=iOS Simulator' build
```

```bash
# Device compile check without signing
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project LMGo.xcodeproj -scheme LMGo -configuration Debug \
-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

If you see `xcodebuild requires Xcode`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Real Device Signing

To install on a physical iPhone/iPad, you must have valid signing:

- Select your Apple Development Team in Xcode.
- Use an appropriate provisioning profile.
- Keep `CODE_SIGN_STYLE = Automatic` unless you intentionally use manual signing.

Common install error:

- `No code signature found / integrity could not be verified`
- Cause: app was built without valid signing for device install.

## Server Setup (LM Studio / OpenAI-Compatible)

In app Settings:

1. Add server host, port, TLS, and optional API key.
2. Test connection.
3. Save and select a model.

Default LM Studio local values:

- Host: `localhost`
- Port: `1234`
- TLS: off (unless you configured HTTPS)

## On-Device MLX Quick Start

1. Open `Settings -> On-Device LLMs`.
2. Search Hugging Face (example: `qwen 3.5 mlx`).
3. Pick a result and tap `Use`.
4. Confirm the model ID (example: `mlx-community/Qwen3.5-4B-4bit`).
5. Tap `Add MLX Model`.
6. Tap `Load`, then select it from the model picker and chat.

Notes:

- Only `mlx-community/*` IDs are accepted in this flow.
- Hugging Face token is optional; needed for private/gated repos.
- First load downloads artifacts and may take time.
- Start with smaller models for better device memory/performance behavior.
- Inference runs on Apple MLX with Metal acceleration on Apple Silicon devices.

## MLX Memory Panel

In `Settings -> On-Device LLMs`, the app shows live MLX memory stats:

- `Active`: currently active MLX buffers
- `Cache`: reusable cached MLX buffers
- `Peak`: peak active MLX memory since process start

Actions:

- `Refresh`: capture a new memory snapshot
- `Clear Cache`: clear MLX cache and refresh snapshot

This helps distinguish normal MLX cache growth from real memory issues.

## Endpoints Integrated

OpenAI-compatible endpoints:

- `GET /v1/models`
- `POST /v1/chat/completions` (streaming + non-streaming)
- `POST /v1/embeddings`

LM Studio REST endpoints:

- `GET /api/v1/models`
- `POST /api/v1/models/load`
- `POST /api/v1/models/unload`

Hugging Face APIs used for discovery/metadata:

- `GET /api/models?search=...&sort=downloads&direction=-1&full=true&limit=...`
- `GET /api/models/{repoId}`

## Truncation Auto-Continue

When streaming ends with truncation-like finish reasons (`length`, `max_tokens`, and similar), LM Go can automatically send continuation requests and append output into the same assistant message.

Guardrails:

- Max continuation hops: `3`
- Manual `Stop` cancels continuation

## Project Structure

- `LMGo/Services`
  - `APIService.swift`
  - `StreamingService.swift`
  - `PersistenceService.swift`
  - `HuggingFaceService.swift`
- `LMGo/ViewModels`
  - `ChatViewModel.swift`
  - `ServerViewModel.swift`
  - `ConversationsViewModel.swift`
- `LMGo/Views`
  - `Chat/`
  - `Navigation/`
  - `Settings/`
- `LMGo/Models`
  - `Message`, `Conversation`, `LMModel`, local model records
- `LMGo/Theme`
  - `Theme.swift`

## Limitations

- MLX artifact download progress is limited (depends on underlying MLX tooling flow).
- No automated test target is currently defined in the project.
- Local model search is intentionally scoped to `mlx-community/*`.
- Legacy local GGUF code paths exist for compatibility but are not the primary UX path.

## Troubleshooting

- `Unsupported model type: qwen3_5`
  - Ensure dependencies are resolved to the pinned `mlx-swift-lm` revision.
  - Clean build folder and rebuild.
- Runtime models empty in Settings
  - Confirm LM Studio server is reachable and has runtime models.
  - Refresh models from Settings.
- Load/unload fails
  - Verify selected model identifier exists on server runtime list.
  - Check error banner in Settings for server response.
- On-device MLX load fails
  - Verify model ID starts with `mlx-community/`.
  - Try a smaller model.
  - Ensure network is reachable for first load.
  - Add Hugging Face token for gated/private repos.
- Metal compiler warnings in logs
  - Warnings from `mlx-swift` metal kernels (for example unused constants) are dependency compile warnings, not direct evidence of an app memory leak.
  - Use the `MLX Memory` panel to inspect `Active` vs `Cache`, then use `Clear Cache` when needed.
