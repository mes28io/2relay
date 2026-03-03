import ApplicationServices
import AppKit
import AVFoundation
import Foundation

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var microphoneState: PermissionState = .unknown
    @Published private(set) var accessibilityState: PermissionState = .unknown

    private let store: PermissionStore

    init(store: PermissionStore? = nil) {
        self.store = store ?? (try? SQLitePermissionStore()) ?? InMemoryPermissionStore()
        refreshFromSystem()
    }

    var accessibilityPromptCount: Int {
        (try? store.loadSnapshot(for: .accessibility)?.promptCount) ?? 0
    }

    func refreshFromSystem() {
        let microphone = Self.microphoneStateFromSystem()
        updateState(microphone, for: .microphone)

        let accessibility = Self.accessibilityStateFromSystem()
        updateState(accessibility, for: .accessibility)
    }

    func refreshFromSystemAndRedirectUnrecognizedIfNeeded() {
        refreshFromSystem()
    }

    func requestAccessibilityPromptIfNeeded(force: Bool = false) {
        refreshFromSystem()

        if !force {
            guard accessibilityState != .granted else {
                return
            }
            guard accessibilityPromptCount == 0 else {
                return
            }
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        try? store.incrementPromptCount(for: .accessibility)
        refreshFromSystem()
    }

    func isAccessibilityTrusted(retryCount: Int = 0, retryDelay: TimeInterval = 0.1) -> Bool {
        func trustedNow() -> Bool {
            if AXIsProcessTrusted() {
                return true
            }

            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        if trustedNow() {
            return true
        }

        guard retryCount > 0 else {
            return false
        }

        for _ in 0..<retryCount {
            Thread.sleep(forTimeInterval: retryDelay)
            if trustedNow() {
                return true
            }
        }

        return false
    }

    func requestMicrophonePermissionIfNeeded() async {
        refreshFromSystem()
        guard microphoneState != .granted else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        _ = await requestMicrophoneAccessUsingAVAudioApplicationIfAvailable()
        refreshFromSystem()
        guard microphoneState != .granted else {
            return
        }

        _ = await requestMicrophoneAccessUsingAVCaptureDevice()

        refreshFromSystem()
    }

    private func requestMicrophoneAccessUsingAVCaptureDevice() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestMicrophoneAccessUsingAVAudioApplicationIfAvailable() async -> Bool? {
        guard #available(macOS 14.0, *) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    @discardableResult
    func openSystemSettings(for kind: PermissionKind) -> Bool {
        for url in Self.systemSettingsURLs(for: kind) {
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        for fallback in Self.systemSettingsFallbackURLs {
            if NSWorkspace.shared.open(fallback) {
                return true
            }
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
           NSWorkspace.shared.open(settingsURL) {
            return true
        }

        for appURL in Self.systemSettingsAppURLs {
            if NSWorkspace.shared.open(appURL) {
                return true
            }
        }

        return false
    }

    private func updateState(_ state: PermissionState, for kind: PermissionKind) {
        switch kind {
        case .microphone:
            microphoneState = state
        case .accessibility:
            accessibilityState = state
        }

        do {
            try store.saveState(state, for: kind)
        } catch {
            print("[2relay] permission store write failed: \(error.localizedDescription)")
        }
    }

    static func microphoneStateFromSystem() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func accessibilityStateFromSystem() -> PermissionState {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return (AXIsProcessTrusted() || AXIsProcessTrustedWithOptions(options)) ? .granted : .denied
    }

    private static func systemSettingsURLs(for kind: PermissionKind) -> [URL] {
        let candidates: [String]
        switch kind {
        case .microphone:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
                "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Microphone"
            ]
        case .accessibility:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
            ]
        }

        return candidates.compactMap(URL.init(string:))
    }

    private static var systemSettingsFallbackURLs: [URL] {
        [
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension"
        ].compactMap(URL.init(string:))
    }

    private static var systemSettingsAppURLs: [URL] {
        [
            URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/System Preferences.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/System Settings.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/System Preferences.app", isDirectory: true)
        ]
    }

    var microphoneIsGranted: Bool {
        Self.microphoneStateFromSystem() == .granted
    }

    var accessibilityIsGranted: Bool {
        Self.accessibilityStateFromSystem() == .granted
    }

    func detailText(for kind: PermissionKind) -> String {
        switch kind {
        case .microphone:
            switch microphoneState {
            case .granted:
                return "2relay can record audio."
            case .denied:
                if isInstalledInApplications {
                    return "Microphone access is denied for 2relay. macOS will not show the native prompt again after Deny, so enable it in Settings."
                }
                return "Microphone access is denied for 2relay. Move 2relay to Applications and relaunch so it appears as an installable app in Privacy settings."
            case .restricted:
                return "Microphone access is restricted by system policy."
            case .unknown:
                return "Microphone access has not been requested yet."
            case .unrecognized:
                return "Microphone state could not be recognized from system APIs."
            }
        case .accessibility:
            switch accessibilityState {
            case .granted:
                return "2relay can send Cmd+V to target apps."
            case .denied:
                return "Accessibility access is not granted."
            case .restricted:
                return "Accessibility access is restricted by system policy."
            case .unknown:
                return "Accessibility status is not determined."
            case .unrecognized:
                return "Accessibility state could not be recognized from system APIs."
            }
        }
    }

    var isInstalledInApplications: Bool {
        let candidatePaths = [
            Bundle.main.bundleURL.standardizedFileURL.path,
            Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        ]

        let prefixes = [
            "/Applications/",
            "/System/Volumes/Data/Applications/",
            "\(NSHomeDirectory())/Applications/"
        ]

        return candidatePaths.contains { path in
            prefixes.contains { path.hasPrefix($0) }
        }
    }

    func revealInstallLocationsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }
}

final class InMemoryPermissionStore: PermissionStore {
    private var data: [PermissionKind: PermissionSnapshot] = [:]

    func loadSnapshot(for kind: PermissionKind) throws -> PermissionSnapshot? {
        data[kind]
    }

    func saveState(_ state: PermissionState, for kind: PermissionKind) throws {
        let existing = data[kind]
        data[kind] = PermissionSnapshot(
            kind: kind,
            state: state,
            updatedAt: Date(),
            promptCount: existing?.promptCount ?? 0,
            lastPromptAt: existing?.lastPromptAt
        )
    }

    func incrementPromptCount(for kind: PermissionKind) throws {
        let existing = data[kind]
        data[kind] = PermissionSnapshot(
            kind: kind,
            state: existing?.state ?? .unknown,
            updatedAt: Date(),
            promptCount: (existing?.promptCount ?? 0) + 1,
            lastPromptAt: Date()
        )
    }
}
