import Foundation
import MachO
import os.log
import AppKit

@MainActor
final class SettingsUpdaterModel: ObservableObject {
    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var releases: [SettingsRelease] = []
    @Published private(set) var frequency: UpdateFrequencyOption
    @Published private(set) var isCheckingForUpdates: Bool = false
    @Published private(set) var progressMessage: String = ""
    @Published private(set) var progressValue: Double = 0
    @Published private(set) var announcementAvailable: Bool = false
    @Published private(set) var nextScheduledCheck: Date
    @Published private(set) var restartRequired: Bool = false

    var currentVersion: String { AppInfo.appVersion }
    var latestRelease: SettingsRelease? { releases.first }
    var announcementText: String { announcement ?? "" }

    private let owner: String
    private let repository: String
    private let session: URLSession
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.rokartur.Micmute", category: "Updater")

    private var lastFetchDate: Date?
    private var announcement: String? = nil
    private var lastSeenReleaseTag: String?
    private var updateFrequency: UpdateFrequency {
        didSet { persistFrequency() }
    }

    private enum DefaultsKey {
        static let frequency = "com.rokartur.micmute.updater.frequency"
        static let nextCheck = "com.rokartur.micmute.updater.nextCheck"
        static let lastSeenRelease = "com.rokartur.micmute.updater.lastSeenRelease"
        static let lastFetch = "com.rokartur.micmute.updater.lastFetch"
    }

    private enum FetchReason {
        case manual
        case background
    }

    init(owner: String, repository: String, session: URLSession = .shared, userDefaults: UserDefaults = .standard) {
        self.owner = owner
        self.repository = repository
        self.session = session
        self.userDefaults = userDefaults

        let storedFrequency = userDefaults.string(forKey: DefaultsKey.frequency)
        self.updateFrequency = UpdateFrequency(rawValue: storedFrequency ?? "daily") ?? .daily
        self.frequency = UpdateFrequencyOption(frequency: updateFrequency)

        if let storedDate = userDefaults.object(forKey: DefaultsKey.nextCheck) as? Date {
            self.nextScheduledCheck = storedDate
        } else {
            self.nextScheduledCheck = Date()
        }

        self.lastSeenReleaseTag = userDefaults.string(forKey: DefaultsKey.lastSeenRelease)
        self.lastFetchDate = userDefaults.object(forKey: DefaultsKey.lastFetch) as? Date
    }

    // MARK: - Public API

    func refreshIfNeeded() {
        if releases.isEmpty {
            performFetch(reason: .background)
            return
        }

        guard shouldPerformBackgroundFetch else { return }
        performFetch(reason: .background)
    }

    func checkForUpdates() {
        performFetch(reason: .manual)
    }

    func downloadUpdate() {
        guard let release = latestRelease else {
            progressMessage = "No releases available"
            progressValue = 0
            return
        }

        guard let asset = preferredAsset(from: release) else {
            progressMessage = "No suitable download found"
            progressValue = 0
            return
        }

        progressMessage = "Preparing download…"
        progressValue = 0.1
        restartRequired = false

        Task { [weak self] in
            guard let self else { return }

            do {
                let downloadURL = asset.downloadURL ?? asset.apiURL
                guard let url = downloadURL else {
                    throw UpdaterError.invalidDownloadURL
                }

                let destination = try prepareDownloadDestination(for: asset.name)
                let data = try await downloadAsset(from: url)
                progressValue = 0.35

                try data.write(to: destination, options: .atomic)
                progressMessage = "Extracting update…"
                progressValue = 0.55

                let extraction = try extractApplicationBundle(from: destination)
                defer { try? FileManager.default.removeItem(at: extraction.containerDirectory) }
                progressValue = 0.7

                progressMessage = "Installing update…"
                progressValue = 0.75

                try replaceInstalledApplication(with: extraction.bundleURL)
                try? FileManager.default.removeItem(at: destination)

                updateAvailable = false
                progressMessage = "Update installed. Restart Micmute to finish."
                progressValue = 1.0
                restartRequired = true
            } catch UpdaterError.installationCancelled {
                logger.info("Update installation cancelled by user")
                progressMessage = "Installation cancelled"
                progressValue = 0
                restartRequired = false
            } catch let updaterError as UpdaterError {
                logger.error("Update flow failed: \(updaterError.logDescription, privacy: .public)")
                progressMessage = updaterError.userFacingMessage
                progressValue = 0
                restartRequired = false
            } catch {
                logger.error("Update flow failed: \(error.localizedDescription, privacy: .public)")
                progressMessage = "Update failed"
                progressValue = 0
                restartRequired = false
            }
        }
    }

    func restartApplication() {
        #if os(macOS)
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.promptsUserIfNeeded = false

        restartRequired = false
        progressMessage = "Restarting Micmute…"

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.logger.error("Failed to relaunch Micmute: \(error.localizedDescription, privacy: .public)")
                    self.progressMessage = "Couldn't relaunch Micmute. Please start it manually."
                    self.restartRequired = true
                    return
                }

                NSApp.terminate(nil)
            }
        }
        #else
        logger.error("Restart requested on unsupported platform")
        #endif
    }

    func setFrequency(_ option: UpdateFrequencyOption) {
        guard option != frequency else { return }
        updateFrequency = option.asUpdaterFrequency()
        frequency = option
        scheduleNextCheck(from: Date())
    }

    func markAnnouncementViewed() {
        guard let tag = latestRelease?.tagName else { return }
        lastSeenReleaseTag = tag
        announcementAvailable = false
        userDefaults.set(tag, forKey: DefaultsKey.lastSeenRelease)
    }

    // MARK: - Scheduling

    func scheduleNextCheck(from date: Date) {
        let next: Date
        switch updateFrequency {
        case .none:
            next = .distantFuture
        case .daily:
            next = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        case .weekly:
            next = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(604_800)
        case .monthly:
            next = Calendar.current.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(2_592_000)
        }

        nextScheduledCheck = next
        userDefaults.set(next, forKey: DefaultsKey.nextCheck)
    }

    func bootstrapOnLaunch() {
        guard updateFrequency != .none else { return }
        if Date() >= nextScheduledCheck {
            performFetch(reason: .background)
        }
    }

    // MARK: - Private helpers

    private var shouldPerformBackgroundFetch: Bool {
        guard updateFrequency != .none else { return false }
        guard Date() >= nextScheduledCheck else { return false }
        if let lastFetchDate, Date().timeIntervalSince(lastFetchDate) < 1_800 {
            return false
        }
        return true
    }

    private func performFetch(reason: FetchReason) {
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        if reason == .manual {
            progressMessage = "Contacting GitHub…"
            progressValue = 0.15
        }

        Task { [weak self] in
            guard let self else { return }

            defer { self.isCheckingForUpdates = false }

            do {
                let releases = try await fetchGitHubReleases()
                handleFetchedReleases(releases)
                lastFetchDate = Date()
                userDefaults.set(lastFetchDate, forKey: DefaultsKey.lastFetch)
                if updateFrequency != .none {
                    scheduleNextCheck(from: Date())
                }
                if reason == .manual {
                    progressMessage = "Latest release info fetched"
                    progressValue = 0.8
                }
            } catch {
                logger.error("Failed to fetch releases: \(error.localizedDescription, privacy: .public)")
                progressMessage = "Unable to reach GitHub"
                progressValue = 0
            }

            if reason == .manual {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.progressMessage = ""
                    self.progressValue = 0
                }
            }
        }
    }

    private func fetchGitHubReleases() async throws -> [GitHubReleaseDTO] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Micmute-Updater", forHTTPHeaderField: "User-Agent")

        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw UpdaterError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubReleaseDTO].self, from: data)
    }

    private func handleFetchedReleases(_ releases: [GitHubReleaseDTO]) {
        // GitHub zwraca w kolejności od najnowszych – filtrujemy i przycinamy do 3
        let visible = releases.filter { !$0.draft && !$0.prerelease }
        let top3 = Array(visible.prefix(3))
        self.releases = top3.map { SettingsRelease(dto: $0) }
        let latest = top3.first
        updateAvailable = determineUpdateAvailability(from: latest)
        updateAnnouncementState(using: latest)

        if progressValue > 0 {
            progressValue = min(progressValue + 0.2, 1.0)
        }
    }

    private func determineUpdateAvailability(from latest: GitHubReleaseDTO?) -> Bool {
        guard let latest else { return false }
        return isVersion(latest.tagName, newerThan: currentVersion)
    }

    private func updateAnnouncementState(using latest: GitHubReleaseDTO?) {
        guard let latest else {
            announcement = nil
            announcementAvailable = false
            return
        }

        announcement = latest.body
        if latest.tagName != lastSeenReleaseTag && !(latest.body ?? "").isEmpty {
            announcementAvailable = true
        } else {
            announcementAvailable = false
        }
    }

    private func preferredAsset(from release: SettingsRelease) -> SettingsRelease.Asset? {
        let candidates = release.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard !candidates.isEmpty else { return nil }

        let bundleToken = Bundle.main.name.normalizedAssetToken()
        let architecture = currentBinaryArchitecture()
        let normalizedCandidates = candidates.map { asset -> (SettingsRelease.Asset, String) in
            (asset, asset.name.normalizedAssetToken())
        }

        if let preciseMatch = normalizedCandidates.first(where: { candidate in
            candidate.1.contains(bundleToken) && candidate.1.containsAny(of: architecture.assetPreferenceTokens)
        }) {
            return preciseMatch.0
        }

        if let archMatch = normalizedCandidates.first(where: { $0.1.containsAny(of: architecture.assetPreferenceTokens) }) {
            return archMatch.0
        }

        if let bundleMatch = normalizedCandidates.first(where: { $0.1.contains(bundleToken) }) {
            return bundleMatch.0
        }

        return candidates.first
    }

    private func currentBinaryArchitecture() -> BinaryArchitecture {
        if let architectures = Bundle.main.executableArchitectures?.compactMap({ BinaryArchitecture(bundleValue: $0.intValue) }),
           let firstMatch = architectures.first {
            return firstMatch
        }

        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    private enum BinaryArchitecture {
        case arm64
        case x86_64

        init?(bundleValue: Int) {
            switch bundleValue {
            case Int(CPU_TYPE_ARM64):
                self = .arm64
            case Int(CPU_TYPE_X86_64):
                self = .x86_64
            default:
                return nil
            }
        }

        var assetPreferenceTokens: [String] {
            switch self {
            case .arm64:
                return ["arm64", "apple-silicon", "applesilicon", "aarch64", "arm"]
            case .x86_64:
                return ["x86-64", "x86_64", "x86", "intel"]
            }
        }
    }

    private func prepareDownloadDestination(for filename: String) throws -> URL {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw UpdaterError.cannotAccessApplicationSupport
        }

        let directory = appSupport.appendingPathComponent(Bundle.main.name, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let destination = directory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        return destination
    }

    private func downloadAsset(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Micmute-Updater", forHTTPHeaderField: "User-Agent")

        if url.host == "api.github.com",
           let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        }

        progressMessage = "Downloading archive…"
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw UpdaterError.invalidResponse
        }
        return data
    }

    private struct ExtractedApplication {
        let bundleURL: URL
        let containerDirectory: URL
    }

    private func extractApplicationBundle(from archiveURL: URL) throws -> ExtractedApplication {
        let fileManager = FileManager.default
        let containerDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: containerDirectory, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, containerDirectory.path]

            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw UpdaterError.failedToExtractArchive(error.localizedDescription)
            }

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw UpdaterError.failedToExtractArchive(message ?? "ditto returned non-zero exit status")
            }

            guard let bundleURL = findApplicationBundle(in: containerDirectory) else {
                throw UpdaterError.applicationBundleNotFound
            }

            return ExtractedApplication(bundleURL: bundleURL, containerDirectory: containerDirectory)
        } catch {
            try? fileManager.removeItem(at: containerDirectory)
            throw error
        }
    }

    private func findApplicationBundle(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "app" {
                    return fileURL
                }
            }
        }
        return nil
    }

    private func replaceInstalledApplication(with newBundleURL: URL) throws {
        let fileManager = FileManager.default
        guard let applicationsDirectory = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first else {
            throw UpdaterError.installationFailed("Unable to locate /Applications directory")
        }

        let destination = applicationsDirectory.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent, isDirectory: true)

        do {
            try copyApplicationBundle(from: newBundleURL, to: destination)
        } catch {
            let nsError = error as NSError
            let needsPrivileges = nsError.domain == NSCocoaErrorDomain &&
                (nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileWriteVolumeReadOnlyError)

            if needsPrivileges {
                #if os(macOS)
                try performPrivilegedApplicationReplace(source: newBundleURL, destination: destination)
                #else
                throw error
                #endif
            } else {
                throw error
            }
        }
    }

    private func copyApplicationBundle(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let parentDirectory = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectory.path) {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
    }

    #if os(macOS)
    private func performPrivilegedApplicationReplace(source: URL, destination: URL) throws {
        let commands = [
            "/bin/mkdir -p \(shellEscapedPath(destination.deletingLastPathComponent().path))",
            "/bin/rm -rf \(shellEscapedPath(destination.path))",
            "/bin/cp -R \(shellEscapedPath(source.path)) \(shellEscapedPath(destination.path))"
        ]

        try runPrivilegedScript(commands: commands)
    }

    private func runPrivilegedScript(commands: [String]) throws {
        guard !commands.isEmpty else { return }

        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sh")

        let script = """
        #!/bin/sh
        set -e
        \(commands.joined(separator: "\n"))
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        defer { try? fileManager.removeItem(at: scriptURL) }

        let command = "/bin/sh \(shellEscapedPath(scriptURL.path))"
        let appleScript = """
        do shell script \"\(command)\" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw UpdaterError.installationFailed("Unable to request administrator privileges")
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if errorOutput.contains("User canceled") || errorOutput.contains("-128") {
                throw UpdaterError.installationCancelled
            }

            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdaterError.installationFailed(message.isEmpty ? "Administrator command failed" : message)
        }
    }
    #endif

    private func shellEscapedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func persistFrequency() {
        userDefaults.set(updateFrequency.rawValue, forKey: DefaultsKey.frequency)
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = versionComponents(from: candidate)
        let rhs = versionComponents(from: current)
        let maxCount = max(lhs.count, rhs.count)

        for index in 0..<maxCount {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left == right { continue }
            return left > right
        }
        return false
    }

    private func versionComponents(from string: String) -> [Int] {
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let filteredScalars = string.unicodeScalars.filter { allowed.contains($0) }
        let sanitized = String(String.UnicodeScalarView(filteredScalars))
        return sanitized.split(separator: ".").compactMap { Int($0) }
    }

}

// MARK: - Supporting models

struct GitHubReleaseDTO: Decodable {
    struct Asset: Decodable {
        let id: Int
        let name: String
        let browserDownloadURL: URL?
        let url: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case browserDownloadURL = "browser_download_url"
            case url
        }
    }

    let id: Int
    let name: String
    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tagName = "tag_name"
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}

struct SettingsRelease: Identifiable {
    struct Asset: Identifiable {
        let id: Int
        let name: String
        let downloadURL: URL?
        let apiURL: URL?

        init(dto: GitHubReleaseDTO.Asset) {
            self.id = dto.id
            self.name = dto.name
            self.downloadURL = dto.browserDownloadURL
            self.apiURL = dto.url
        }
    }

    let id: Int
    let name: String
    let tagName: String
    let body: String
    let publishedAt: Date?
    let assets: [Asset]
    let isPrerelease: Bool

    init(dto: GitHubReleaseDTO) {
        self.id = dto.id
        self.name = dto.name
        self.tagName = dto.tagName
        self.body = dto.body ?? ""
        self.publishedAt = dto.publishedAt
        self.assets = dto.assets.map { Asset(dto: $0) }
        self.isPrerelease = dto.prerelease
    }

    var displayTitle: String {
        name.isEmpty ? tagName : name
    }

    var githubURL: URL? {
        guard let owner = GitHubReleaseConfiguration.owner,
              let repo = GitHubReleaseConfiguration.repository else { return nil }
        let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName
        return URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(encodedTag)")
    }
}

private extension String {
    func normalizedAssetToken() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let underscored = lowered.replacingOccurrences(of: "_", with: "-")
        let spaced = underscored.replacingOccurrences(of: " ", with: "-")
        return spaced.replacingOccurrences(of: "--", with: "-")
    }

    func containsAny(of tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        return tokens.contains(where: { !$0.isEmpty && self.contains($0) })
    }
}
 
enum UpdateFrequency: String {
    case none
    case daily
    case weekly
    case monthly
}

enum UpdateFrequencyOption: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case monthly

    init(frequency: UpdateFrequency) {
        switch frequency {
        case .none: self = .never
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var subtitle: String {
        switch self {
        case .never: return "Only manual checks"
        case .daily: return "Recommended"
        case .weekly: return "Once a week"
        case .monthly: return "Once a month"
        }
    }

    func asUpdaterFrequency() -> UpdateFrequency {
        switch self {
        case .never: return .none
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }
}

private enum UpdaterError: Error {
    case invalidResponse
    case invalidDownloadURL
    case cannotAccessApplicationSupport
    case failedToExtractArchive(String)
    case applicationBundleNotFound
    case installationFailed(String)
    case installationCancelled
}

private extension UpdaterError {
    var userFacingMessage: String {
        switch self {
        case .invalidResponse:
            return "Micmute couldn't understand GitHub's response."
        case .invalidDownloadURL:
            return "The release is missing a valid download link."
        case .cannotAccessApplicationSupport:
            return "Micmute can't access Application Support."
        case .failedToExtractArchive(let reason):
            return "Couldn't unpack the update (\(reason))."
        case .applicationBundleNotFound:
            return "Micmute couldn't find the app bundle inside the archive."
        case .installationFailed(let message):
            return message.isEmpty ? "Update installation failed." : message
        case .installationCancelled:
            return "Installation cancelled"
        }
    }

    var logDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .invalidDownloadURL:
            return "Missing or invalid download URL"
        case .cannotAccessApplicationSupport:
            return "Cannot access Application Support directory"
        case .failedToExtractArchive(let reason):
            return "Extraction failed: \(reason)"
        case .applicationBundleNotFound:
            return "Application bundle not found in archive"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .installationCancelled:
            return "Installation cancelled by user"
        }
    }
}

private extension Bundle {
    var name: String {
        if let displayName = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let bundleName = object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return bundleURL.deletingPathExtension().lastPathComponent
    }
}
