import SwiftUI
import TwoRelayCore

@main
struct TwoRelayWrapperApp: App {
    private let coreApp = TwoRelayCoreApp()

    var body: some Scene {
        coreApp.body
    }
}
