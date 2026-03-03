import XCTest
@testable import TwoRelayApp

final class PromptCleanerTests: XCTestCase {
    func testCleanerReturnsGoalOnlyAsBullet() {
        let cleaner = PromptCleaner()
        let rawText = "Hey claude, today we are going to design a website with you. Are you ready?"

        let cleaned = cleaner.clean(rawText: rawText, style: .claudeCode)

        XCTAssertEqual(cleaned, "- \(rawText)")
        XCTAssertFalse(cleaned.contains("Context:"))
        XCTAssertFalse(cleaned.contains("Constraints:"))
        XCTAssertFalse(cleaned.contains("Output format:"))
    }

    func testCleanerNormalizesWhitespaceInGoal() {
        let cleaner = PromptCleaner()
        let rawText = "  Hey   claude,\n\ntoday   we build  this  "

        let cleaned = cleaner.clean(rawText: rawText, style: .codex)

        XCTAssertEqual(cleaned, "- Hey claude, today we build this")
    }

    func testCleanerReturnsFallbackForEmptyInput() {
        let cleaner = PromptCleaner()
        let cleaned = cleaner.clean(rawText: "   \n  ", style: .claudeCode)

        XCTAssertEqual(cleaned, "- No transcript captured.")
    }

    func testCleanerOutputIsSameAcrossStyles() {
        let cleaner = PromptCleaner()
        let rawText = "fix auth flow"

        let claude = cleaner.clean(rawText: rawText, style: .claudeCode)
        let codex = cleaner.clean(rawText: rawText, style: .codex)

        XCTAssertEqual(claude, codex)
        XCTAssertEqual(claude, "- fix auth flow")
    }
}
