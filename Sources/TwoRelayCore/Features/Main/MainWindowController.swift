import AppKit
import Combine
import SwiftUI

@MainActor
final class MainWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?
    private let layoutState = MainLayoutState()
    private var cancellables = Set<AnyCancellable>()
    private var onboardingVisibilityCancellable: AnyCancellable?
    private weak var sidebarToggleButton: NSButton?

    override init() {
        super.init()
        layoutState.$isSidebarCollapsed
            .sink { [weak self] _ in
                self?.updateSidebarToggleButtonAppearance()
            }
            .store(in: &cancellables)
    }

    func present(
        state: AppState,
        permissionCenter: PermissionCenter,
        misspellingDictionary: MisspellingDictionary,
        onRunWhisperTestFlow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHelp: @escaping () -> Void,
        canCheckForUpdates: Bool,
        updatesDisabledReason: String?,
        onCheckForUpdates: @escaping () -> Void
    ) {
        if window == nil {
            window = makeWindow(
                state: state,
                permissionCenter: permissionCenter,
                misspellingDictionary: misspellingDictionary,
                onRunWhisperTestFlow: onRunWhisperTestFlow,
                onOpenSettings: onOpenSettings,
                onOpenHelp: onOpenHelp,
                canCheckForUpdates: canCheckForUpdates,
                updatesDisabledReason: updatesDisabledReason,
                onCheckForUpdates: onCheckForUpdates
            )
        } else {
            window?.contentView = NSHostingView(
                rootView: makeRootView(
                    state: state,
                    permissionCenter: permissionCenter,
                    misspellingDictionary: misspellingDictionary,
                    onRunWhisperTestFlow: onRunWhisperTestFlow,
                    onOpenSettings: onOpenSettings,
                    onOpenHelp: onOpenHelp,
                    canCheckForUpdates: canCheckForUpdates,
                    updatesDisabledReason: updatesDisabledReason,
                    onCheckForUpdates: onCheckForUpdates
                )
            )
        }

        guard let window else {
            return
        }

        onboardingVisibilityCancellable = state.$hasCompletedOnboarding
            .removeDuplicates()
            .sink { [weak self] completed in
                self?.sidebarToggleButton?.isHidden = !completed
            }
        sidebarToggleButton?.isHidden = !state.hasCompletedOnboarding

        if NSApp.activationPolicy() != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }
        AppBranding.applyDockIcon()

        center(window: window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.unhide(nil)
        _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        // Menu-bar menu dismissal can re-focus the previous app after a short delay.
        // Pulse activation once more so 2relay reliably remains frontmost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            _ = NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow(
        state: AppState,
        permissionCenter: PermissionCenter,
        misspellingDictionary: MisspellingDictionary,
        onRunWhisperTestFlow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHelp: @escaping () -> Void,
        canCheckForUpdates: Bool,
        updatesDisabledReason: String?,
        onCheckForUpdates: @escaping () -> Void
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "2relay"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = NSColor(
            calibratedRed: 250 / 255,
            green: 248 / 255,
            blue: 242 / 255,
            alpha: 1
        )
        window.minSize = NSSize(width: 1100, height: 800)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: makeRootView(
                state: state,
                permissionCenter: permissionCenter,
                misspellingDictionary: misspellingDictionary,
                onRunWhisperTestFlow: onRunWhisperTestFlow,
                onOpenSettings: onOpenSettings,
                onOpenHelp: onOpenHelp,
                canCheckForUpdates: canCheckForUpdates,
                updatesDisabledReason: updatesDisabledReason,
                onCheckForUpdates: onCheckForUpdates
            )
        )
        attachSidebarToggleAccessory(to: window)
        return window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func makeRootView(
        state: AppState,
        permissionCenter: PermissionCenter,
        misspellingDictionary: MisspellingDictionary,
        onRunWhisperTestFlow: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenHelp: @escaping () -> Void,
        canCheckForUpdates: Bool,
        updatesDisabledReason: String?,
        onCheckForUpdates: @escaping () -> Void
    ) -> some View {
        MainView(
            state: state,
            permissionCenter: permissionCenter,
            misspellingDictionary: misspellingDictionary,
            layoutState: layoutState,
            onRunWhisperTestFlow: onRunWhisperTestFlow,
            onOpenSettings: onOpenSettings,
            onOpenHelp: onOpenHelp,
            canCheckForUpdates: canCheckForUpdates,
            updatesDisabledReason: updatesDisabledReason,
            onCheckForUpdates: onCheckForUpdates
        )
    }

    private func center(window: NSWindow) {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            window.center()
            return
        }

        let frame = screen.visibleFrame
        let x = frame.midX - (window.frame.width / 2)
        let y = frame.midY - (window.frame.height / 2)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func attachSidebarToggleAccessory(to window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .left

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        let button = NSButton(title: "", target: self, action: #selector(toggleSidebar))
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.controlSize = .small
        button.imageScaling = .scaleProportionallyUpOrDown
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false

        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])

        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
        sidebarToggleButton = button
        updateSidebarToggleButtonAppearance()
    }

    @objc
    private func toggleSidebar() {
        layoutState.isSidebarCollapsed.toggle()
    }

    private func updateSidebarToggleButtonAppearance() {
        guard let button = sidebarToggleButton else {
            return
        }

        let symbolName = layoutState.isSidebarCollapsed ? "sidebar.right" : "sidebar.left"
        let fallbackName = layoutState.isSidebarCollapsed ? "chevron.right" : "chevron.left"
        let baseImage =
            NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        button.image = baseImage?.withSymbolConfiguration(symbolConfig)
        button.contentTintColor = NSColor(
            calibratedRed: 79 / 255,
            green: 78 / 255,
            blue: 78 / 255,
            alpha: 0.85
        )
        button.toolTip = layoutState.isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar"
    }
}
