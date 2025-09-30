import Foundation
import AlinFoundation

extension UpdaterService {
    @_dynamicReplacement(for: downloadUpdate())
    func micmute_downloadUpdate() {
        if !ensureAppIsInApplicationsFolder() {
            return
        }

        progressBar.0 = "Update in progress".localized()
        progressBar.1 = 0.1

        guard let latestRelease = releases.first else {
            DispatchQueue.main.async {
                self.progressBar.0 = "No releases available".localized()
                self.progressBar.1 = 0.0
            }
            return
        }

        let archIdentifier = isOSArm() ? "arm" : "intel"
        let candidateAssets = latestRelease.assets.filter { asset in
            asset.name.hasSuffix(".zip") && !asset.name.hasSuffix(".dmg")
        }

        let appName = Bundle.main.name
        let asset = candidateAssets.first(where: { $0.name.contains("\(appName)-\(archIdentifier).zip") })
            ?? candidateAssets.first(where: { $0.name == "\(appName).zip" })
            ?? candidateAssets.first

        guard let asset else {
            DispatchQueue.main.async {
                self.progressBar.0 = "No downloadable update found".localized()
                self.progressBar.1 = 0.0
            }
            return
        }

        let downloadURL = URL(string: asset.browserDownloadURL) ?? URL(string: asset.url)

        guard let url = downloadURL else {
            DispatchQueue.main.async {
                self.progressBar.0 = "Invalid download URL".localized()
                self.progressBar.1 = 0.0
            }
            return
        }

        DispatchQueue.main.async {
            self.progressBar.1 = 0.2
        }

        print("[MicmuteUpdater] Using patched download flow for asset: \(asset.name)")

        var request = makeRequest(url: url, token: token)
        if url.absoluteString == asset.url {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }

        let fileManager = FileManager.default
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloadDirectory = appSupportDirectory.appendingPathComponent(Bundle.main.name, isDirectory: true)

        do {
            try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        } catch {
            printOS("Updater: Failed to prepare download directory: \(error)", category: LogCategory.updater)
            DispatchQueue.main.async {
                self.progressBar.0 = "Failed to prepare download".localized()
                self.progressBar.1 = 0.0
            }
            return
        }

        let destinationURL = downloadDirectory.appendingPathComponent(asset.name)
        let existingFileURL = destinationURL

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                printOS("Error fetching asset: \(error?.localizedDescription ?? "Unknown error")", category: LogCategory.updater)
                DispatchQueue.main.async {
                    self.progressBar.0 = "Download failed".localized()
                    self.progressBar.1 = 0.0
                }
                return
            }

            DispatchQueue.main.async {
                self.progressBar.1 = 0.3
            }

            do {
                if fileManager.fileExists(atPath: existingFileURL.path) {
                    try fileManager.removeItem(at: existingFileURL)
                }

                try data.write(to: existingFileURL, options: .atomic)

                DispatchQueue.main.async {
                    self.progressBar.1 = 0.4
                }

                print("[MicmuteUpdater] Saved update archive to \(existingFileURL.path)")

                self.unzipAndReplace(downloadedFileURL: existingFileURL.path)
            } catch {
                printOS("Error saving downloaded file: \(error.localizedDescription)", category: LogCategory.updater)
                DispatchQueue.main.async {
                    self.progressBar.0 = "Failed to save update".localized()
                    self.progressBar.1 = 0.0
                }
            }
        }

        task.resume()
    }
}
