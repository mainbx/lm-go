# LM Go

LM Go is a SwiftUI iOS chat client for LM Studio and other OpenAI-compatible local/remote inference servers.

## Highlights

- Modern glass-style iOS UI with chat, model picker, and settings.
- Streaming chat via Server-Sent Events (SSE).
- `<think>...</think>` reasoning parsing with a compact "Thinking..." preview banner.
- Automatic continuation when a streamed response is truncated (token/length finish reasons).
- Runtime model controls from Settings and model picker (`load`, `unload`, `select loaded`).
- Embeddings tool in Settings for quick text-to-vector testing.
- On-device local MLX support:
  - Hugging Face repository search
  - Add model by `owner/repo`
  - Load/unload and chat inference on device
- Legacy on-device GGUF path remains in code for compatibility.
- Multi-server configuration with persisted active server/model selection.

## Requirements

- Xcode 26.3+
- Swift language mode 6 (`SWIFT_VERSION = 6.0`)
- iOS 26.2 deployment target
- LM Studio server (local or remote), or another compatible API server
- Apple device for on-device MLX inference (iPhone/iPad)

## Run

1. Open `/Users/main/Dev/Workspace/GitHub/lm-go/LMGo.xcodeproj` in Xcode.
2. Select the `LMGo` scheme.
3. Run on simulator or device.

If command-line builds fail with `xcodebuild requires Xcode`, point `xcode-select` to full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

If MLX package builds fail with `missing Metal Toolchain`, install it once:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Configure Server

In app:

1. Open Settings.
2. Add server host/port/API key.
3. Test connection.
4. Save and select model.

If you want local-only usage, tap `Use On-Device Mode` on first launch and manage MLX model IDs from Settings -> On-Device LLMs.

Default LM Studio local server values:

- Host: `localhost`
- Port: `1234`
- TLS: Off (unless you configured HTTPS)

## On-Device MLX Quick Start

1. Open `Settings -> On-Device LLMs`.
2. Search Hugging Face with keywords like `qwen 3.5 mlx`.
3. Pick a repository and tap `Use`, then tap `Add MLX Model`.
4. Tap `Load` for that model.
5. Select it from the model picker and start chatting.

Notes:

- Model IDs must be `owner/repo` format (example: `mlx-community/Qwen3.5-4B-MLX-4bit`).
- Hugging Face token is optional; required for private/gated repos.
- First load downloads model artifacts through `MLXLMCommon` and can take time.
- Inference speed/memory depend heavily on model size; start with smaller models if needed.

## API Endpoints Used

OpenAI-compatible:

- `GET /v1/models`
- `POST /v1/chat/completions` (streaming and non-streaming)
- `POST /v1/embeddings`

LM Studio REST:

- `GET /api/v1/models`
- `POST /api/v1/models/load`
- `POST /api/v1/models/unload`

Hugging Face (for local model discovery):

- `GET /api/models?search=...&full=true&limit=...` (repository discovery/search)
- `MLXLMCommon` handles artifact download/cache on first model load (`loadModelContainer(id:)`).

## Truncation Auto-Continue

During streaming, LM Go inspects `finish_reason`.  
If the stream ends with truncation-like reasons (`length`, `max_tokens`, etc.), LM Go automatically issues follow-up continuation requests and appends into the same in-progress assistant response.

Guardrails:

- max continuation hops: `3`
- manual Stop cancels continuation

## Project Structure

- `LMGo/Services/`
  - `APIService.swift`: HTTP client and API request/response models
  - `StreamingService.swift`: SSE streaming parser
  - `PersistenceService.swift`: `UserDefaults` persistence
- `LMGo/ViewModels/`
  - `ChatViewModel.swift`: chat lifecycle, streaming, continuation logic
  - `ServerViewModel.swift`: server/model/runtimes/embeddings state
  - `ConversationsViewModel.swift`: conversation list management
- `LMGo/Views/`
  - `Chat/`: message list, input, bubble rendering
  - `Navigation/`: conversation list and model picker sheets
  - `Settings/`: server config, model/runtime controls, embeddings panel
- `LMGo/Models/`
  - `Message`, `Conversation`, `ServerConfig`, `LMModel`
- `LMGo/Theme/`
  - `Theme.swift`: shared color, spacing, and glass card style

## Current Scope and Limitations

- Local on-device inference targets MLX repositories (recommended) and supports legacy GGUF paths.
- MLX model download lifecycle is handled by `MLXLMCommon` cache flow (no in-app progress UI yet).
- Continuation currently uses chat-completions continuation prompting (not `/v1/responses` stateful chaining).
- No automated test target currently included.

## Troubleshooting

- Runtime model list errors:
  - Ensure LM Studio server is reachable.
  - Use Settings -> Models refresh.
  - Verify server has runtime-discoverable models.
- Load/unload fails:
  - Confirm the selected model exists in LM Studio runtime list.
  - Check server response details shown in Settings error banner.
- On-device MLX load fails:
  - Verify model ID is valid `owner/repo`.
  - Try a smaller MLX model.
  - Ensure network is reachable for first load.
  - Add a Hugging Face token if repo is gated/private.
- No models in picker:
  - Load at least one model in LM Studio, then refresh.
