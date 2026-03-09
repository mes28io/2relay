import XCTest
@testable import TwoRelayApp

final class TargetAppTests: XCTestCase {
    func testPreferredBundleIdentifiers() {
        XCTAssertEqual(TargetApp.clipboard.displayName, "Anywhere")
        XCTAssertEqual(
            TargetApp.clipboard.preferredBundleIdentifiers(),
            []
        )
    }
}
