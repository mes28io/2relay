import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: ObservableObject {
    private var window: NSWindow?

    func present(
        state: AppState,
        permissionCenter: PermissionCenter,
        updaterController: UpdaterController
    ) {
        if window == nil {
            window = makeWindow(
                state: state,
                permissionCenter: permissionCenter,
                updaterController: updaterController
            )
        } else {
            window?.contentView = NSHostingView(
                rootView: SettingsView(
                    state: state,
                    permissionCenter: permissionCenter,
                    updaterController: updaterController
                )
                    .frame(width: 760, height: 560)
                    .padding(20)
            )
        }

        guard let window else {
            return
        }

        center(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    private func makeWindow(
        state: AppState,
        permissionCenter: PermissionCenter,
        updaterController: UpdaterController
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "2relay Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(
                state: state,
                permissionCenter: permissionCenter,
                updaterController: updaterController
            )
                .frame(width: 760, height: 560)
                .padding(20)
        )
        return window
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
}
