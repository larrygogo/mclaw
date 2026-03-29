# ClawMo

iOS native client for [OpenClaw](https://openclaw.ai) Gateway. IM-style interface to interact with your AI agent team on the go.

Built with SwiftUI + UIKit hybrid, targeting iOS 17+.

## Features

- **Office** - Real-time agent status dashboard with working/idle/offline indicators
- **Messaging** - IM-style conversations with AI agents, supporting text, images, files, and voice input
- **Agent-to-Agent** - View conversations between agents (A2A)
- **Streaming** - Live message streaming with real-time display
- **Attachments** - Send photos (album/camera), documents, with image compression
- **Message History** - Incremental loading with local SwiftData cache
- **Custom Icons** - Personalize agent avatars with SF Symbols
- **Device Pairing** - Ed25519 challenge-response authentication

## Screenshots

_Coming soon_

## Requirements

- iOS 17.0+
- Xcode 15.0+
- An [OpenClaw](https://openclaw.ai) Gateway instance

## Getting Started

1. Clone the repo
2. Open `ClawMo.xcodeproj` in Xcode
3. Build and run on simulator or device
4. Add your Gateway URL in Settings to connect

For mock/demo mode, launch with `-mock` argument.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI + UIKit (selective) |
| Networking | URLSession WebSocket |
| Persistence | SwiftData + UserDefaults |
| Auth | Ed25519 (CryptoKit) |
| Speech | SFSpeechRecognizer |

## Roadmap

- [ ] View and edit OpenClaw Gateway configuration
- [ ] View and edit Agent profiles (config files, model selection, etc.)
- [ ] Multi-language support (i18n)

## License

_TBD_
