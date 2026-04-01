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
    @Published private(set) var lastCheckFailed = false

    private let repo = "mes28io/2relay"
    private var currentVersion: String

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

        // Check on launch after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await checkForUpdates(interactive: false)
        }
    }

    func checkForUpdates(interactive: Bool = true) async {
        guard !isChecking else { return }
        isChecking = true
        lastCheckFailed = false

        do {
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[2relay] update check failed: HTTP \(statusCode)")
                lastCheckFailed = true
                isChecking = false
                if interactive {
                    showAlert(
                        title: "Update Check Failed",
                        message: "Could not reach the update server. Please check your internet connection and try again."
                    )
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                print("[2relay] update check failed: unexpected response format")
                lastCheckFailed = true
                isChecking = false
                if interactive {
                    showAlert(
                        title: "Update Check Failed",
                        message: "Received an unexpected response from the update server."
                    )
                }
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
                if interactive {
                    showUpdateAvailableAlert(version: latestVersion)
                }
            } else {
                updateAvailable = false
                print("[2relay] up to date: \(currentVersion)")
                if interactive {
                    showAlert(
                        title: "You're Up to Date",
                        message: "2relay \(currentVersion) is the latest version."
                    )
                }
            }
        } catch {
            print("[2relay] update check failed: \(error.localizedDescription)")
            lastCheckFailed = true
            if interactive {
                showAlert(
                    title: "Update Check Failed",
                    message: "Could not check for updates. Please check your internet connection and try again."
                )
            }
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

    private func showUpdateAvailableAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "2relay \(version) is available. You are currently running \(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openDownload()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
