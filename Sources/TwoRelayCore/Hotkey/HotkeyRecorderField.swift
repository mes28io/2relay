import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

@MainActor
private final class HotkeyRecorderButton: NSButton {
    private let recorderNotification = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")
    private let shortcutChangeNotification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

    var shortcutName: KeyboardShortcuts.Name {
        didSet {
            updateShortcutTitle()
        }
    }

    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    private var localMonitor: Any?
    private var shortcutObserver: NSObjectProtocol?
    private var isRecordingShortcut = false

    init(name: KeyboardShortcuts.Name, onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?) {
        self.shortcutName = name
        self.onChange = onChange
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        font = .systemFont(ofSize: 12, weight: .medium)
        isBordered = true
        focusRingType = .default
        updateShortcutTitle()

        let observedName = name
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: shortcutChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
                  name == observedName else {
                return
            }

            Task { @MainActor in
                self?.updateShortcutTitle()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(170, size.width + 18), height: max(28, size.height + 8))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            endRecording()
        }
    }

    @objc
    private func toggleRecording() {
        if isRecordingShortcut {
            endRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard !isRecordingShortcut else {
            return
        }

        isRecordingShortcut = true
        title = "Press shortcut"
        NotificationCenter.default.post(name: recorderNotification, object: nil, userInfo: ["isActive": true])

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleRecordingEvent(event) ?? event
        }
    }

    private func endRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        guard isRecordingShortcut else {
            return
        }

        isRecordingShortcut = false
        NotificationCenter.default.post(name: recorderNotification, object: nil, userInfo: ["isActive": false])
        updateShortcutTitle()
    }

    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            let point = convert(event.locationInWindow, from: nil)
            if !bounds.contains(point) {
                endRecording()
            }
            return event
        case .keyDown:
            return handleKeyDown(event)
        default:
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            return nil
        }

        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            KeyboardShortcuts.setShortcut(nil, for: shortcutName)
            onChange?(nil)
            endRecording()
            return nil
        }

        guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return nil
        }

        KeyboardShortcuts.setShortcut(shortcut, for: shortcutName)
        onChange?(shortcut)
        endRecording()
        return nil
    }

    private func updateShortcutTitle() {
        title = KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? "Record Shortcut"
        invalidateIntrinsicContentSize()
    }
}

private struct HotkeyRecorderRepresentable: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        HotkeyRecorderButton(name: name, onChange: onChange)
    }

    func updateNSView(_ nsView: HotkeyRecorderButton, context: Context) {
        nsView.shortcutName = name
        nsView.onChange = onChange
    }
}

struct HotkeyRecorderField: View {
    let name: KeyboardShortcuts.Name
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil

    var body: some View {
        HotkeyRecorderRepresentable(name: name, onChange: onChange)
            .frame(minWidth: 170, idealWidth: 220, maxWidth: 260, minHeight: 28, maxHeight: 28, alignment: .leading)
    }
}
