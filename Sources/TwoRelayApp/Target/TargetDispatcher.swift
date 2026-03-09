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

    init(permissionCenter: PermissionCenter) {
        self.permissionCenter = permissionCenter
    }

    func activateAndPaste(text: String, target: TargetApp) throws {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw TargetDispatcherError.textIsEmpty
        }

        writeToPasteboard(prompt)

        // "Anywhere" target: paste into the currently focused input without switching apps.
        Thread.sleep(forTimeInterval: 0.15)
        try injectCommandV()
    }

    func ensureTargetIsRunning(_ target: TargetApp, activate: Bool) throws {
        if target == .clipboard {
            return
        }

        let app = try runningOrLaunch(target, activate: activate)
        guard !activate || app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) else {
            throw TargetDispatcherError.activationFailed(target)
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

    private func runningOrLaunch(_ target: TargetApp, activate: Bool) throws -> NSRunningApplication {
        if let running = runningApplication(for: target) {
            return running
        }

        guard let appURL = firstInstalledAppURL(for: target) else {
            throw TargetDispatcherError.appUnavailable(target)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if let launched = runningApplication(for: target) {
                return launched
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        throw TargetDispatcherError.appUnavailable(target)
    }

    private func runningApplication(for target: TargetApp) -> NSRunningApplication? {
        for bundleID in target.preferredBundleIdentifiers() {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return app
            }
        }
        return nil
    }

    private func firstInstalledAppURL(for target: TargetApp) -> URL? {
        for bundleID in target.preferredBundleIdentifiers() {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }
        return nil
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
