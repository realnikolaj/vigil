# Vigil — Copilot Handoff

**Date:** 2026-04-03
**From:** Overseer (Claude Opus 4.6, CLI session 009)
**To:** Claude Opus 4.6 via GitHub Copilot
**Repos needed:** `vigil` (this repo), `ronitsingh10/FineTune` (reference)

---

## What Vigil Is

Native macOS menu bar app (Swift 6.0, SwiftUI) that serves as the control
plane for voicedaemon — a Go-based voice infrastructure daemon that handles
STT (speech-to-text) and TTS (text-to-speech). Vigil manages voicedaemon
as a child process, monitors audio devices, provides Touch Bar controls,
stores transcripts in SQLite for LoRA fine-tuning, and renders a transparent
subtitle overlay.

## What Works

- **Compiles clean** on Swift 6.0 with strict concurrency (macOS 15+)
- **Menu bar icon** with state-dependent SF Symbols (mic.fill, mic.badge.plus, waveform)
- **SwiftUI popover** with device info, daemon status, transcript list with tap-to-correct
- **Process manager** spawns voicedaemon at `/Users/beskar/go/bin/voicedaemon`, captures stdout
- **Socket manager** connects to voicedaemon's Unix socket at `/tmp/voice-daemon.sock`
- **Core Audio** device enumeration and default device change listeners
- **SQLite** transcript database with correction tagging and training data export
- **Transparent overlay** window for subtitle-style transcripts (NSWindow, borderless, floating)
- **Caps Lock toggle** (partial — see bugs below)

## What Does Not Work (Your Job)

### 1. Caps Lock event lifecycle (crash)
The `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` handler toggles
recording on Caps Lock press. First press works (starts recording). Second press
either doesn't fire or crashes the app. The crash occurs when the popover is
shown while the Caps Lock event fires — likely a thread/actor conflict between
the global event monitor and the NSPopover interaction.

**Ask FineTune:** How do they handle global keyboard events from a menu bar app?
Do they use `NSEvent.addGlobalMonitorForEvents` or a different mechanism?

### 2. Touch Bar from windowless app
`TouchBarController.swift` has the NSTouchBar items defined but no working
presentation mechanism. Standard NSTouchBar requires an NSWindow or NSResponder
chain. Vigil has no window (menu bar only).

**Ask FineTune:** They are also a menu bar app. Do they present a Touch Bar?
If so, how? Options: `NSApplication.touchBar`, hidden NSWindow as key window,
or `NSTouchBarProvider` protocol on NSApplication.

### 3. Socket connection lifecycle
When recording starts, Vigil opens a socket to voicedaemon and sends `start\n`.
Transcripts arrive as `transcript:<text>\n` pushes. When stop is sent on a
separate connection, the original connection should be closed. The lifecycle
sometimes leaves stale connections, causing voicedaemon to see duplicate
`start` commands.

**The socket protocol:**
```
Client → Daemon: "start\n"     → Daemon responds: "started\n", then pushes "transcript:<text>\n"
Client → Daemon: "stop\n"      → Daemon responds: "<accumulated transcript>\n"
Client → Daemon: "status\n"    → Daemon responds: "idle\n" | "listening\n" | "recording\n"
Client → Daemon: "cancel\n"    → Daemon responds: "cancelled\n"
```

### 4. Training data recorder (second mic)
Not implemented. Vigil should open a second audio input (e.g., MacBook mic array)
using Core Audio while voicedaemon uses the primary input (e.g., AirPods).
Records to timestamped WAV files. Pairs with transcript corrections for LoRA
fine-tuning dataset generation.

**Ask FineTune:** Their per-app audio tap implementation is the pattern we need.
How do they create `AudioHardwareTapStream` or aggregate devices? Key files to
study: anything related to `AudioTapManager`, aggregate device creation.

### 5. URL scheme registration
Not implemented. Should register `vigil://start`, `vigil://stop`, `vigil://status`
URL schemes for automation from Shortcuts, Raycast, and scripts.

**Ask FineTune:** They have URL schemes. How is it registered in Info.plist
(or Package.swift for SPM?) and dispatched to handlers?

## Architecture

```
Vigil (Swift, this repo)
├── VigilApp.swift          — Entry point, AppDelegate, menu bar, event monitors
├── SocketManager.swift     — Unix socket connection to voicedaemon
├── DeviceManager.swift     — Core Audio device enumeration and change listeners
├── ProcessManager.swift    — voicedaemon child process lifecycle
├── TranscriptStore.swift   — SQLite database for transcripts and corrections
├── OverlayWindow.swift     — Transparent subtitle overlay (NSWindow + SwiftUI)
├── TouchBarController.swift — Touch Bar item definitions (presentation stubbed)
└── VigilPopoverView.swift  — SwiftUI popover UI

voicedaemon (Go, separate repo: realnikolaj/voicedaemon)
├── Audio capture (PortAudio)
├── WebSocket streaming to stt-server
├── TTS playback (PocketTTS, Speaches)
├── Unix socket server (/tmp/voice-daemon.sock)
└── HTTP API (port 5111, TTS only currently)

stt-server (Python, in voicedaemon repo: stt-server/)
├── WebSocket endpoint — live VAD + Whisper transcription
├── HTTP POST endpoint — batch transcription with word timestamps
├── Silero VAD (ONNX, CPU)
└── faster-whisper (CTranslate2, CUDA)
```

## FineTune Patterns to Study

FineTune (github.com/ronitsingh10/FineTune) is a menu bar audio control app
with 5300 stars. Same bones as Vigil, different purpose. Study these patterns:

1. **Audio tap creation** — Core Audio aggregate devices and tap streams
2. **Device change handling** — Priority-based auto-fallback on disconnect
3. **URL scheme dispatch** — Registration and routing
4. **Menu bar UI** — SwiftUI popover from NSStatusItem
5. **Global event monitoring** — How they handle keyboard/mouse events safely

## Build & Run

```bash
cd ~/git/vigil
swift build
.build/debug/Vigil &
```

## Key Dependencies

- macOS 15.0+ (Sequoia)
- Swift 6.0+
- No external Swift packages (all AppKit/SwiftUI/CoreAudio system frameworks)
- voicedaemon binary at `/Users/beskar/go/bin/voicedaemon`
- voicedaemon socket at `/tmp/voice-daemon.sock`
