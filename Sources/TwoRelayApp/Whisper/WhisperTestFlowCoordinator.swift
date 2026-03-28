import Foundation

@MainActor
final class WhisperTestFlowCoordinator {
    private let appState: AppState
    private let misspellingDictionary: MisspellingDictionary
    private let recorder: AudioRecorder
    private let whisperEngine: WhisperEngine
    private let promptCleaner: PromptCleaner
    private var isRunning = false

    init(
        appState: AppState,
        misspellingDictionary: MisspellingDictionary,
        recorder: AudioRecorder = AudioRecorder(),
        whisperEngine: WhisperEngine,
        promptCleaner: PromptCleaner = PromptCleaner()
    ) {
        self.appState = appState
        self.misspellingDictionary = misspellingDictionary
        self.recorder = recorder
        self.whisperEngine = whisperEngine
        self.promptCleaner = promptCleaner
    }

    func runRecordThreeSecondsThenTranslateToEnglish() {
        guard !isRunning else {
            print("[2relay] whisper test flow ignored: already running")
            return
        }

        isRunning = true

        Task { @MainActor in
            defer {
                Task { @MainActor in
                    self.isRunning = false
                }
            }

            var recordedAudioURL: URL?

            do {
                print("[2relay] whisper test flow: recording 3 seconds...")
                try recorder.start()
                try await Task.sleep(for: .seconds(3))

                let audioURL = try recorder.stop()
                recordedAudioURL = audioURL
                print("[2relay] whisper test flow: recorded wav at \(audioURL.path)")

                await whisperEngine.updateModelPath(appState.modelPath)
                let translated = try await whisperEngine.transcribeOrTranslate(
                    audioURL: audioURL,
                    task: .translateToEnglish
                )

                print("[2relay] raw transcript: \(translated)")
                let correctedTranscript = misspellingDictionary.apply(to: translated)
                if correctedTranscript != translated {
                    print("[2relay] corrected transcript: \(correctedTranscript)")
                }

                let finalPrompt: String
                if appState.cleanPromptEnabled {
                    finalPrompt = promptCleaner.clean(rawText: correctedTranscript)
                    print("[2relay] cleaned coding prompt:\n\(finalPrompt)")
                } else {
                    finalPrompt = correctedTranscript
                    print("[2relay] clean prompt disabled")
                }

                appState.updateOutputs(rawTranscript: correctedTranscript, finalPrompt: finalPrompt)
            } catch {
                if recorder.isRecording {
                    _ = try? recorder.stop()
                }
                appState.setOverlayError(error.localizedDescription)
                print("[2relay] whisper test flow failed: \(error.localizedDescription)")
            }

            if let recordedAudioURL {
                try? FileManager.default.removeItem(at: recordedAudioURL)
            }
        }
    }

}
