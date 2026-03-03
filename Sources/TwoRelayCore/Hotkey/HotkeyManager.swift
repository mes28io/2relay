import Combine
import Foundation
import KeyboardShortcuts

enum RelayHotkeyDefaults {
    static let preferred = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option])
    static let legacyControlSpace = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])
    static let legacyFunction = KeyboardShortcuts.Shortcut(.space, modifiers: [.function])
    static let legacyOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
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
        bindModeChanges()
        registerCallbacks()
    }

    private func migrateShortcutIfNeeded() {
        let current = KeyboardShortcuts.getShortcut(for: .relayListen)
        if current == nil
            || current == RelayHotkeyDefaults.legacyControlSpace
            || current == RelayHotkeyDefaults.legacyFunction
            || current == RelayHotkeyDefaults.legacyOption {
            KeyboardShortcuts.setShortcut(RelayHotkeyDefaults.preferred, for: .relayListen)
            appState.reportStatus("Hotkey migrated to Control + Option + Space to avoid macOS conflicts.", level: .info)
        }
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
