import KeyboardShortcuts
import SwiftUI

struct HotkeyRecorderField: View {
    let name: KeyboardShortcuts.Name
    var onChange: ((KeyboardShortcuts.Shortcut?) -> Void)? = nil

    var body: some View {
        KeyboardShortcuts.Recorder(for: name, onChange: onChange)
            .frame(minWidth: 170, idealWidth: 220, maxWidth: 260, alignment: .leading)
    }
}
