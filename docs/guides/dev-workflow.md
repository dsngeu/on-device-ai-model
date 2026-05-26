# Dev Workflow

How a change moves through the AI harness — from idea to committed code. Read this once when you start; after that it becomes habit.

For privacy and PII rules, see [docs/ai-harness/safety-and-hipaa.md](../ai-harness/safety-and-hipaa.md).
For architecture rules, see [CLAUDE.md](../../CLAUDE.md).

---

## Setup (once after cloning)

```bash
bash scripts/setup-hooks.sh
brew install swiftlint
```

That installs the pre-commit PII hook and ensures SwiftLint is available for the edit-time hook.

---

## Feature lifecycle: idea → committed code

```
idea / Linear ticket
        │
        ▼
  Read CLAUDE.md              — architecture rules, layer boundaries, 300-line rule
  Read safety-and-hipaa.md   — PII rules, impact analysis template
        │
        ▼
  Plan the change             — verify facts from codebase, fill the impact analysis template
        │
        ▼
  Implement                   — one logical change at a time
        │                       PostToolUse hook → SwiftLint fires on every Swift edit
        │                       Fix violations before moving to the next file
        ▼
  Build + test locally
        │   xcodebuild build  -project Debrief.xcodeproj -scheme Debrief -destination '...'
        │   xcodebuild test   -project Debrief.xcodeproj -scheme Debrief -destination '...'
        ▼
  git commit                  — pre-commit hook fires, blocks if PII found in log calls
        │
        ▼
  Push + open PR              — CI runs tests on GitHub Actions
```

---

## Inner loop (while making a change)

1. **Edit** — Claude Code writes or edits a Swift file.
2. **SwiftLint fires automatically** — the `PostToolUse` hook in `.claude/settings.json` runs `swiftlint lint` on the file immediately. Errors are shown inline; Claude must fix them before continuing.
3. **300-line check** — SwiftLint's `type_body_length` rule enforces the 300-line limit on every type. If a View grows past it, split into `Components/`.
4. **PII rules** — SwiftLint's `no_pii_in_logs` and `no_phi_content_in_logs` custom rules error on any log statement referencing a PII field.

The goal: catch violations at edit time, not at review time.

---

## Before committing

The pre-commit hook (`scripts/hooks/pre-commit`, installed via `scripts/setup-hooks.sh`) runs automatically on every `git commit`.

It greps newly staged Swift lines for PII fields inside logging calls:

```
git commit
    ↓
pre-commit hook scans staged .swift files
    ↓
❌  BLOCKED   →  "PII in log — AppStore.swift"
               "    +logger.log("topic: \(topic)")"
               "🚫  Commit blocked. See docs/ai-harness/safety-and-hipaa.md"

✅  CLEAN     →  commit proceeds normally
```

**What it checks:** property access of `transcript`, `participants`, `meetingTopic`, `summary`, `summaryLines`, `actionItems`, `keyDecisions`, `openQuestions`, `liveTranscript`, `firstName`, `lastName`, `fullName`, `email`, `phoneNumber` inside any `logger.log`, `print(`, `NSLog(`, `debugPrint(`, or `dump(` call.

**What it does not check:** indirect logging via intermediate variables (`let x = session.transcript; logger.log(x)`). Those require code review.

---

## After pushing

GitHub Actions runs on every PR and push to `main`:

- **[ios-tests.yml](../../.github/workflows/ios-tests.yml)** — resolves packages, runs `DebriefTests` on simulator, uploads result bundle.
- **[ios-release.yml](../../.github/workflows/ios-release.yml)** — manual trigger, builds and signs a release IPA.

A PR is not ready to merge until `ios-tests.yml` is green.

---

## When rules change

| What changed | Where to update |
|---|---|
| Architecture or layer rules | `CLAUDE.md` |
| PII / logging rules | `docs/ai-harness/safety-and-hipaa.md` |
| SwiftLint rules (300-line, custom PII rules) | `.swiftlint.yml` |
| Edit-time hook (SwiftLint trigger) | `.claude/settings.json` + `.claude/hooks/validate-swift.sh` |
| Pre-commit PII grep (fields or patterns) | `scripts/hooks/pre-commit` → re-run `scripts/setup-hooks.sh` |
| Allowed / denied Claude commands | `.claude/settings.json` |

When you update `scripts/hooks/pre-commit`, teammates need to re-run `bash scripts/setup-hooks.sh` to get the new version — git hooks are not tracked automatically.

---

## Quick reference — what fires when

| Moment | What runs | Blocks on failure? |
|---|---|---|
| Every Swift file edit | SwiftLint (via PostToolUse hook) | Yes — Claude must fix before continuing |
| `git commit` | Pre-commit PII grep | Yes — commit blocked |
| PR / push to main | GitHub Actions `ios-tests.yml` | Yes — merge blocked |
