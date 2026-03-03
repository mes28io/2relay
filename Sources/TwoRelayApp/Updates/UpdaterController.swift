import Foundation
import Sparkle

enum SparkleConfigurationError: LocalizedError {
    case missingValue(key: String)
    case invalidFeedURL(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(key):
            return "Missing required Info.plist key: \(key)"
        case let .invalidFeedURL(value):
            return "SUFeedURL is not a valid URL: \(value)"
        }
    }
}

struct SparkleConfiguration {
    let feedURL: URL
    let publicEDKey: String

    static func load(from bundle: Bundle = .main) throws -> SparkleConfiguration {
        guard let feedURLString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SparkleConfigurationError.missingValue(key: "SUFeedURL")
        }

        guard let feedURL = URL(string: feedURLString) else {
            throw SparkleConfigurationError.invalidFeedURL(feedURLString)
        }

        guard let publicEDKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SparkleConfigurationError.missingValue(key: "SUPublicEDKey")
        }

        return SparkleConfiguration(feedURL: feedURL, publicEDKey: publicEDKey)
    }
}

@MainActor
final class UpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var configurationErrorMessage: String?

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        do {
            _ = try SparkleConfiguration.load(from: bundle)
        } catch {
            let message = """
[2relay] Sparkle configuration error: \(error.localizedDescription)
[2relay] Sparkle updater is disabled. Add SUFeedURL and SUPublicEDKey to the app target Info.plist.
"""
            configurationErrorMessage = message
            print(message)
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController

        canCheckObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        guard let updaterController else {
            if let configurationErrorMessage {
                print(configurationErrorMessage)
            }
            return
        }
        updaterController.checkForUpdates(nil)
    }
}
