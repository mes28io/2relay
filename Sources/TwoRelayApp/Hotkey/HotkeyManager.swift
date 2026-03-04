import Carbon.HIToolbox
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

    static var fallbackCandidates: [KeyboardShortcuts.Shortcut] {
        [
            fallbackControlOption,
            fallbackControlShift
        ]
    }
}

extension KeyboardShortcuts.Name {
    static let relayListen = Self(
        "relayListen",
        default: RelayHotkeyDefaults.preferred
    )
}

private final class CarbonHotkeyMonitor {
    private static let signature: OSType = 0x32524C59 // "2RLY"
    private static let identifier: UInt32 = 1

    private let onKeyDown: @MainActor () -> Void
    private let onKeyUp: @MainActor () -> Void

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        installEventHandlerIfNeeded()
    }

    deinit {
        unregister()
        removeEventHandler()
    }

    @discardableResult
    func register(shortcut: KeyboardShortcuts.Shortcut) -> OSStatus {
        unregister()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode),
            UInt32(shortcut.carbonModifiers),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &newHotKeyRef
        )

        if status == noErr {
            hotKeyRef = newHotKeyRef
        }

        return status
    }

    func unregister() {
        guard let hotKeyRef else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.eventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            print("[2relay] failed to install Carbon hotkey handler: \(status)")
        }
    }

    private func removeEventHandler() {
        guard let eventHandlerRef else {
            return
        }

        RemoveEventHandler(eventHandlerRef)
        self.eventHandlerRef = nil
    }

    private static let eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let monitor = Unmanaged<CarbonHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        return monitor.handleEvent(eventRef)
    }

    private func handleEvent(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let readStatus = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard readStatus == noErr else {
            return readStatus
        }

        guard hotKeyID.signature == Self.signature, hotKeyID.id == Self.identifier else {
            return OSStatus(eventNotHandledErr)
        }

        let eventKind = GetEventKind(eventRef)
        if eventKind == UInt32(kEventHotKeyPressed) {
            Task { @MainActor in
                onKeyDown()
            }
            return noErr
        }

        if eventKind == UInt32(kEventHotKeyReleased) {
            Task { @MainActor in
                onKeyUp()
            }
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    private enum RegistrationReason {
        case startup
        case preferencesChange
    }

    private let appState: AppState
    private var hotkeyMonitor: CarbonHotkeyMonitor!
    private var keyIsHeld = false
    private var toggleListening = false
    private var lastRegisteredShortcut: KeyboardShortcuts.Shortcut?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        hotkeyMonitor = CarbonHotkeyMonitor(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )

        migrateShortcutIfNeeded()
        registerCurrentShortcut(reason: .startup)
        bindModeChanges()
        bindShortcutChanges()
    }

    private func migrateShortcutIfNeeded() {
        let current = KeyboardShortcuts.getShortcut(for: .relayListen)
        if current == nil
            || RelayHotkeyDefaults.migratableShortcuts.contains(where: { $0 == current }) {
            KeyboardShortcuts.setShortcut(RelayHotkeyDefaults.preferred, for: .relayListen)
            appState.reportStatus("Hotkey default set to \(RelayHotkeyDefaults.preferred.description).", level: .info)
        }
    }

    private func registerCurrentShortcut(reason: RegistrationReason) {
        let selectedShortcut = KeyboardShortcuts.getShortcut(for: .relayListen) ?? RelayHotkeyDefaults.preferred
        if KeyboardShortcuts.getShortcut(for: .relayListen) == nil {
            KeyboardShortcuts.setShortcut(selectedShortcut, for: .relayListen)
        }

        if selectedShortcut == lastRegisteredShortcut, reason != .startup {
            return
        }

        let status = hotkeyMonitor.register(shortcut: selectedShortcut)
        if status == noErr {
            lastRegisteredShortcut = selectedShortcut
            if reason == .preferencesChange {
                appState.reportStatus("Hotkey updated: \(selectedShortcut.description)", level: .success)
            }
            return
        }

        for fallback in RelayHotkeyDefaults.fallbackCandidates where fallback != selectedShortcut {
            let fallbackStatus = hotkeyMonitor.register(shortcut: fallback)
            if fallbackStatus == noErr {
                KeyboardShortcuts.setShortcut(fallback, for: .relayListen)
                lastRegisteredShortcut = fallback
                appState.reportStatus(
                    "Hotkey \(selectedShortcut.description) is unavailable on this Mac. Switched to \(fallback.description).",
                    level: .warning
                )
                return
            }
        }

        hotkeyMonitor.unregister()
        appState.reportStatus(
            "Could not register a global hotkey. Choose another shortcut in Settings > Shortcuts.",
            level: .error
        )
    }

    private func bindShortcutChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.registerCurrentShortcut(reason: .preferencesChange)
            }
            .store(in: &cancellables)
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
