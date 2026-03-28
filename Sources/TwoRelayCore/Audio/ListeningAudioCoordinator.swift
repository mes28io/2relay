import Combine
import AppKit
import Foundation

@MainActor
final class ListeningAudioCoordinator {
    private let appState: AppState
    private let permissionCenter: PermissionCenter
    private let misspellingDictionary: MisspellingDictionary
    private let recorder: AudioRecorder
    private let whisperEngine: WhisperEngine
    private let targetDispatcher: TargetDispatcher
    private let promptCleaner: PromptCleaner
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        permissionCenter: PermissionCenter,
        misspellingDictionary: MisspellingDictionary,
        whisperEngine: WhisperEngine,
        targetDispatcher: TargetDispatcher,
        promptCleaner: PromptCleaner = PromptCleaner(),
        recorder: AudioRecorder = AudioRecorder()
    ) {
        self.appState = appState
        self.permissionCenter = permissionCenter
        self.misspellingDictionary = misspellingDictionary
        self.whisperEngine = whisperEngine
        self.targetDispatcher = targetDispatcher
        self.promptCleaner = promptCleaner
        self.recorder = recorder

        appState.$isListening
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isListening in
                Task { @MainActor in
                    self?.handleListeningChange(isListening)
                }
            }
            .store(in: &cancellables)
    }

    private func handleListeningChange(_ isListening: Bool) {
        if isListening {
            Task { @MainActor in
                await startRecordingIfAllowed()
            }
            return
        }

        guard recorder.isRecording else {
            appState.setIdle()
            return
        }

        appState.setTranscribing()

        do {
            let wavURL = try recorder.stop()
            appState.reportStatus("Audio captured. Translating to English...", level: .info)
            print("[2relay] audio capture saved: \(wavURL.path)")

            Task { @MainActor in
                defer {
                    try? FileManager.default.removeItem(at: wavURL)
                }

                do {
                    await whisperEngine.updateModelPath(appState.modelPath)
                    let translatedText = try await whisperEngine.transcribeOrTranslate(
                        audioURL: wavURL,
                        task: .translateToEnglish
                    )

                    print("[2relay] raw transcript: \(translatedText)")
                    let correctedTranscript = misspellingDictionary.apply(to: translatedText)
                    if correctedTranscript != translatedText {
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
                    if appState.autoCopyPromptToClipboardEnabled {
                        writePromptToClipboard(finalPrompt)
                        appState.saveTargetClip(finalPrompt, for: appState.defaultTarget)
                        appState.reportStatus("Copied clip for \(appState.defaultTarget.displayName).", level: .success)
                    }

                    if appState.autoSendAfterTranscriptionEnabled {
                        print("[2relay] auto-send enabled: dispatching prompt to \(appState.defaultTarget.displayName)")
                        appState.reportStatus("Auto-sending to \(appState.defaultTarget.displayName)...", level: .info)
                        sendReadyPromptToTarget()
                    }
                } catch {
                    appState.setOverlayError(error.localizedDescription)
                    print("[2relay] whisper translation failed: \(error.localizedDescription)")
                }
            }
        } catch AudioRecorderError.noAudioCaptured {
            appState.setIdle()
            appState.reportStatus("No audio captured. Hold the hotkey slightly longer.", level: .warning)
            print("[2relay] audio capture failed to stop: No audio samples were captured.")
        } catch AudioRecorderError.notRecording {
            appState.setIdle()
        } catch {
            appState.setOverlayError(error.localizedDescription)
            print("[2relay] audio capture failed to stop: \(error.localizedDescription)")
        }
    }

    private func startRecordingIfAllowed() async {
        permissionCenter.refreshFromSystem()

        await permissionCenter.requestMicrophonePermissionIfNeeded()
        permissionCenter.refreshFromSystem()

        guard appState.isListening else {
            return
        }

        guard permissionCenter.microphoneState == .granted else {
            print("[2relay] audio capture failed to start: Microphone access is not granted.")
            appState.cancelListening()
            appState.setOverlayError("Microphone permission is required. Click Open in Settings in Permissions if the prompt does not appear.")
            return
        }

        do {
            try recorder.start()
            permissionCenter.refreshFromSystem()
            appState.reportStatus("Microphone capture started.", level: .info)
            print("[2relay] audio capture started")
        } catch AudioRecorderError.microphonePermissionDenied {
            permissionCenter.refreshFromSystem()
            print("[2relay] audio capture failed to start: Microphone access is not granted.")
            appState.cancelListening()
            appState.setOverlayError("Microphone permission is required. Click Open in Settings in Permissions if the prompt does not appear.")
        } catch {
            print("[2relay] audio capture failed to start: \(error.localizedDescription)")
            appState.cancelListening()
            appState.setOverlayError(error.localizedDescription)
        }
    }

    func sendReadyPromptToTarget() {
        let prompt = appState.lastPromptToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            appState.setOverlayError("No prompt is ready to send.")
            return
        }

        do {
            try targetDispatcher.activateAndPaste(
                text: prompt,
                target: appState.defaultTarget
            )
            appState.reportStatus("Prompt sent to \(appState.defaultTarget.displayName).", level: .success)
            appState.setOverlayError(nil)
            appState.clearPendingPrompt()
            print("[2relay] prompt pasted into \(appState.defaultTarget.displayName)")
        } catch let error as TargetDispatcherError {
            switch error {
            case .accessibilityPermissionRequired:
                permissionCenter.refreshFromSystem()
                writePromptToClipboard(prompt)
                appState.saveTargetClip(prompt, for: appState.defaultTarget)
                appState.setOverlayError(
                    "Auto-paste is blocked by Accessibility permission. Prompt was copied to clipboard. Paste manually with Cmd+V. If permission is already enabled, restart 2relay."
                )
                appState.reportStatus("Auto-paste blocked. Prompt copied to clipboard.", level: .warning)
            default:
                appState.setOverlayError(error.localizedDescription)
            }

            print("[2relay] target dispatch failed: \(error.localizedDescription)")
        } catch {
            appState.setOverlayError(error.localizedDescription)
            print("[2relay] target dispatch failed: \(error.localizedDescription)")
        }
    }

    func copyReadyPromptToClipboard() {
        let prompt = appState.lastPromptToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            appState.setOverlayError("No prompt is ready to copy.")
            return
        }

        writePromptToClipboard(prompt)
        appState.saveTargetClip(prompt, for: appState.defaultTarget)
        appState.reportStatus("Prompt copied to clipboard for \(appState.defaultTarget.displayName).", level: .success)
        appState.setOverlayError(nil)
        appState.setReadyToSend()
        print("[2relay] prompt copied to clipboard")
    }

    func cancelReadyPrompt() {
        appState.clearPendingPrompt()
        print("[2relay] prompt canceled")
    }
    private func writePromptToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
