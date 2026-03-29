# ClawMo - OpenClaw Gateway iOS Client

## Project Overview
iOS native client for OpenClaw Gateway, providing IM-style interface to interact with AI agents.
Built with SwiftUI + UIKit hybrid, targeting iOS 17+.

## Tech Stack
- **UI**: SwiftUI (views) + UIKit (UITextView for selectable text, UIImagePickerController, UIDocumentPickerViewController)
- **Networking**: URLSession WebSocket (GatewayClient)
- **Persistence**: SwiftData (PersistedMessage), UserDefaults (gateway configs, device identity)
- **Auth**: Ed25519 challenge-response (CryptoKit), device pairing
- **Speech**: SFSpeechRecognizer for voice input

## Project Structure
```
ClawMo/
├── ClawMoApp.swift                    # App entry, ModelContainer setup
├── Theme/
│   └── Theme.swift                   # Centralized colors, Color(hex:) extension
├── Models/
│   ├── Models.swift                  # Domain models (GatewayConfig, AgentInfo, Conversation, ChatMessage)
│   └── PersistedMessage.swift        # SwiftData @Model for message cache
├── Utilities/
│   ├── ImageUtils.swift              # compressImage()
│   ├── TextParsing.swift             # stripImagesFromText(), parseMessageParts()
│   └── DateFormatting.swift          # formatRowTime(), formatBubbleTime(), formatDateSectionLabel()
├── Services/
│   ├── GatewayClient.swift           # WebSocket client, Protocol v3, Ed25519 auth
│   ├── AppStore.swift                # @Observable coordinator (~340 lines)
│   ├── MessageService.swift          # Message CRUD, dedup, mount/fetch, event handlers
│   ├── ConversationService.swift     # Session grouping, conversation building
│   ├── PersistenceService.swift      # SwiftData read/write/clear
│   ├── MockDataProvider.swift        # Test data generation
│   └── SpeechManager.swift           # Voice input @Observable
├── Views/
│   ├── ContentView.swift             # Tab bar (办公室/消息/设置)
│   ├── Shared/
│   │   ├── AvatarIcon.swift          # SF Symbol / emoji avatar
│   │   └── SelectableText.swift      # UITextView wrapper for drag-to-select
│   ├── Office/
│   │   └── OfficeView.swift          # Agent orbs, status, pairing
│   ├── Messages/
│   │   ├── MessageCenterView.swift   # Conversation list (~139 lines)
│   │   ├── ConversationRow.swift     # List row with avatar + preview
│   │   ├── ConversationDetailView.swift  # Detail + input bar + attachments
│   │   ├── MessageListView.swift     # ScrollView + date grouping
│   │   ├── MessageBubble.swift       # User/agent bubble
│   │   ├── A2AMessageBubble.swift    # Agent-to-agent bubble
│   │   ├── StreamingBubble.swift     # Live streaming indicator
│   │   ├── MessageContentView.swift  # Rich content (images + text)
│   │   ├── ImageViewer.swift         # Fullscreen zoom/save
│   │   ├── AttachmentSheet.swift     # Photo/camera/file picker sheet
│   │   ├── CameraPicker.swift        # UIImagePickerController wrapper
│   │   └── DocumentPicker.swift      # UIDocumentPicker wrapper
│   └── Settings/
│       └── SettingsView.swift        # Gateway management, cache
└── Assets.xcassets/
    ├── AppIcon.appiconset/
    └── LaunchBg.colorset/
```

## Architecture

### Service Layer
- **AppStore** (@Observable): Coordinator holding state, delegates to services
- **MessageService**: Message add/dedup, mount window, event handlers, parseHistory
- **ConversationService**: Session grouping (user by agentId, A2A by pair), agent list building
- **PersistenceService**: SwiftData CRUD, cache size/clear
- **GatewayClient**: WebSocket Protocol v3, Ed25519 auth, request/response matching

### Key Patterns
- **Fetch + Mount**: Background loads into `messages[]`, UI shows `mountedMessages()` (default 30)
- **Message Dedup**: ID match OR (sessionKey + role + text + 5s time window)
- **VStack** (not LazyVStack) for message list — reliable scrollTo
- **SelectableText** (UITextView wrapper) for drag-to-select text

### Gateway Protocol
- `chat.send` supports `attachments` param for images `[{type, mimeType, content}]`
- System messages identified by `provenance` field
- `__openclaw.id` for stable message IDs (history only, not in real-time events)
- API docs: github.com/larrygogo/ming-document → tech/openclaw-gateway-api.md

## Build & Run
```bash
# Simulator (mock mode)
xcodebuild -scheme ClawMo -destination 'id=34434E56-BC6F-4D89-B4FE-C824AA379BE1' build
xcrun simctl launch 34434E56-BC6F-4D89-B4FE-C824AA379BE1 clawmo.ClawMo -- -mock

# Real device: select in Xcode → Run
```

## Known Limitations
- iOS 26.2+ simulator missing emoji font — use SF Symbols
- Gateway `chat.history` returns images as `omitted: true`
- SwiftUI ScrollView has no native "prepend without jump"
