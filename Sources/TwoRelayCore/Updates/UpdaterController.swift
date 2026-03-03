import Foundation
import Sparkle

enum SparkleConfigurationError: LocalizedError {
    case missingValue(key: String)
    case placeholderValue(key: String)
    case invalidFeedURL(String)
    case insecureFeedURLScheme(String)
    case invalidPublicEDKey

    var errorDescription: String? {
        switch self {
        case let .missingValue(key):
            return "Missing required Info.plist key: \(key)"
        case let .placeholderValue(key):
            return "\(key) is still a placeholder value."
        case let .invalidFeedURL(value):
            return "SUFeedURL is not a valid URL: \(value)"
        case let .insecureFeedURLScheme(value):
            return "SUFeedURL must use HTTPS. Current value: \(value)"
        case .invalidPublicEDKey:
            return "SUPublicEDKey must be a valid Sparkle Ed25519 public key (base64)."
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

        guard !isPlaceholder(feedURLString) else {
            throw SparkleConfigurationError.placeholderValue(key: "SUFeedURL")
        }

        guard let feedURL = URL(string: feedURLString) else {
            throw SparkleConfigurationError.invalidFeedURL(feedURLString)
        }
        guard feedURL.scheme?.lowercased() == "https" else {
            throw SparkleConfigurationError.insecureFeedURLScheme(feedURLString)
        }

        guard let publicEDKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SparkleConfigurationError.missingValue(key: "SUPublicEDKey")
        }

        guard !isPlaceholder(publicEDKey) else {
            throw SparkleConfigurationError.placeholderValue(key: "SUPublicEDKey")
        }

        let trimmedPublicEDKey = publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decodedKey = Data(base64Encoded: trimmedPublicEDKey), decodedKey.count == 32 else {
            throw SparkleConfigurationError.invalidPublicEDKey
        }

        return SparkleConfiguration(feedURL: feedURL, publicEDKey: publicEDKey)
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let normalized = value.uppercased()
        return normalized.contains("REPLACE_WITH")
            || normalized.contains("YOUR-")
            || normalized.contains("YOUR_")
            || normalized.contains("TODO")
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
            let message = "Updates are not available in this build yet."
            configurationErrorMessage = message
            print("[2relay] \(message) (\(error.localizedDescription))")
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
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

        updaterController.startUpdater()
    }

    func checkForUpdates() {
        guard let updaterController else {
            if let configurationErrorMessage {
                print("[2relay] \(configurationErrorMessage)")
            }
            return
        }

        guard canCheckForUpdates else {
            print("[2relay] Sparkle updater is not ready to check for updates yet.")
            return
        }

        updaterController.checkForUpdates(nil)
    }
}
