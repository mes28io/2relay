# 2relay

Voice-to-prompt relay for macOS. Speak naturally in any language, get clean English prompts pasted into any app.

## How it works

| Step | What happens |
|------|-------------|
| **Hold Fn** | Push-to-talk: recording starts |
| **Release Fn** | Recording stops, Whisper transcribes locally |
| **Auto-paste** | Clean prompt is pasted into your focused app |

There's also a **hands-free mode** (Fn+Space by default) — press once to start, press again to stop. Customizable in Settings > Shortcuts.

## Features

- **100% local** — Whisper runs on-device, audio never leaves your Mac
- **Any language in, English out** — speak in your native language, get English prompts
- **Paste anywhere** — auto-pastes into your editor, terminal, browser, or any focused app
- **Auto-cleanup** — removes fillers, stutters, and repetitions
- **Dual shortcuts** — Fn (push-to-talk) + Fn+Space (hands-free toggle)
- **Menu bar app** — lives in your menu bar, no dock clutter

## Install

### curl (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/mes28io/2relay/main/scripts/install.sh | bash
```

### DMG

Download the latest `.dmg` from [Releases](https://github.com/mes28io/2relay/releases), open it, and drag 2relay to Applications.

### Requirements

- macOS 13+
- A [license key](https://2relay.2eight.co) ($8.90 one-time, lifetime)
- Whisper model file at `~/models/ggml-medium.bin`

## License key

2relay is open source but requires a license key to use. Get one at [2relay.2eight.co](https://2relay.2eight.co) for $8.90 (one-time, lifetime). Enter the key during the app's setup flow.

The license is verified via Ed25519 signed tokens — your key is validated once online, then works offline forever.

## Development

```bash
swift build
swift test
```

The app runs as a proper `.app` bundle built via the Xcode project at `mac-app/2relay.xcodeproj`. Running `swift run` launches a terminal process (not the full app experience).

## Building a release

```bash
# Build the .app bundle
TWORELAY_MARKETING_VERSION=0.2.0 ./scripts/build_release.sh

# Create release zip for GitHub
./scripts/make_release_zip.sh

# Create DMG installer
./scripts/make_dmg.sh
```

Upload `dist/2relay-macos.zip` and `dist/2relay-macos.zip.sha256` to the GitHub Release.

## Project structure

```
Sources/
  TwoRelayCore/     Shared library (hotkeys, audio, whisper, UI)
  TwoRelayApp/      App wrapper (mirrors TwoRelayCore)
mac-app/            Xcode project (XcodeGen)
scripts/            Build, release, and install scripts
Tests/              Unit tests
```

## License

MIT — see [LICENSE](LICENSE).
