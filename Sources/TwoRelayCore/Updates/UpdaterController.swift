import AppKit
import Foundation

@MainActor
final class UpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersionString: String?
    @Published private(set) var downloadURL: URL?
    @Published private(set) var configurationErrorMessage: String?
    @Published private(set) var isChecking = false

    private let repo = "mes28io/2relay"
    private var currentVersion: String

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

        // Check on launch after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await checkForUpdates()
        }
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true

        do {
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isChecking = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                isChecking = false
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(latestVersion, than: currentVersion) {
                latestVersionString = latestVersion
                updateAvailable = true

                // Find the DMG or zip asset
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           let urlString = asset["browser_download_url"] as? String,
                           name.hasSuffix(".dmg") {
                            downloadURL = URL(string: urlString)
                            break
                        }
                    }
                    // Fallback to zip if no DMG
                    if downloadURL == nil {
                        for asset in assets {
                            if let name = asset["name"] as? String,
                               let urlString = asset["browser_download_url"] as? String,
                               name == "2relay-macos.zip" {
                                downloadURL = URL(string: urlString)
                                break
                            }
                        }
                    }
                }

                // Fallback to release page
                if downloadURL == nil {
                    downloadURL = URL(string: "https://github.com/\(repo)/releases/tag/\(tagName)")
                }

                print("[2relay] update available: \(latestVersion) (current: \(currentVersion))")
            } else {
                updateAvailable = false
                print("[2relay] up to date: \(currentVersion)")
            }
        } catch {
            print("[2relay] update check failed: \(error.localizedDescription)")
        }

        isChecking = false
    }

    func openDownload() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
