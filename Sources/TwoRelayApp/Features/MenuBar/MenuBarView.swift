import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    let canCheckForUpdates: Bool
    let onOpenMain: () -> Void
    let onCheckForUpdates: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            Button("Open 2relay") {
                // Let the menu close before bringing app window to front.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    onOpenMain()
                }
            }

            Button("Settings...") {
                onOpenSettings()
            }

            Button("Check for Updates...") {
                onCheckForUpdates()
            }
            .disabled(!canCheckForUpdates)

            Button("Status: \(state.overlayState.title)") {}
                .disabled(true)
            Button("Hotkey: \(state.activeHotkeyDisplayText)") {}
                .disabled(true)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
