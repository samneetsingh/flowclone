# FlowClone

macOS menu bar dictation app. Hold hotkey → record → whisper.cpp transcribes → LLM cleans up → text injected into focused field.

## Quick Reference

- **Language**: Swift 5.9+, macOS 13.0+ deployment target
- **UI**: SwiftUI views hosted in AppKit containers (NSPopover, NSPanel, NSWindow)
- **Dependencies**: Zero third-party packages. System frameworks only (AVFoundation, Security, ApplicationServices, Carbon)
- **Whisper**: Runtime-downloaded whisper.cpp binary (universal macOS, stored in `~/Library/Application Support/FlowClone/`), NOT the Python openai-whisper CLI
- **Signing**: Ad-hoc (`codesign --sign -`). No Apple Developer account, no notarization, no sandbox.

## Build & Run

```bash
# Build in Xcode
open FlowClone.xcodeproj
# Scheme: FlowClone, destination: My Mac
# Signing: "Sign to Run Locally"

# Package for distribution
./scripts/package.sh
```

No pre-build steps required. The whisper-cpp binary is downloaded automatically on first launch.

## Project Structure

```
FlowClone/
├── App/              # FlowCloneApp.swift, AppDelegate.swift
├── Core/             # HotkeyManager, AudioRecorder, WhisperRunner, LLMClient, TextInjector, etc.
├── Models/           # AppState, Settings, Persona, Hotkey
├── UI/               # SwiftUI views (MenuBarView, SettingsView, RecordingIndicatorView, etc.)
└── Resources/        # Assets, Info.plist, entitlements
scripts/              # package.sh
docs/
├── specs/            # Product spec
├── plans/            # Implementation plan
└── prompts/          # Per-phase build prompts
```

## Architecture Rules

- **AppDelegate owns everything**: All AppKit containers (NSStatusItem, NSPopover, NSPanel, NSWindow) and core service objects live in AppDelegate. SwiftUI views are purely declarative UI.
- **AppState is the single source of truth**: One `ObservableObject` shared across all SwiftUI views via `.environmentObject()` at each hosting boundary.
- **No environment propagation across hosting boundaries**: Every NSHostingController/NSHostingView is an independent SwiftUI tree. Must inject `.environmentObject(appState)` at each one.
- **Pipeline is sequential**: record → transcribe → LLM → inject. No parallelism within a single dictation session.
- **CGEventTap on its own thread**: Dedicated background thread with CFRunLoop. State changes dispatch to MainActor via `Task { @MainActor in }`.
- **Capture context at hotkey press, not injection time**: Both `AXUIElement` (focused element) and frontmost app name are captured the moment the hotkey fires. By injection time (5-30s later), user may have switched contexts.

## Code Conventions

- No third-party packages. No SPM dependencies.
- No comments unless explaining a non-obvious "why" (hidden constraint, workaround, surprising behavior).
- Prefer `async/await` over completion handlers. Use `Task.detached` for `Process.waitUntilExit()` calls.
- Errors that affect the user surface via `AppState.lastError` (shown in popover). Never fail silently.
- API key stored in Keychain (Security framework), never UserDefaults.
- Settings stored as a single JSON-encoded Codable struct in UserDefaults — atomic encode/decode on every change.
- Whisper model files stored at `~/Library/Application Support/FlowClone/models/`.

## Key Technical Decisions

- **Non-sandboxed**: CGEventTap doesn't work in sandbox. Cannot use Mac App Store. Distributed as ad-hoc signed .app via zip/AirDrop.
- **whisper.cpp (not Python whisper)**: Downloaded C++ binary (universal, self-hosted on GitHub release) — no Python, no PATH resolution, no ffmpeg dependency. Reads .wav directly.
- **Audio format**: 16kHz mono Int16 PCM .wav — what whisper.cpp expects internally. AVAudioEngine handles conversion from hardware format.
- **Text injection**: AX `kAXSelectedTextAttribute` first (inserts at cursor), fallback to `kAXValueAttribute`, then paste simulation (Cmd+V via CGEvent). Electron apps always need paste fallback.
- **Model download on first launch**: GGML models downloaded from HuggingFace on first run. Onboarding flow blocks app until at least one model is available.

## Things That Will Break If You Forget

- `codesign --deep` is required when packaging.
- `NSApp.setActivationPolicy(.accessory)` must be called BEFORE creating any windows/popovers, or the Dock icon flashes.
- The CGEventTap C callback cannot capture context — pass self via `userInfo` as `Unmanaged<HotkeyManager>`.
- CGEventTap is disabled by macOS if the callback blocks for >300ms. Never do I/O in the callback.
- `AVAudioFile` must be set to `nil` (closing the file handle) before the file is read by whisper.
- `installTap(onBus:)` can only be called once per bus. Must `removeTap(onBus: 0)` before re-installing.
- Stop sequence for AVAudioEngine: `removeTap` → `stop` (this order matters).
- HotkeyManager must NOT be instantiated if `AXIsProcessTrusted()` is false — `CGEvent.tapCreate` returns nil without accessibility permission.
- The default hotkey is Right Option (hold-to-talk). KeyCode 0, modifier flags raw value 0x00000040.

## Things That Will Break If You Forget (continued)

- The whisper-cpp binary is downloaded to `~/Library/Application Support/FlowClone/whisper-cpp` on first launch. If missing, BinaryManager re-downloads it.
- whisper.cpp process must be run via `Task.detached` — `Process.waitUntilExit()` blocks the calling thread. Never call from MainActor or cooperative pool.
- AppContextDetector must be called at hotkey PRESS time, before any UI appears. If called at injection time, the frontmost app will be wrong (user may have switched during the 5-30s pipeline).
- KeychainHelper.upsert() tries update first, then add. Don't call save() for existing items — it fails with errSecDuplicateItem.

## Development Notes

- To test audio recording in isolation: hold the hotkey, speak, release. Check temp dir for .wav file: `ls $TMPDIR/*.wav`. Verify with `afinfo` (should show 16000 Hz, 1 ch, Int16).
- Models are stored at `~/Library/Application Support/FlowClone/models/`. To reset model state for testing, delete this directory.
- whisper.cpp CLI flags used: `-m <model> -f <audio> -l en -nt -np` (model path, file, language, no timestamps, no prints). Output is read from stdout.
- To test transcription in isolation: `~/Library/Application\ Support/FlowClone/whisper-cpp -m ~/Library/Application\ Support/FlowClone/models/ggml-base.en.bin -f /path/to/test.wav -l en -nt -np`
- To verify Keychain storage: `security find-generic-password -s "com.flowclone.api-key" -g` (shows the stored API key)
- To delete Keychain entry for testing: `security delete-generic-password -s "com.flowclone.api-key"`
- LLM endpoint is any OpenAI-compatible API (LiteLLM, OpenAI, Groq, Ollama at localhost:11434/v1). Same code, different base URL.
