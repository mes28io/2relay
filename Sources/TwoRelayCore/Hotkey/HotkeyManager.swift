import Carbon.HIToolbox
import AppKit
import Combine
import Foundation
import KeyboardShortcuts

enum RelayHotkeyDefaults {
    static let systemInputSourceControlSpaceID = 60
    static let systemInputSourceControlOptionSpaceID = 61

    static let preferred = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])
    static let fallbackControlOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option])
    static let fallbackControlShift = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])
    static let fallbackCommandOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .option])
    static let fallbackCommandShift = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

    static let legacyFunction = KeyboardShortcuts.Shortcut(.space, modifiers: [.function])
    static let legacyOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])

    static var migratableShortcuts: [KeyboardShortcuts.Shortcut] {
        [
            fallbackControlOption,
            fallbackControlShift,
            fallbackCommandOption,
            fallbackCommandShift,
            legacyFunction,
            legacyOption
        ]
    }

    static var fallbackCandidates: [KeyboardShortcuts.Shortcut] {
        [
            fallbackControlOption,
            fallbackControlShift,
            fallbackCommandOption,
            fallbackCommandShift
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
    private enum RegistrationTarget: CaseIterable {
        case application
        case dispatcher

        var label: String {
            switch self {
            case .application:
                return "application"
            case .dispatcher:
                return "dispatcher"
            }
        }

        var eventTarget: EventTargetRef? {
            switch self {
            case .application:
                return GetApplicationEventTarget()
            case .dispatcher:
                return GetEventDispatcherTarget()
            }
        }
    }

    private static let signature: OSType = 0x32524C59 // "2RLY"
    private static let identifier: UInt32 = 1

    private let onKeyDown: @MainActor () -> Void
    private let onKeyUp: @MainActor () -> Void

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeTarget: RegistrationTarget?

    var activeTargetLabel: String {
        activeTarget?.label ?? "none"
    }

    init(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    deinit {
        unregister()
        removeEventHandler()
    }

    @discardableResult
    func register(shortcut: KeyboardShortcuts.Shortcut) -> OSStatus {
        unregister()
        activeTarget = nil
        var lastStatus = OSStatus(eventNotHandledErr)

        for target in RegistrationTarget.allCases {
            let handlerStatus = installEventHandler(on: target)
            guard handlerStatus == noErr else {
                lastStatus = handlerStatus
                print("[2relay] failed to install Carbon handler on \(target.label) target: \(handlerStatus)")
                continue
            }

            let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
            var newHotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.carbonKeyCode),
                UInt32(shortcut.carbonModifiers),
                hotKeyID,
                target.eventTarget,
                0,
                &newHotKeyRef
            )
            lastStatus = status

            if status == noErr {
                hotKeyRef = newHotKeyRef
                activeTarget = target
                return status
            }

            print("[2relay] Carbon register failed on \(target.label) target: \(status)")
        }

        return lastStatus
    }

    func unregister() {
        guard let hotKeyRef else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installEventHandler(on target: RegistrationTarget) -> OSStatus {
        if eventHandlerRef != nil, activeTarget == target {
            return noErr
        }

        removeEventHandler()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(
            target.eventTarget,
            Self.eventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status == noErr {
            activeTarget = target
        } else {
            activeTarget = nil
        }

        return status
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

private final class KeyEventFallbackMonitor {
    private let instanceID = UUID().uuidString.prefix(8)
    private let onKeyDown: @MainActor () -> Void
    private let onKeyUp: @MainActor () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var trackedShortcut: KeyboardShortcuts.Shortcut?
    private var isActive = false

    init(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        print("[2relay] key event fallback monitor init: \(instanceID)")
    }

    deinit {
        print("[2relay] key event fallback monitor deinit: \(instanceID)")
        stop()
    }

    func start(shortcut: KeyboardShortcuts.Shortcut) {
        trackedShortcut = shortcut
        guard !isActive else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
        isActive = true
        print("[2relay] key event fallback monitor enabled (\(instanceID))")
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if isActive {
            print("[2relay] key event fallback monitor disabled (\(instanceID))")
        }

        trackedShortcut = nil
        isActive = false
    }

    private func handle(_ event: NSEvent) {
        guard let trackedShortcut else {
            return
        }

        guard let eventShortcut = KeyboardShortcuts.Shortcut(event: event) else {
            return
        }

        guard eventShortcut == trackedShortcut else {
            return
        }

        switch event.type {
        case .keyDown:
            Task { @MainActor in
                onKeyDown()
            }
        case .keyUp:
            Task { @MainActor in
                onKeyUp()
            }
        default:
            return
        }
    }
}

private final class FunctionKeyMonitor {
    private let instanceID = UUID().uuidString.prefix(8)
    private let onKeyDown: @MainActor () -> Void
    private let onKeyUp: @MainActor () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isActive = false
    private var isFunctionKeyHeld = false

    init(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        print("[2relay] function key monitor init: \(instanceID)")
    }

    deinit {
        print("[2relay] function key monitor deinit: \(instanceID)")
        stop()
    }

    func start() {
        guard !isActive else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
            return event
        }
        isActive = true
        print("[2relay] function key monitor enabled (\(instanceID))")
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if isActive {
            print("[2relay] function key monitor disabled (\(instanceID))")
        }

        isFunctionKeyHeld = false
        isActive = false
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            return
        }

        let functionKeyHeld = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.function)
        guard functionKeyHeld != isFunctionKeyHeld else {
            return
        }

        isFunctionKeyHeld = functionKeyHeld
        Task { @MainActor in
            if functionKeyHeld {
                onKeyDown()
            } else {
                onKeyUp()
            }
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    private enum RegistrationReason {
        case startup
        case preferencesChange
        case lifecycleRecovery
    }

    private let appState: AppState
    private let instanceID = UUID().uuidString.prefix(8)
    private var hotkeyMonitor: CarbonHotkeyMonitor!
    private var keyEventFallbackMonitor: KeyEventFallbackMonitor!
    private var functionKeyMonitor: FunctionKeyMonitor!
    private var keyIsHeld = false
    private var toggleListening = false
    private var isRecorderActive = false
    private var lastRegisteredShortcut: KeyboardShortcuts.Shortcut?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        print("[2relay] hotkey manager init: \(instanceID)")
        hotkeyMonitor = CarbonHotkeyMonitor(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )
        keyEventFallbackMonitor = KeyEventFallbackMonitor(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )
        functionKeyMonitor = FunctionKeyMonitor(
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
        bindTriggerChanges()
        bindShortcutChanges()
        bindRecorderActivity()
        bindLifecycleChanges()
    }

    deinit {
        print("[2relay] hotkey manager deinit: \(instanceID)")
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
        releaseHeldHotkeyIfNeeded()

        if appState.hotkeyTrigger == .functionKey {
            hotkeyMonitor.unregister()
            keyEventFallbackMonitor.stop()
            functionKeyMonitor.start()
            lastRegisteredShortcut = nil

            if reason == .preferencesChange {
                appState.reportStatus("Hotkey updated: Fn", level: .success)
            }
            return
        }

        functionKeyMonitor.stop()

        var selectedShortcut = KeyboardShortcuts.getShortcut(for: .relayListen) ?? RelayHotkeyDefaults.preferred
        if KeyboardShortcuts.getShortcut(for: .relayListen) == nil {
            KeyboardShortcuts.setShortcut(selectedShortcut, for: .relayListen)
        }

        if hotkeyConflictsWithSystemShortcut(selectedShortcut),
           let nonConflictingFallback = RelayHotkeyDefaults.fallbackCandidates.first(where: {
               $0 != selectedShortcut && !hotkeyConflictsWithSystemShortcut($0)
           }) {
            let conflictingShortcut = selectedShortcut
            selectedShortcut = nonConflictingFallback
            KeyboardShortcuts.setShortcut(selectedShortcut, for: .relayListen)
            lastRegisteredShortcut = nil
            print(
                "[2relay] selected hotkey \(conflictingShortcut.description) conflicts with macOS input source shortcuts; switched to \(selectedShortcut.description)"
            )
            appState.reportStatus(
                "Hotkey \(conflictingShortcut.description) conflicts with macOS input source shortcuts. Switched to \(selectedShortcut.description).",
                level: .warning
            )
        }

        if selectedShortcut == lastRegisteredShortcut, reason == .preferencesChange {
            return
        }

        keyEventFallbackMonitor.start(shortcut: selectedShortcut)

        let status = hotkeyMonitor.register(shortcut: selectedShortcut)
        if status == noErr {
            lastRegisteredShortcut = selectedShortcut
            print("[2relay] hotkey registered (\(hotkeyMonitor.activeTargetLabel)): \(selectedShortcut.description)")
            if reason == .preferencesChange {
                appState.reportStatus("Hotkey updated: \(selectedShortcut.description)", level: .success)
            }
            return
        }

        print("[2relay] hotkey registration failed for \(selectedShortcut.description): \(status)")

        for fallback in RelayHotkeyDefaults.fallbackCandidates where fallback != selectedShortcut {
            if hotkeyConflictsWithSystemShortcut(fallback) {
                print("[2relay] skipping fallback \(fallback.description) due to macOS input source shortcut conflict")
                continue
            }

            let fallbackStatus = hotkeyMonitor.register(shortcut: fallback)
            if fallbackStatus == noErr {
                KeyboardShortcuts.setShortcut(fallback, for: .relayListen)
                lastRegisteredShortcut = fallback
                keyEventFallbackMonitor.start(shortcut: fallback)
                print("[2relay] hotkey fallback registered (\(hotkeyMonitor.activeTargetLabel)): \(fallback.description)")
                appState.reportStatus(
                    "Hotkey \(selectedShortcut.description) is unavailable on this Mac. Switched to \(fallback.description).",
                    level: .warning
                )
                return
            }

            print("[2relay] hotkey fallback registration failed for \(fallback.description): \(fallbackStatus)")
        }

        hotkeyMonitor.unregister()
        keyEventFallbackMonitor.stop()
        print("[2relay] no global hotkey could be registered")
        appState.reportStatus(
            "Could not register a global hotkey. Choose another shortcut in Settings > Shortcuts.",
            level: .error
        )
    }

    private func bindTriggerChanges() {
        appState.$hotkeyTrigger
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.registerCurrentShortcut(reason: .preferencesChange)
            }
            .store(in: &cancellables)
    }

    private func bindShortcutChanges() {
        let shortcutChangeNotification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")
        let keyboardShortcutsChanges = NotificationCenter.default.publisher(for: shortcutChangeNotification)
            .compactMap { $0.userInfo?["name"] as? KeyboardShortcuts.Name }
            .filter { $0 == .relayListen }
            .map { _ in () }

        let userDefaultsChanges = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .map { _ in () }

        keyboardShortcutsChanges
            .merge(with: userDefaultsChanges)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.registerCurrentShortcut(reason: .preferencesChange)
            }
            .store(in: &cancellables)
    }

    private func bindRecorderActivity() {
        let recorderNotification = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")
        NotificationCenter.default.publisher(for: recorderNotification)
            .compactMap { $0.userInfo?["isActive"] as? Bool }
            .removeDuplicates()
            .sink { [weak self] isActive in
                self?.setRecorderActive(isActive)
            }
            .store(in: &cancellables)
    }

    private func bindLifecycleChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .sink { [weak self] _ in
                self?.registerCurrentShortcut(reason: .lifecycleRecovery)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.registerCurrentShortcut(reason: .lifecycleRecovery)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.releaseHeldHotkeyIfNeeded()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.releaseHeldHotkeyIfNeeded()
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
        guard !isRecorderActive else {
            return
        }

        guard !keyIsHeld else {
            return
        }

        keyIsHeld = true
        print("[2relay] hotkey down")

        if appState.hotkeyMode == .pushToTalk {
            appState.startListening()
        }
    }

    private func handleKeyUp() {
        guard !isRecorderActive else {
            return
        }

        guard keyIsHeld else {
            return
        }

        defer {
            keyIsHeld = false
        }
        print("[2relay] hotkey up")

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

    private func releaseHeldHotkeyIfNeeded() {
        guard keyIsHeld else {
            return
        }

        keyIsHeld = false
        if appState.isListening {
            appState.stopListening()
        }
    }

    private func setRecorderActive(_ isActive: Bool) {
        guard isRecorderActive != isActive else {
            return
        }

        isRecorderActive = isActive

        if isActive {
            releaseHeldHotkeyIfNeeded()
            hotkeyMonitor.unregister()
            keyEventFallbackMonitor.stop()
            functionKeyMonitor.stop()
        } else {
            registerCurrentShortcut(reason: .preferencesChange)
        }
    }

    private func hotkeyConflictsWithSystemShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        if symbolicSystemShortcuts().contains(shortcut) {
            return true
        }

        if shortcut == RelayHotkeyDefaults.preferred {
            return symbolicHotkeyEnabled(RelayHotkeyDefaults.systemInputSourceControlSpaceID)
        }

        if shortcut == RelayHotkeyDefaults.fallbackControlOption {
            return symbolicHotkeyEnabled(RelayHotkeyDefaults.systemInputSourceControlOptionSpaceID)
        }

        return false
    }

    private func symbolicSystemShortcuts() -> [KeyboardShortcuts.Shortcut] {
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
              let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        return shortcuts.compactMap { shortcutInfo in
            guard (shortcutInfo[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let keyCode = shortcutInfo[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = shortcutInfo[kHISymbolicHotKeyModifiers] as? Int else {
                return nil
            }

            return KeyboardShortcuts.Shortcut(
                carbonKeyCode: keyCode,
                carbonModifiers: modifiers
            )
        }
    }

    private func symbolicHotkeyEnabled(_ keyID: Int) -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
              let hotkeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys"),
              let hotkey = hotkeys["\(keyID)"] as? [String: Any] else {
            return false
        }

        if let enabled = hotkey["enabled"] as? Bool {
            return enabled
        }

        if let enabled = hotkey["enabled"] as? NSNumber {
            return enabled.boolValue
        }

        return false
    }
}
