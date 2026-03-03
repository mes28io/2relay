import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum TargetDispatcherError: LocalizedError {
    case textIsEmpty
    case appUnavailable(TargetApp)
    case activationFailed(TargetApp)
    case accessibilityPermissionRequired
    case pasteEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .textIsEmpty:
            return "Prompt text is empty."
        case let .appUnavailable(target):
            return "Could not find or launch \(target.displayName)."
        case let .activationFailed(target):
            return "Could not activate \(target.displayName)."
        case .accessibilityPermissionRequired:
            return "2relay needs Accessibility permission to simulate Cmd+V. Enable it in System Settings > Privacy & Security > Accessibility."
        case .pasteEventCreationFailed:
            return "Failed to create keyboard events for paste action."
        }
    }
}

@MainActor
final class TargetDispatcher {
    private let permissionCenter: PermissionCenter
    private var bootstrappedSessionKeys = Set<String>()

    init(permissionCenter: PermissionCenter) {
        self.permissionCenter = permissionCenter
    }

    func activateAndPaste(text: String, target: TargetApp, claudeCodeMode: ClaudeCodeMode = .terminal) throws {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw TargetDispatcherError.textIsEmpty
        }

        writeToPasteboard(prompt)

        if target == .clipboard {
            // "Anywhere" target: paste into the currently focused input without switching apps.
            Thread.sleep(forTimeInterval: 0.06)
            try injectCommandV()
            return
        }

        try ensureTargetIsRunning(target, activate: true, claudeCodeMode: claudeCodeMode)

        // Allow the activated app to become frontmost before injecting Cmd+V.
        Thread.sleep(forTimeInterval: 0.15)
        try injectCommandV()
    }

    func ensureTargetIsRunning(_ target: TargetApp, activate: Bool, claudeCodeMode: ClaudeCodeMode = .terminal) throws {
        if target == .clipboard {
            return
        }

        let app = try runningOrLaunch(target, activate: activate, claudeCodeMode: claudeCodeMode)
        guard !activate || app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) else {
            throw TargetDispatcherError.activationFailed(target)
        }

        if target == .claudeCode, claudeCodeMode == .terminal {
            bootstrapTerminalCommandIfNeeded("claude", for: app)
        }

        if target == .codex {
            bootstrapTerminalCommandIfNeeded("codex", for: app)
        }
    }

    func requestAccessibilityPermission() {
        permissionCenter.requestAccessibilityPromptIfNeeded()
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func runningOrLaunch(_ target: TargetApp, activate: Bool, claudeCodeMode: ClaudeCodeMode) throws -> NSRunningApplication {
        if let running = runningApplication(for: target, claudeCodeMode: claudeCodeMode) {
            return running
        }

        guard let appURL = firstInstalledAppURL(for: target, claudeCodeMode: claudeCodeMode) else {
            throw TargetDispatcherError.appUnavailable(target)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if let launched = runningApplication(for: target, claudeCodeMode: claudeCodeMode) {
                return launched
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        throw TargetDispatcherError.appUnavailable(target)
    }

    private func runningApplication(for target: TargetApp, claudeCodeMode: ClaudeCodeMode) -> NSRunningApplication? {
        for bundleID in target.preferredBundleIdentifiers(claudeCodeMode: claudeCodeMode) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return app
            }
        }
        return nil
    }

    private func firstInstalledAppURL(for target: TargetApp, claudeCodeMode: ClaudeCodeMode) -> URL? {
        for bundleID in target.preferredBundleIdentifiers(claudeCodeMode: claudeCodeMode) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        return nil
    }

    private func bootstrapTerminalCommandIfNeeded(_ command: String, for app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else {
            return
        }
        let sessionKey = "\(bundleID)::\(command)"
        guard !bootstrappedSessionKeys.contains(sessionKey) else {
            return
        }

        let started: Bool
        switch bundleID {
        case "com.apple.Terminal":
            started = runAppleScript(
                """
                tell application "Terminal"
                    activate
                    if not (exists front window) then
                        do script "\(command)"
                    else
                        do script "\(command)" in front window
                    end if
                end tell
                """
            )
        case "com.googlecode.iterm2":
            started = runAppleScript(
                """
                tell application "iTerm"
                    activate
                    if (count of windows) = 0 then
                        create window with default profile
                    end if
                    tell current session of current window
                        write text "\(command)"
                    end tell
                end tell
                """
            )
        default:
            started = false
        }

        if started {
            bootstrappedSessionKeys.insert(sessionKey)
            // Give CLI a moment to initialize before paste.
            Thread.sleep(forTimeInterval: 0.45)
        }
    }

    private func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            print("[2relay] AppleScript failed: \(error)")
            return false
        }

        return true
    }

    private func injectCommandV() throws {
        permissionCenter.refreshFromSystem()
        guard permissionCenter.isAccessibilityTrusted(retryCount: 6, retryDelay: 0.12) else {
            requestAccessibilityPermission()
            let executablePath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? "unknown"
            print("[2relay] accessibility trust check failed for executable: \(executablePath)")
            throw TargetDispatcherError.accessibilityPermissionRequired
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            throw TargetDispatcherError.pasteEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
