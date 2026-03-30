import Carbon.HIToolbox
import AppKit
import Combine
import Foundation
import KeyboardShortcuts

enum RelayHotkeyDefaults {
    static let systemInputSourceControlSpaceID = 60
    static let systemInputSourceControlOptionSpaceID = 61

    /// Default hands-free shortcut: Fn+Space
    static let handsFreeFnSpace = KeyboardShortcuts.Shortcut(.space, modifiers: [.function])

    static let preferred = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])
    static let fallbackControlOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .option])
    static let fallbackControlShift = KeyboardShortcuts.Shortcut(.space, modifiers: [.control, .shift])
    static let fallbackCommandOption = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .option])
    static let fallbackCommandShift = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])

    static var fallbackCandidates: [KeyboardShortcuts.Shortcut] {
        [
            handsFreeFnSpace,
            fallbackControlOption,
            fallbackControlShift,
            fallbackCommandOption,
            fallbackCommandShift
        ]
    }
}

extension KeyboardShortcuts.Name {
    /// Hands-free toggle shortcut (default: Fn+Space)
    static let relayListen = Self(
        "relayListen",
        default: RelayHotkeyDefaults.handsFreeFnSpace
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

/// Monitors AirPods stem double-press (Next Track media key) for hands-free toggle.
private final class MediaKeyMonitor {
    private let instanceID = UUID().uuidString.prefix(8)
    private let onToggle: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isActive = false

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle
        print("[2relay] media key monitor init: \(instanceID)")
    }

    deinit {
        print("[2relay] media key monitor deinit: \(instanceID)")
        stop()
    }

    func start() {
        guard !isActive else { return }

        // NX_SYSDEFINED = 14 — system-defined events including media keys
        let eventMask: CGEventMask = 1 << 14
        let callback: CGEventTapCallBack = { _, _, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handleEvent(event)
            return Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[2relay] media key monitor: failed to create event tap (accessibility permission may be needed)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isActive = true
        print("[2relay] media key monitor enabled (\(instanceID))")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if isActive {
            print("[2relay] media key monitor disabled (\(instanceID))")
        }
        isActive = false
    }

    private func handleEvent(_ event: CGEvent) {
        // System-defined events (type 14) with subtype 8 are media/AUX key events
        guard event.type.rawValue == 14 else { return }

        let nsEvent = NSEvent(cgEvent: event)
        guard let nsEvent, nsEvent.subtype.rawValue == 8 else { return }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyState = (data1 & 0xFF00) >> 8

        // keyCode 17 = Next Track (AirPods double-press)
        // keyState: 0x0A = key down, 0x0B = key up
        guard keyCode == 17, keyState == 0x0A else { return }

        print("[2relay] AirPods double-press detected (Next Track)")
        Task { @MainActor in
            onToggle()
        }
    }
}

// MARK: - HotkeyManager

@MainActor
final class HotkeyManager: ObservableObject {
    private enum RegistrationReason {
        case startup
        case preferencesChange
        case lifecycleRecovery
    }

    private let appState: AppState
    private let instanceID = UUID().uuidString.prefix(8)

    // Push-to-talk: Fn key hold (always active)
    private var functionKeyMonitor: FunctionKeyMonitor!
    private var fnKeyIsHeld = false

    // Hands-free toggle: configurable shortcut (default Fn+Space)
    private var hotkeyMonitor: CarbonHotkeyMonitor!
    private var keyEventFallbackMonitor: KeyEventFallbackMonitor!
    private var toggleKeyIsHeld = false
    private var toggleListening = false
    private var lastRegisteredShortcut: KeyboardShortcuts.Shortcut?

    // AirPods: double-press stem = hands-free toggle
    private var mediaKeyMonitor: MediaKeyMonitor!

    private var isRecorderActive = false
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        print("[2relay] hotkey manager init: \(instanceID)")

        // Push-to-talk via Fn hold
        functionKeyMonitor = FunctionKeyMonitor(
            onKeyDown: { [weak self] in
                self?.handleFnDown()
            },
            onKeyUp: { [weak self] in
                self?.handleFnUp()
            }
        )

        // AirPods double-press stem = hands-free toggle
        mediaKeyMonitor = MediaKeyMonitor(
            onToggle: { [weak self] in
                self?.handleAirPodsToggle()
            }
        )

        // Hands-free toggle via configurable shortcut
        hotkeyMonitor = CarbonHotkeyMonitor(
            onKeyDown: { [weak self] in
                self?.handleToggleDown()
            },
            onKeyUp: { [weak self] in
                self?.handleToggleUp()
            }
        )
        keyEventFallbackMonitor = KeyEventFallbackMonitor(
            onKeyDown: { [weak self] in
                self?.handleToggleDown()
            },
            onKeyUp: { [weak self] in
                self?.handleToggleUp()
            }
        )

        registerAll(reason: .startup)
        bindShortcutChanges()
        bindRecorderActivity()
        bindLifecycleChanges()
    }

    deinit {
        print("[2relay] hotkey manager deinit: \(instanceID)")
    }

    // MARK: - Registration

    private func registerAll(reason: RegistrationReason) {
        releaseAllHeldKeys()

        // Always start Fn push-to-talk monitor
        functionKeyMonitor.start()

        // Always start AirPods media key monitor
        mediaKeyMonitor.start()

        // Register the hands-free toggle shortcut
        registerHandsFreeShortcut(reason: reason)
    }

    private func registerHandsFreeShortcut(reason: RegistrationReason) {
        let selectedShortcut = KeyboardShortcuts.getShortcut(for: .relayListen)
            ?? RelayHotkeyDefaults.handsFreeFnSpace

        if KeyboardShortcuts.getShortcut(for: .relayListen) == nil {
            KeyboardShortcuts.setShortcut(selectedShortcut, for: .relayListen)
        }

        if selectedShortcut == lastRegisteredShortcut, reason == .preferencesChange {
            return
        }

        keyEventFallbackMonitor.start(shortcut: selectedShortcut)

        let status = hotkeyMonitor.register(shortcut: selectedShortcut)
        if status == noErr {
            lastRegisteredShortcut = selectedShortcut
            print("[2relay] hands-free hotkey registered (\(hotkeyMonitor.activeTargetLabel)): \(selectedShortcut.description)")
            if reason == .preferencesChange {
                appState.reportStatus("Hands-free shortcut updated: \(selectedShortcut.description)", level: .success)
            }
            return
        }

        print("[2relay] hands-free hotkey registration failed for \(selectedShortcut.description): \(status)")

        // Try fallbacks
        for fallback in RelayHotkeyDefaults.fallbackCandidates where fallback != selectedShortcut {
            let fallbackStatus = hotkeyMonitor.register(shortcut: fallback)
            if fallbackStatus == noErr {
                KeyboardShortcuts.setShortcut(fallback, for: .relayListen)
                lastRegisteredShortcut = fallback
                keyEventFallbackMonitor.start(shortcut: fallback)
                print("[2relay] hands-free hotkey fallback registered (\(hotkeyMonitor.activeTargetLabel)): \(fallback.description)")
                appState.reportStatus(
                    "Shortcut \(selectedShortcut.description) unavailable. Using \(fallback.description) instead.",
                    level: .warning
                )
                return
            }
        }

        hotkeyMonitor.unregister()
        keyEventFallbackMonitor.stop()
        print("[2relay] no hands-free hotkey could be registered")
        appState.reportStatus(
            "Could not register hands-free shortcut. Choose another in Settings > Shortcuts.",
            level: .error
        )
    }

    // MARK: - Push-to-talk (Fn hold)

    private func handleFnDown() {
        guard !isRecorderActive, !fnKeyIsHeld else { return }
        fnKeyIsHeld = true
        print("[2relay] Fn down (push-to-talk)")
        appState.startListening()
    }

    private func handleFnUp() {
        guard !isRecorderActive, fnKeyIsHeld else { return }
        fnKeyIsHeld = false
        print("[2relay] Fn up (push-to-talk)")
        appState.stopListening()
    }

    // MARK: - AirPods toggle (double-press stem)

    private func handleAirPodsToggle() {
        guard !isRecorderActive else { return }
        print("[2relay] AirPods toggle (hands-free)")

        if toggleListening {
            appState.stopListening()
        } else {
            appState.startListening()
        }
        toggleListening.toggle()
    }

    // MARK: - Hands-free toggle (configurable shortcut)

    private func handleToggleDown() {
        guard !isRecorderActive, !toggleKeyIsHeld else { return }
        toggleKeyIsHeld = true
        print("[2relay] toggle key down (hands-free)")
    }

    private func handleToggleUp() {
        guard !isRecorderActive, toggleKeyIsHeld else { return }
        toggleKeyIsHeld = false
        print("[2relay] toggle key up (hands-free)")

        if toggleListening {
            appState.stopListening()
        } else {
            appState.startListening()
        }
        toggleListening.toggle()
    }

    // MARK: - Key release safety

    private func releaseAllHeldKeys() {
        if fnKeyIsHeld {
            fnKeyIsHeld = false
            if appState.isListening {
                appState.stopListening()
            }
        }
        if toggleKeyIsHeld {
            toggleKeyIsHeld = false
        }
        toggleListening = false
    }

    // MARK: - Bindings

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
                self?.registerHandsFreeShortcut(reason: .preferencesChange)
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
                self?.registerAll(reason: .lifecycleRecovery)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.registerAll(reason: .lifecycleRecovery)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.releaseAllHeldKeys()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.releaseAllHeldKeys()
            }
            .store(in: &cancellables)
    }

    private func setRecorderActive(_ isActive: Bool) {
        guard isRecorderActive != isActive else { return }
        isRecorderActive = isActive

        if isActive {
            releaseAllHeldKeys()
            hotkeyMonitor.unregister()
            keyEventFallbackMonitor.stop()
            functionKeyMonitor.stop()
            mediaKeyMonitor.stop()
        } else {
            registerAll(reason: .preferencesChange)
        }
    }
}
