import Foundation

enum UpdaterSupport {
    static func ensureDownloadDirectoryExists() {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            Bundle.main.bundleURL.deletingPathExtension().lastPathComponent

        let downloadDirectory = applicationSupport.appendingPathComponent(bundleName, isDirectory: true)

        if fileManager.fileExists(atPath: downloadDirectory.path) {
            return
        }

        do {
            try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            print("[BetterAudioUpdater] Created Application Support directory at \(downloadDirectory.path)")
        } catch {
            print("[BetterAudioUpdater] Failed to create Application Support directory: \(error.localizedDescription)")
        }
    }
}
