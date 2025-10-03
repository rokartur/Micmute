import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationVolumeListViewModel: ObservableObject {
    @Published private(set) var rows: [ApplicationVolumeRowViewModel] = []
    @Published private(set) var filterText: String = ""

    var hasActiveApplications: Bool { !rows.isEmpty }

    private var cache: [String: ApplicationVolumeRowViewModel] = [:]
    private var installationCache: [String: Bool] = [:]
    private var cancellable: AnyCancellable?
    private let manager: PerAppAudioVolumeManager
    private let peakThreshold: Float = 0.0025

    init(manager: PerAppAudioVolumeManager) {
        self.manager = manager
        bindToManager()
    }

    func updateFilter(to text: String) {
        filterText = text
        refreshRows(using: manager.applications)
    }

    func refresh() {
        manager.refresh()
    }

    private func bindToManager() {
        cancellable = manager.$applications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] applications in
                self?.refreshRows(using: applications)
            }
    }

    private func refreshRows(using applications: [AudioApplication]) {
        let installedApps = applications.filter { isApplicationInstalled(bundleID: $0.bundleID) }
        let activeApps = installedApps.filter { hasActiveAudio($0) }

        let filteredApps: [AudioApplication]
        if filterText.isEmpty {
            filteredApps = activeApps
        } else {
            filteredApps = activeApps.filter { app in
                app.name.localizedCaseInsensitiveContains(filterText) ||
                app.bundleID.localizedCaseInsensitiveContains(filterText)
            }
        }

        var updated: [ApplicationVolumeRowViewModel] = []
        updated.reserveCapacity(filteredApps.count)

        for application in filteredApps {
            if let existing = cache[application.bundleID] {
                existing.update(with: application)
                updated.append(existing)
            } else {
                let viewModel = ApplicationVolumeRowViewModel(application: application, manager: manager)
                cache[application.bundleID] = viewModel
                updated.append(viewModel)
            }
        }

        rows = updated.sorted(by: { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
    }

    private func isApplicationInstalled(bundleID: String) -> Bool {
        if let cached = installationCache[bundleID] {
            return cached
        }

        let isInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        installationCache[bundleID] = isInstalled
        return isInstalled
    }

    private func hasActiveAudio(_ application: AudioApplication) -> Bool {
        guard !application.isMuted else { return false }
        if Date().timeIntervalSince(application.lastSeen) < 5 { return true }
        let maxPeak = max(application.peakLevel.left, application.peakLevel.right)
        return maxPeak > peakThreshold
    }
}
