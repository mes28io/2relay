import XCTest
@testable import TwoRelayApp

@MainActor
final class AppStateTests: XCTestCase {
    func testDefaults() {
        let state = AppState()

        XCTAssertEqual(state.defaultTarget, .clipboard)
        XCTAssertEqual(state.modelPath, "~/models/ggml-medium.bin")
        XCTAssertTrue(state.cleanPromptEnabled)
        XCTAssertTrue(state.launchTargetOnStartupEnabled)
        XCTAssertTrue(state.autoCopyPromptToClipboardEnabled)
        XCTAssertTrue(state.autoSendAfterTranscriptionEnabled)
        XCTAssertFalse(state.isListening)
        XCTAssertEqual(state.overlayState, .idle)
        XCTAssertNil(state.overlayErrorMessage)
        XCTAssertEqual(state.lastRawTranscript, "")
        XCTAssertEqual(state.lastPromptToSend, "")
        XCTAssertEqual(state.latestRelays, [])
        XCTAssertEqual(state.targetClips, [:])
    }

    func testStartAndStopListeningUpdatesState() {
        let state = AppState()
        state.licenseValidator.forceActivateForTesting()

        state.startListening()
        XCTAssertTrue(state.isListening)
        XCTAssertEqual(state.overlayState, .listening)

        state.stopListening()
        XCTAssertFalse(state.isListening)
        XCTAssertEqual(state.overlayState, .transcribing)
    }

    func testUpdateOutputsStoresLatestValues() {
        let state = AppState()
        state.updateOutputs(rawTranscript: "raw", finalPrompt: "clean")

        XCTAssertEqual(state.lastRawTranscript, "raw")
        XCTAssertEqual(state.lastPromptToSend, "clean")
        XCTAssertEqual(state.latestRelays, ["clean"])
        XCTAssertEqual(state.overlayState, .readyToSend)
    }

    func testLatestRelaysPersistAfterClearingPendingPrompt() {
        let state = AppState()
        state.updateOutputs(rawTranscript: "raw", finalPrompt: "- first")
        state.clearPendingPrompt()

        XCTAssertEqual(state.lastRawTranscript, "")
        XCTAssertEqual(state.lastPromptToSend, "")
        XCTAssertEqual(state.latestRelays, ["- first"])
    }

    func testPromptPreviewUses120CharacterLimit() {
        let state = AppState()
        let longPrompt = String(repeating: "a", count: 130)
        state.updateOutputs(rawTranscript: "raw", finalPrompt: longPrompt)

        XCTAssertEqual(state.promptPreview.count, 123)
        XCTAssertTrue(state.promptPreview.hasSuffix("..."))
    }

    func testSaveTargetClipStoresPerTarget() {
        let state = AppState()
        state.saveTargetClip(" hello ", for: .clipboard)
        state.saveTargetClip("world", for: .clipboard)

        XCTAssertEqual(state.targetClips[.clipboard], "world")
    }
}
