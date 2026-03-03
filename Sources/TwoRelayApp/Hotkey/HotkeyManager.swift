import Combine
import Foundation
import KeyboardShortcuts

enum RelayHotkeyDefaults {
    static let preferred = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])
    static let fallbackControlOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option])
    static let fallbackControlShift = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])

    static let legacyFunction = KeyboardShortcuts.Shortcut(.space, modifiers: [.function])
    static let legacyOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])

    static var migratableShortcuts: [KeyboardShortcuts.Shortcut] {
        [
            fallbackControlOption,
            fallbackControlShift,
            legacyFunction,
            legacyOption
        ]
    }
}

extension KeyboardShortcuts.Name {
    static let relayListen = Self(
        "relayListen",
        default: RelayHotkeyDefaults.preferred
    )
}

@MainActor
final class HotkeyManager: ObservableObject {
    private let appState: AppState
    private var keyIsHeld = false
    private var toggleListening = false
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        migrateShortcutIfNeeded()
        resolveSystemConflictsIfNeeded()
        bindModeChanges()
        registerCallbacks()
    }

    private func migrateShortcutIfNeeded() {
        let current = KeyboardShortcuts.getShortcut(for: .relayListen)
        if current == nil
            || RelayHotkeyDefaults.migratableShortcuts.contains(where: { $0 == current }) {
            let preferred = recommendedDefaultShortcut()
            KeyboardShortcuts.setShortcut(preferred, for: .relayListen)
            appState.reportStatus("Hotkey default set to \(preferred.description).", level: .info)
        }
    }

    private func resolveSystemConflictsIfNeeded() {
        guard let current = KeyboardShortcuts.getShortcut(for: .relayListen) else {
            return
        }

        if current == RelayHotkeyDefaults.preferred, isSymbolicHotkeyEnabled(id: 60) {
            let fallback = recommendedFallbackShortcut()
            KeyboardShortcuts.setShortcut(fallback, for: .relayListen)
            appState.reportStatus(
                "Control + Space is reserved by macOS Input Sources. Switched to \(fallback.description). Disable the macOS shortcut in System Settings > Keyboard > Keyboard Shortcuts > Input Sources to keep Control + Space.",
                level: .warning
            )
            return
        }

        if current == RelayHotkeyDefaults.fallbackControlOption, isSymbolicHotkeyEnabled(id: 61) {
            let fallback = RelayHotkeyDefaults.fallbackControlShift
            KeyboardShortcuts.setShortcut(fallback, for: .relayListen)
            appState.reportStatus(
                "Both Control + Space and Control + Option + Space are reserved by macOS. Switched to \(fallback.description).",
                level: .warning
            )
        }
    }

    private func recommendedDefaultShortcut() -> KeyboardShortcuts.Shortcut {
        if isSymbolicHotkeyEnabled(id: 60) {
            return recommendedFallbackShortcut()
        }
        return RelayHotkeyDefaults.preferred
    }

    private func recommendedFallbackShortcut() -> KeyboardShortcuts.Shortcut {
        if !isSymbolicHotkeyEnabled(id: 61) {
            return RelayHotkeyDefaults.fallbackControlOption
        }
        return RelayHotkeyDefaults.fallbackControlShift
    }

    private func isSymbolicHotkeyEnabled(id: Int) -> Bool {
        let hotkeysKey = "AppleSymbolicHotKeys" as CFString
        let domain = "com.apple.symbolichotkeys" as CFString
        guard let rawHotkeys = CFPreferencesCopyAppValue(hotkeysKey, domain) else {
            return false
        }

        guard let hotkeys = rawHotkeys as? [AnyHashable: Any] else {
            return false
        }

        let entry = hotkeys.first { key, _ in
            if let numeric = key as? NSNumber {
                return numeric.intValue == id
            }
            return Int(String(describing: key)) == id
        }?.value as? [AnyHashable: Any]

        guard let entry else {
            return false
        }

        if let enabled = entry["enabled"] as? Bool {
            return enabled
        }
        if let enabled = entry["enabled"] as? NSNumber {
            return enabled.boolValue
        }
        return false
    }

    private func bindModeChanges() {
        appState.$hotkeyMode
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.modeDidChange()
            }
            .store(in: &cancellables)
    }

    func modeDidChange() {
        if appState.hotkeyMode == .pushToTalk && toggleListening {
            toggleListening = false
            appState.stopListening()
        }
    }

    private func registerCallbacks() {
        KeyboardShortcuts.onKeyDown(for: .relayListen) { [weak self] in
            Task { @MainActor in
                self?.handleKeyDown()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .relayListen) { [weak self] in
            Task { @MainActor in
                self?.handleKeyUp()
            }
        }
    }

    private func handleKeyDown() {
        guard !keyIsHeld else {
            return
        }

        keyIsHeld = true

        if appState.hotkeyMode == .pushToTalk {
            appState.startListening()
        }
    }

    private func handleKeyUp() {
        defer {
            keyIsHeld = false
        }

        switch appState.hotkeyMode {
        case .pushToTalk:
            appState.stopListening()
        case .toggle:
            if toggleListening {
                appState.stopListening()
            } else {
                appState.startListening()
            }
            toggleListening.toggle()
        }
    }
}
