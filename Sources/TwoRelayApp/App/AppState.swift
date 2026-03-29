import Foundation
import KeyboardShortcuts

@MainActor
final class AppState: ObservableObject {
    private static let onboardingCompletedDefaultsKey = "com.2relay.onboarding.completed"

    enum StatusLevel: Equatable {
        case info
        case success
        case warning
        case error
    }

    struct StatusEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: StatusLevel
    }

    enum OverlayState: Equatable {
        case idle
        case listening
        case transcribing
        case readyToSend
        case error

        var title: String {
            switch self {
            case .idle:
                return "Idle"
            case .listening:
                return "Listening"
            case .transcribing:
                return "Transcribing"
            case .readyToSend:
                return "Ready to Send"
            case .error:
                return "Error"
            }
        }
    }

    @Published var defaultTarget: TargetApp = .clipboard
    @Published var modelPath: String = "~/models/ggml-medium.bin"
    @Published var cleanPromptEnabled: Bool = true
    @Published var launchTargetOnStartupEnabled: Bool = true
    @Published var autoCopyPromptToClipboardEnabled: Bool = true
    @Published var autoSendAfterTranscriptionEnabled: Bool = true
    @Published var hasCompletedOnboarding: Bool
    @Published var overlayState: OverlayState = .idle
    @Published var overlayErrorMessage: String?
    @Published var isSettingsPanelPresented = false
    @Published private(set) var lastRawTranscript: String = ""
    @Published private(set) var lastPromptToSend: String = ""
    @Published private(set) var latestRelays: [String] = []
    @Published private(set) var isListening = false
    @Published private(set) var statusMessage: String = "Ready. Hold the hotkey to talk."
    @Published private(set) var statusLevel: StatusLevel = .info
    @Published private(set) var statusTimestamp: Date = .now
    @Published private(set) var statusHistory: [StatusEntry] = []
    @Published private(set) var targetClips: [TargetApp: String] = [:]
    let licenseValidator: LicenseValidator
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.licenseValidator = LicenseValidator(userDefaults: userDefaults)
        hasCompletedOnboarding = userDefaults.bool(forKey: Self.onboardingCompletedDefaultsKey)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: Self.onboardingCompletedDefaultsKey)
        reportStatus("Setup complete. 2relay is ready.", level: .success)
    }

    func restartOnboarding() {
        hasCompletedOnboarding = false
        userDefaults.set(false, forKey: Self.onboardingCompletedDefaultsKey)
        reportStatus("Setup restarted.", level: .info)
    }

    func startListening() {
        guard !isListening else {
            return
        }

        guard licenseValidator.isLicensed else {
            reportStatus("License required. Restart onboarding to activate.", level: .error)
            return
        }

        overlayErrorMessage = nil
        isListening = true
        overlayState = .listening
        reportStatus("Listening started.", level: .info)
        print("[2relay] startListening()")
    }

    func stopListening() {
        guard isListening else {
            return
        }

        isListening = false
        overlayState = .transcribing
        reportStatus("Transcribing audio...", level: .info)
        print("[2relay] stopListening()")
    }

    func cancelListening() {
        isListening = false
        overlayState = .idle
        reportStatus("Listening canceled.", level: .warning)
    }

    func updateOutputs(rawTranscript: String, finalPrompt: String) {
        lastRawTranscript = rawTranscript
        lastPromptToSend = finalPrompt
        appendLatestRelay(finalPrompt)
        overlayState = .readyToSend
        reportStatus("Relay ready.", level: .success)
    }

    func setOverlayError(_ message: String?) {
        overlayErrorMessage = message
        overlayState = message == nil ? .idle : .error
        if let message {
            reportStatus(message, level: .error)
        }
    }

    func setTranscribing() {
        overlayState = .transcribing
        reportStatus("Transcribing audio...", level: .info)
    }

    func setReadyToSend() {
        overlayState = .readyToSend
        reportStatus("Relay ready.", level: .success)
    }

    func setIdle() {
        overlayState = .idle
        reportStatus("Ready. Hold the hotkey to talk.", level: .info)
    }

    var activeHotkeyDisplayText: String {
        let handsFree = KeyboardShortcuts.getShortcut(for: .relayListen)?.description ?? "Fn+Space"
        return "Fn (hold) / \(handsFree) (toggle)"
    }

    func clearPendingPrompt() {
        lastRawTranscript = ""
        lastPromptToSend = ""
        overlayErrorMessage = nil
        overlayState = .idle
        reportStatus("Ready for the next relay.", level: .info)
    }

    var promptPreview: String {
        let trimmed = lastPromptToSend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed.count <= 120 {
            return trimmed
        }

        let preview = String(trimmed.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(preview)..."
    }

    func selectNextTarget() {
        let all = TargetApp.allCases
        guard let index = all.firstIndex(of: defaultTarget) else {
            defaultTarget = .clipboard
            return
        }

        let nextIndex = all.index(after: index)
        defaultTarget = nextIndex == all.endIndex ? all[all.startIndex] : all[nextIndex]
    }

    func selectPreviousTarget() {
        let all = TargetApp.allCases
        guard let index = all.firstIndex(of: defaultTarget) else {
            defaultTarget = .clipboard
            return
        }

        let previousIndex = index == all.startIndex ? all.index(before: all.endIndex) : all.index(before: index)
        defaultTarget = all[previousIndex]
    }

    func saveTargetClip(_ text: String, for target: TargetApp) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        targetClips[target] = normalized
    }

    private func appendLatestRelay(_ relay: String) {
        let normalized = relay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        if let existingIndex = latestRelays.firstIndex(of: normalized) {
            latestRelays.remove(at: existingIndex)
        }

        latestRelays.insert(normalized, at: 0)
        if latestRelays.count > 12 {
            latestRelays.removeLast(latestRelays.count - 12)
        }
    }

    func reportStatus(_ message: String, level: StatusLevel = .info) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        let timestamp = Date()
        statusMessage = normalized
        statusLevel = level
        statusTimestamp = timestamp
        statusHistory.insert(
            StatusEntry(timestamp: timestamp, message: normalized, level: level),
            at: 0
        )

        if statusHistory.count > 20 {
            statusHistory.removeLast(statusHistory.count - 20)
        }
    }
}
