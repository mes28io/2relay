# whisper.cpp Build Notes (macOS SwiftUI app)

This app's `WhisperEngine` follows the `whisper.swiftui` approach: call Whisper's C API from Swift via the `whisper` module.

## 1) Build whisper.xcframework

From a local clone of [whisper.cpp](https://github.com/ggml-org/whisper.cpp):

```bash
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```

Expected output:

- `build-apple/whisper.xcframework`

If Xcode toolchain selection is wrong:

```bash
sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
```

## 2) Add framework to app target

In Xcode (app target):

1. Drag `build-apple/whisper.xcframework` into the project.
2. Add it under `Frameworks, Libraries, and Embedded Content`.
3. Set Embed to `Do Not Embed` (dynamic embedding is not required for the static usage pattern).
4. Confirm `import whisper` resolves in Swift sources.

## 2b) Terminal-only run (`swift run`) fallback

If you run the app via SwiftPM (`swift run TwoRelay`), Xcode framework linking is not used.
The app now falls back to `whisper.cpp` CLI automatically when the `whisper` module is unavailable.

Install CLI:

```bash
brew install whisper-cpp
```

Expected executable:

- `/opt/homebrew/bin/whisper-cli` (Apple Silicon)
- `/usr/local/bin/whisper-cli` (Intel)

Optional override:

```bash
WHISPER_CPP_CLI=/absolute/path/to/whisper-cli swift run TwoRelay
```

## 3) Model file

Use a local model path in Settings, for example:

- `~/models/ggml-medium.bin`

This app defaults to medium path naming and expects the user to provide/download the model file locally.

## 4) Runtime permissions

- Microphone permission must be granted for recording.

## 5) Test flow in app

Use menu item:

- `Record 3s + Translate (Test)`

Flow:

1. Record 3 seconds of microphone audio.
2. Save temp WAV.
3. Run Whisper with `translate = true`, `language = en`.
4. Print translation to console logs.
