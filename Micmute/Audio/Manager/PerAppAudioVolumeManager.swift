import AppKit
import Combine
import Foundation
import os.log

@MainActor
final class PerAppAudioVolumeManager: ObservableObject {
    @Published private(set) var applications: [AudioApplication] = []
    @Published private(set) var driverState: DriverState = .idle

    enum DriverState: Equatable {
        case idle
        case notInstalled
        case installing
        case uninstalling
        case initializing
        case ready
        case installFailure(DriverInstallerError)
        case unavailable(String)
    }

    private let backend: BGMHALBackend
    private var refreshTimer: AnyCancellable?
    private let refreshInterval: TimeInterval
    private let logger = Logger(subsystem: "com.rokartur.Micmute", category: "PerAppAudioVolumeManager")

    init(backend: BGMHALBackend = BGMHALBackend(), refreshInterval: TimeInterval = 1.0) {
        self.backend = backend
        self.refreshInterval = refreshInterval
        scheduleRefreshTimer()
        Task { await checkDriverStatus() }
    }

    deinit {
        refreshTimer?.cancel()
    }

    func installDriver() {
        Task { await performDriverInstallation(force: false) }
    }

    func reinstallDriver() {
        Task { await performDriverInstallation(force: true) }
    }

    func uninstallDriver() {
        Task { await performDriverUninstallation() }
    }

    func refresh() {
        refreshApplications()
    }

    func setVolume(bundleID: String, volume: Double) {
        let clampedVolume = min(max(volume, 0.0), 1.25)
        switch backend.setVolume(bundleID: bundleID, volume: Float(clampedVolume)) {
        case .success:
            updateLocalState(bundleID: bundleID) { $0.volume = clampedVolume }
        case .failure(let error):
            logger.error("Failed to set volume for \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func setMuted(bundleID: String, muted: Bool) {
        switch backend.mute(bundleID: bundleID, muted: muted) {
        case .success:
            updateLocalState(bundleID: bundleID) { $0.isMuted = muted }
        case .failure(let error):
            logger.error("Failed to mute \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshApplications()
            }
    }

    private func refreshApplications() {
        guard driverState == .ready else {
            applications = []
            return
        }

        let snapshots = backend.processEntries()
        let runningApps = NSWorkspace.shared.runningApplications
        let mapping = Dictionary(uniqueKeysWithValues: runningApps.compactMap { app -> (String, NSRunningApplication)? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return (bundleID, app)
        })
        let now = Date()

        let newApplications: [AudioApplication] = snapshots.compactMap { snapshot in
            let bundleID = snapshot.bundleID
            guard !bundleID.isEmpty else { return nil }
            let app = mapping[bundleID]
            return AudioApplication(
                name: app?.localizedName ?? bundleID,
                bundleID: bundleID,
                processID: snapshot.pid,
                icon: app?.icon,
                volume: Double(snapshot.volume),
                isMuted: snapshot.muted,
                peakLevel: .silent,
                lastSeen: now
            )
        }

        mergeApplications(newApplications, referenceDate: now)
    }

    private func mergeApplications(_ newApplications: [AudioApplication], referenceDate: Date) {
        var mergedDictionary = Dictionary(uniqueKeysWithValues: applications.map { ($0.bundleID, $0) })

        for application in newApplications {
            mergedDictionary[application.bundleID] = application
        }

        let staleWindow: TimeInterval = 10
        applications = mergedDictionary.values
            .filter { referenceDate.timeIntervalSince($0.lastSeen) < staleWindow }
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func updateLocalState(bundleID: String, update: (inout AudioApplication) -> Void) {
        guard let index = applications.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        var updated = applications[index]
        update(&updated)
        applications[index] = updated
    }

    private func checkDriverStatus() async {
        backend.refreshDevice()

        guard DriverInstaller.isDriverInstalled else {
            driverState = .notInstalled
            applications = []
            logger.info("HAL plugin not installed")
            return
        }

        driverState = .initializing
        backend.refreshDevice()

        if backend.isAvailable {
            driverState = .ready
            logger.info("HAL backend initialized successfully")
            refreshApplications()
        } else {
            let reason = "Micmute couldn't locate the HAL plugin device. Try reinstalling the driver."
            driverState = .unavailable(reason)
            logger.error("HAL backend unavailable")
        }
    }

    private func performDriverInstallation(force: Bool) async {
        driverState = .installing
        logger.info("Starting HAL plugin installation (force: \(force, privacy: .public))")

        do {
            try await Task.detached(priority: .userInitiated) {
                try DriverInstaller.installDriverIfNeeded(forceInstall: force)
            }.value

            logger.info("HAL plugin installation completed successfully")

            backend.refreshDevice()
            await checkDriverStatus()

            await MainActor.run {
                showSuccessAlert(
                    title: "Driver Installed Successfully",
                    message: "Micmute's HAL audio plugin has been installed and is now active.\n\nYou can control the volume of individual applications playing audio on your Mac."
                )
            }

        } catch let installerError as DriverInstallerError {
            logger.error("Driver installation failed: \(String(describing: installerError), privacy: .public)")

            if case .bundleNotFound = installerError {
                logger.warning("Bundled HAL plugin missing; skipping install in dev mode.")
                driverState = .notInstalled
            } else {
                driverState = .installFailure(installerError)
                await MainActor.run {
                    showErrorAlert(
                        title: "Installation Failed",
                        message: installerError.localizedDescription
                    )
                }
            }
        } catch {
            logger.error("Unexpected installation error: \(error.localizedDescription, privacy: .public)")
            driverState = .installFailure(.unknown(error.localizedDescription))
            await MainActor.run {
                showErrorAlert(
                    title: "Installation Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func performDriverUninstallation() async {
        driverState = .uninstalling
        logger.info("Starting HAL plugin uninstallation")

        do {
            let wasUninstalled = try await Task.detached(priority: .userInitiated) {
                try DriverInstaller.uninstallDriver()
            }.value

            backend.refreshDevice()

            if wasUninstalled {
                logger.info("HAL plugin uninstalled successfully")
                applications = []
                driverState = .notInstalled
                await MainActor.run {
                    showSuccessAlert(
                        title: "Driver Uninstalled Successfully",
                        message: "Micmute's HAL audio plugin has been removed. CoreAudio was restarted, and you can reinstall the driver at any time."
                    )
                }
            } else {
                logger.warning("Uninstall operation completed but driver was not present")
                driverState = .notInstalled
            }

        } catch let installerError as DriverInstallerError {
            logger.error("Driver uninstallation failed: \(String(describing: installerError), privacy: .public)")
            driverState = .installFailure(installerError)
            await MainActor.run {
                showErrorAlert(
                    title: "Uninstallation Failed",
                    message: installerError.localizedDescription
                )
            }
        } catch {
            logger.error("Unexpected uninstallation error: \(error.localizedDescription, privacy: .public)")
            driverState = .installFailure(.unknown(error.localizedDescription))
            await MainActor.run {
                showErrorAlert(
                    title: "Uninstallation Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    private func showSuccessAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.icon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
