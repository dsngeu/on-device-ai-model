# Safety & Privacy

Debrief records real conversations and generates transcripts and summaries of those meetings. Even though this app is not a clinical tool, the data it handles — participant names, spoken content, meeting topics, and summaries — is **personal and sensitive**. A log leak, a crash report, or a debug print that includes transcript text is a privacy violation.

Read this before every code change that touches recording, transcription, summarization, logging, or any model that carries participant or meeting data.

---

## Verification-first rule

Before making code changes, proposing a fix, or running any command:

1. Do not assume behavior, file ownership, API shape, or root cause.
2. Verify the relevant facts from the codebase before acting.
3. State the evidence briefly before proposing changes.
4. If something cannot be confirmed from available evidence, **explicitly say it is unverified**.
5. For non-trivial tasks, inspect the relevant files and dependencies, propose a plan, then implement.
6. Never claim certainty unless it is directly confirmed by code or tool output.

---

## Impact analysis — required before every non-trivial change

Before touching any file that handles recording state, transcription, summarization, persistence, or logging, answer these by reading the code — not by assuming:

```text
- Verified facts:
- Callers / consumers affected:
- Downstream dependencies:
- PII exposure risk introduced or removed:
- Unknown / not yet verified:
- Plan:
```

Trivial single-line changes (typo, constant value) can use a brief inline note. Anything that touches data flow, logging, or multiple files requires the full analysis.

---

## What counts as PII in Debrief

| Field | Where it lives | Why it is sensitive |
|-------|---------------|---------------------|
| `participants: [String]` | `RecordingSession`, `Meeting` | real names of people in the meeting |
| `meetingTopic: String?` | `RecordingSession`, `Meeting`, `RecordingRuntimeState` | reveals the subject of a private conversation |
| `transcript: String` | `RecordingSession`, `Meeting` | verbatim spoken content — highest sensitivity |
| `summary: String` | `Meeting` | derived from transcript, same risk |
| `summaryLines: [String]` | `Meeting` | same |
| `actionItems: [ActionItem]` | `Meeting` | may contain names and personal commitments |
| `keyDecisions: [String]` | `Meeting` | private deliberation content |
| `openQuestions: [String]` | `Meeting` | same |
| `liveTranscript: String` | `RecordingRuntimeState` | in-flight transcript during recording |

**Safe to log:** `recordingID`, `meetingID`, `id`, `durationSeconds`, `queueState`, `stage`, `chunksReceived`, `chunksTranscribed`, file paths (no user data embedded).

---

## PrintLogger rules

`PrintLogger` (`Shared/Services/PrintLogger.swift`) is the only permitted logging path in this codebase.

### Current gap — fix before adding new log sites

`PrintLogger.enableLogs` defaults to `true` with no release-build guard. This means debug logs emit in App Store builds. Until this is fixed, every new log site must be wrapped:

```swift
// Required wrapper until PrintLogger has a built-in #if DEBUG guard
#if DEBUG
logger.log("...")
#endif
```

The correct permanent fix is to make `PrintLogger` release-safe at the source:

```swift
func log(_ message: String, ...) {
    #if DEBUG
    guard enableLogs else { return }
    // ... emit
    #endif
}
```

### Never log PII fields

```swift
// ✅ Safe — anonymized IDs only
logger.log("Recording started — ID: \(recordingID)")
logger.log("Queue processing complete — meeting: \(meetingID)")
logger.log("Chunk transcribed — count: \(chunksTranscribed)")

// ❌ Unsafe — PII in log
logger.log("Topic: \(topic ?? "")")                          // meetingTopic is PII
logger.log("Participants: \(session.participants)")          // real names
logger.log("Transcript: \(session.transcript)")             // verbatim content
logger.log("Summary: \(meeting.summary)")                   // derived content
logger.log("Action item: \(actionItem.task) for \(actionItem.person ?? "")") // names + tasks
```

### Use counts and states, not content

When logging progress through transcription or summarization, log counts and states — never the content itself.

```swift
// ✅
logger.log("Chunk \(index + 1)/\(total) transcribed — ID: \(recordingID)")
logger.log("Summarization complete — meeting: \(meetingID), model: \(modelID)")

// ❌
logger.log("Transcript so far: \(accumulatedTranscript)")
logger.log("Summary result: \(summaryText)")
```

---

## Known existing violations

These log sites existed before this rule was enforced. Do not add more. Fix them when you touch the surrounding code:

| File | Line | Violation |
|------|------|-----------|
| `Shared/Services/AppStore.swift` | ~85 | `logger.log("beginRecording called — topic: \(topic ?? "(none)")")` — `topic` is PII |

When fixing, replace with the recording ID only:
```swift
// before
logger.log("beginRecording called — topic: \(topic ?? "(none)")")
// after
logger.log("beginRecording called — ID: \(recordingID)")
```

---

## Risky areas — extra care required

These subsystems have non-obvious invariants. Touch them only with verified understanding and a full impact analysis:

- **Live transcription pipeline** — `AppStore.processLiveChunksIfNeeded()` runs one task at a time. Adding log statements inside the chunk loop can accidentally capture transcript fragments.
- **Queue processing** — `processQueuedRecording(recordingID:)` builds the full transcript incrementally. Logging intermediate state risks capturing partial spoken content.
- **Summarization** — `SummaryService.summarize(...)` receives the complete transcript. Never log the input or output of this call.
- **RecordingRuntimeState** — `liveTranscript` is updated on `MainActor` from live chunks. Never serialize or log this struct wholesale.
- **AppStore persistence** — `recordings.json` and `meetings.json` contain full participant lists, topics, and transcripts. Never log these file paths alongside their contents.
- **Error messages** — `localizedDescription` from `SFSpeechRecognizer` or LLM errors can echo back fragments of user input. Log only the error domain and code, not the full message.

---

## What NOT to do

- **Do not log `participants`, `transcript`, `meetingTopic`, `summary`, or any `ActionItem` field** in `PrintLogger`, `print`, `NSLog`, or any future logging path.
- **Do not pass entire model structs to the logger.** `RecordingSession`, `Meeting`, and `RecordingRuntimeState` all contain PII fields. Extract only the safe ID fields before logging.
- **Do not log error messages verbatim** if they originate from speech recognition or LLM inference — they may echo user speech.
- **Do not add new `print()` or `NSLog()` calls** anywhere in the codebase. All logging must go through `PrintLogger`.
- **Do not log file paths that embed user-identifying content.** `recordingID`-based paths are fine; paths that include participant names or meeting topics are not.
- **Do not use `dump()` or `debugPrint()` on any model type.** These serialize all stored properties including PII fields.

---

## After your change — verify no PII leaked

Before marking a task complete, check:

- [ ] No new `print()`, `NSLog()`, `dump()`, or `debugPrint()` calls added
- [ ] Every new `logger.log(...)` call uses only safe fields (`recordingID`, `meetingID`, counts, states)
- [ ] No model struct (`RecordingSession`, `Meeting`, `RecordingRuntimeState`) passed wholesale to any log call
- [ ] Error messages logged by domain/code only, not `.localizedDescription` from speech or LLM paths
- [ ] New log sites wrapped in `#if DEBUG` until `PrintLogger` has a built-in release guard
