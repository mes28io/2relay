import SwiftUI
import TwoRelayCore

@main
struct TwoRelayApp: App {
    private let coreApp = TwoRelayCoreApp()

    var body: some Scene {
        coreApp.body
    }
}
