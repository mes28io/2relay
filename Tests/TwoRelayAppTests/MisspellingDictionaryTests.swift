import XCTest
@testable import TwoRelayApp

@MainActor
final class MisspellingDictionaryTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "TwoRelayAppTests.MisspellingDictionary"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAddAndApplyCorrection() {
        let dictionary = MisspellingDictionary(
            storage: defaults,
            storageKey: "test.corrections"
        )
        XCTAssertTrue(dictionary.addOrUpdate(source: "cloud", replacement: "Claude"))

        let output = dictionary.apply(to: "please open cloud code")
        XCTAssertEqual(output, "please open Claude code")
    }

    func testApplyIsCaseInsensitiveAndWordBounded() {
        let dictionary = MisspellingDictionary(
            storage: defaults,
            storageKey: "test.corrections"
        )
        _ = dictionary.addOrUpdate(source: "cloud", replacement: "Claude")

        XCTAssertEqual(dictionary.apply(to: "CLOUD"), "Claude")
        XCTAssertEqual(dictionary.apply(to: "cloudy"), "cloudy")
    }

    func testUpdateExistingCorrectionAndRemove() {
        let dictionary = MisspellingDictionary(
            storage: defaults,
            storageKey: "test.corrections"
        )
        _ = dictionary.addOrUpdate(source: "cloud", replacement: "Claude")
        _ = dictionary.addOrUpdate(source: "cloud", replacement: "Claude Code")

        XCTAssertEqual(dictionary.entries.count, 1)
        XCTAssertEqual(dictionary.apply(to: "cloud"), "Claude Code")

        let id = dictionary.entries[0].id
        dictionary.remove(id: id)
        XCTAssertEqual(dictionary.entries.count, 0)
        XCTAssertEqual(dictionary.apply(to: "cloud"), "cloud")
    }
}
