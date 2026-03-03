import XCTest
@testable import TwoRelayApp

final class TargetAppTests: XCTestCase {
    func testPreferredBundleIdentifiers() {
        XCTAssertEqual(TargetApp.claudeCode.displayName, "Claude Code")
        XCTAssertTrue(
            TargetApp.claudeCode
                .preferredBundleIdentifiers(claudeCodeMode: .terminal)
                .contains("com.apple.Terminal")
        )
        XCTAssertTrue(
            TargetApp.claudeCode
                .preferredBundleIdentifiers(claudeCodeMode: .cursorExtension)
                .contains("com.todesktop.230313mzl4w4u92")
        )

        XCTAssertEqual(TargetApp.codex.displayName, "Codex")
        XCTAssertTrue(
            TargetApp.codex
                .preferredBundleIdentifiers(claudeCodeMode: .terminal)
                .contains("com.apple.Terminal")
        )
        XCTAssertTrue(
            TargetApp.codex
                .preferredBundleIdentifiers(claudeCodeMode: .terminal)
                .contains("com.googlecode.iterm2")
        )

        XCTAssertEqual(TargetApp.clipboard.displayName, "Anywhere")
        XCTAssertEqual(
            TargetApp.clipboard
                .preferredBundleIdentifiers(claudeCodeMode: .terminal),
            []
        )
    }
}
