# Debrief

On-device AI app for iOS. Records meetings, transcribes audio, and generates structured summaries — all locally on device, no cloud, no data leaves the phone.

## Required reading

Read these before every non-trivial change — they are the source of truth, not this file:

- [docs/ai-harness/safety-and-hipaa.md](docs/ai-harness/safety-and-hipaa.md) — PII rules, logging rules, impact analysis template
- [docs/guides/dev-workflow.md](docs/guides/dev-workflow.md) — how a change moves from edit to committed code

## Stack

- Swift + SwiftUI (iOS 17+)
- On-device speech recognition via `SFSpeechRecognizer` (Apple Speech framework)
- On-device LLM summarization via local GGUF models
- AVFoundation / AVAudioEngine for microphone capture

## Architecture

Feature-first MVVM with four strict layers:

```
SwiftUI View
  → ViewModel         (screen state + named user actions)
    → AppStore        (app-wide orchestration, single source of truth)
      → Services      (AVFoundation, Speech, LLM, file I/O)
```

### Layer rules

- **View**: layout, bindings, and forwarding actions only. No business logic, no persistence, no AVFoundation, no speech APIs.
- **ViewModel**: exposes only UI-ready `@Published` state and named action methods (`onAppear()`, `didTapStop()`). One ViewModel per screen.
- **AppStore**: owns the recording lifecycle, queue processing, and JSON persistence. All cross-screen state lives here.
- **Services**: pure and injectable. They do not import AppStore or ViewModels.

### 300-line rule

**Every SwiftUI View struct must stay under 300 lines.** If a View grows beyond that, extract subviews into that feature's `Components/` folder. This is enforced by SwiftLint on every file edit.

## Folder structure

```
Debrief/
├── App/
│   ├── AppDelegate.swift
│   └── Navigation/AppShellView.swift
├── Features/
│   └── {FeatureName}/
│       ├── Views/          ← SwiftUI screens
│       ├── ViewModel/      ← @MainActor ObservableObject
│       └── Components/     ← feature-local subviews (optional)
└── Shared/
    ├── Components/          ← shared UI used by 3+ features
    ├── Domain/AppModels.swift   ← all models and enums
    ├── Services/                ← pure service types
    └── Theme/AppTheme.swift
```

New features always go under `Features/`. Only models or UI used by 3+ features go into `Shared/`.

## Key files

| File | Purpose |
|------|---------|
| `Shared/Services/AppStore.swift` | App-wide state and recording orchestration |
| `Shared/Domain/AppModels.swift` | All domain models, enums, and runtime state |
| `Shared/Services/NativeAudioRecorderService.swift` | AVAudioEngine mic capture and chunk rotation |
| `Shared/Services/SpeechTranscriptionService.swift` | On-device SFSpeechRecognizer transcription |
| `Shared/Services/LLMSummarizationService.swift` | Local GGUF model inference via LlamaSwift |
| `Shared/Services/SummaryService.swift` | Heuristic NLP summarizer (fallback via Apple NaturalLanguage) |
| `Shared/Services/AudioConversionService.swift` | PCM → WAV conversion |
| `Shared/Services/AudioPlaybackController.swift` | AVAudioPlayer wrapper for recording playback |
| `Shared/Services/BackgroundDownloadService.swift` | Background GGUF model download management |
| `Shared/Services/MeetingExportService.swift` | Plain-text export formatting for meetings |
| `Shared/Services/SettingsStoring.swift` | Protocol for app settings and model management |
| `Shared/Services/DebriefPaths.swift` | File path constants |
| `App/Navigation/AppShellView.swift` | Root tab and navigation shell |

## Build and test

```bash
# Build for simulator
xcodebuild build \
  -project Debrief.xcodeproj \
  -scheme Debrief \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test \
  -project Debrief.xcodeproj \
  -scheme Debrief \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:DebriefTests

# Lint all files
swiftlint lint

# Lint a single file
swiftlint lint Debrief/Features/Home/Views/HomeView.swift
```

Tests use **Swift Testing** (not XCTest). All tests run on simulator.

## Concurrency rules

- All `@Published` state and `@Observable` updates must be on `@MainActor`.
- Audio capture, transcription, and LLM inference run off the main thread.
- Never block `MainActor` with file I/O, model loading, encoding, or network calls.
- Only one live transcription task runs at a time (`processLiveChunksIfNeeded` guard).
- Only one queue processing task runs at a time. Queue processing blocks while recording is active.

## Storage layout

```
Documents/debrief/
├── recordings/{recordingID}/
│   ├── segments/   ← full raw PCM (kept permanently for playback)
│   ├── chunks/     ← 30s rotating PCM chunks (deleted after processing)
│   └── tmp/        ← temporary WAV files for transcription (deleted after processing)
├── playback/
└── state/
    ├── recordings.json   ← persisted RecordingSession array
    └── meetings.json     ← persisted Meeting array
```

Segment files are raw PCM (not WAV or m4a). Any consumer must convert first via `AudioConversionService`.

## Privacy & PII

Debrief records real conversations. Participant names, meeting topics, transcripts, and summaries are sensitive personal data. Read the full rules before touching any code that handles recording, transcription, summarization, or logging:

**[docs/ai-harness/safety-and-hipaa.md](docs/ai-harness/safety-and-hipaa.md)** — required reading before every non-trivial change.

Quick reference — safe vs unsafe logging:

```swift
// ✅ Safe — anonymized IDs and counts only
logger.log("Recording started — ID: \(recordingID)")
logger.log("Chunk \(n)/\(total) transcribed")

// ❌ Unsafe — never log these
logger.log("Topic: \(topic)")                    // PII
logger.log("Participants: \(participants)")      // PII
logger.log("Transcript: \(transcript)")          // PII
```

SwiftLint custom rules (`no_pii_in_logs`, `no_phi_content_in_logs`) enforce this on every file edit automatically.

## MCP

Linear is available via MCP. Use it to read or create tickets when referencing work items related to code changes.

## Git policy

Claude may **read** git state freely. Claude must **not** modify the git repository. The following are blocked in the harness:

- `git commit` — commits are the developer's responsibility
- `git push` — no remote writes
- `git rm` — no tracked file deletion via git
- `git reset` / `git rebase` / `git restore` — no history or working-tree manipulation
- `rm` — no file deletion from the shell

When a change is complete, summarize what was done and tell the developer what to commit. Do not commit or push on their behalf.
