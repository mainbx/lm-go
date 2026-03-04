# LM Go

LM Go is a SwiftUI iOS chat client for LM Studio and other OpenAI-compatible local/remote inference servers.

## Highlights

- Modern glass-style iOS UI with chat, model picker, and settings.
- Streaming chat via Server-Sent Events (SSE).
- `<think>...</think>` reasoning parsing with a compact "Thinking..." preview banner.
- Automatic continuation when a streamed response is truncated (token/length finish reasons).
- Runtime model controls from Settings:
  - Load model
  - Unload model
- Runtime model controls in top chat model picker:
  - Load model
  - Unload model
  - Select loaded model for active chat
- Embeddings tool in Settings for quick text-to-vector testing.
- Multi-server configuration with persisted active server/model selection.

## Requirements

- Xcode 26.3+ (latest stable baseline as of March 2, 2026)
- Swift language mode 6 (`SWIFT_VERSION = 6.0`)
- iOS 26.2 deployment target (latest iOS SDK available in stable Xcode 26.3)
- LM Studio server (local or remote), or another compatible API server

## Run

1. Open `/Users/main/Dev/Workspace/GitHub/lm-go/LMGo.xcodeproj` in Xcode.
2. Select the `LMGo` scheme.
3. Run on simulator or device.

If command-line builds fail with `xcodebuild requires Xcode`, point `xcode-select` to full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Configure Server

In app:

1. Open Settings.
2. Add server host/port/API key.
3. Test connection.
4. Save and select model.

Default LM Studio local server values:

- Host: `localhost`
- Port: `1234`
- TLS: Off (unless you configured HTTPS)

## API Endpoints Used

OpenAI-compatible:

- `GET /v1/models`
- `POST /v1/chat/completions` (streaming and non-streaming)
- `POST /v1/embeddings`

LM Studio REST:

- `GET /api/v1/models`
- `POST /api/v1/models/load`
- `POST /api/v1/models/unload`

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

- No in-app model download/store UI yet.
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
- No models in picker:
  - Load at least one model in LM Studio, then refresh.
