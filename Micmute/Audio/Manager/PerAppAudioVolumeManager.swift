import AppKit
import Combine
import Foundation
import os.log

@MainActor
public final class PerAppAudioVolumeManager: ObservableObject {
    @Published public private(set) var applications: [AudioApplication] = []
    @Published public private(set) var driverState: DriverState = .idle

    public enum DriverState: Equatable {
        case idle
        case notInstalled
        case installing
        case uninstalling
        case initializing
        case ready
        case installFailure(DriverInstallerError)
        case failure(VirtualDriverBridgeError)
    }

    private let driver: VirtualDriverBridge
    private let monitor: ApplicationAudioMonitor
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.rokartur.Micmute", category: "PerAppAudioVolumeManager")

    public init(driver: VirtualDriverBridge? = nil, monitor: ApplicationAudioMonitor? = nil) {
        self.driver = driver ?? VirtualDriverBridge.shared
        self.monitor = monitor ?? ApplicationAudioMonitor(driver: self.driver)

        self.monitor.applicationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                Task { @MainActor in
                    self?.mergeApplications(apps)
                }
            }
            .store(in: &cancellables)

        // Check driver installation status but don't auto-install
        Task { await checkDriverStatus() }
        self.monitor.start()
    }

    public func installDriver() {
        Task { await performDriverInstallation(force: false) }
    }

    public func reinstallDriver() {
        Task { await performDriverInstallation(force: true) }
    }

    public func uninstallDriver() {
        Task { await performDriverUninstallation() }
    }

    public func refresh() {
        monitor.refresh()
    }

    public func setVolume(bundleID: String, volume: Double) {
        let clampedVolume = min(max(volume, 0.0), 1.25)
        switch driver.setVolume(bundleID: bundleID, volume: Float(clampedVolume)) {
        case .success:
            updateLocalState(bundleID: bundleID) { $0.volume = clampedVolume }
        case .failure(let error):
            logger.error("Failed to set volume for \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    public func setMuted(bundleID: String, muted: Bool) {
        switch driver.mute(bundleID: bundleID, muted: muted) {
        case .success:
            updateLocalState(bundleID: bundleID) { $0.isMuted = muted }
        case .failure(let error):
            logger.error("Failed to mute \(bundleID, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func updateLocalState(bundleID: String, update: (inout AudioApplication) -> Void) {
        guard let index = applications.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        var updated = applications[index]
        update(&updated)
        applications[index] = updated
    }

    private func mergeApplications(_ newApplications: [AudioApplication]) {
        var mergedDictionary = Dictionary(uniqueKeysWithValues: applications.map { ($0.bundleID, $0) })
        let now = Date()

        for application in newApplications {
            if var existing = mergedDictionary[application.bundleID] {
                existing.volume = application.volume
                existing.isMuted = application.isMuted
                existing.peakLevel = application.peakLevel
                existing.lastSeen = now
                mergedDictionary[application.bundleID] = existing
            } else {
                mergedDictionary[application.bundleID] = application
            }
        }

        applications = mergedDictionary.values
            .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private func checkDriverStatus() async {
        if !DriverInstaller.isDriverInstalled {
            driverState = .notInstalled
            logger.info("Driver not installed - waiting for manual installation")
            return
        }

        // Driver is installed, try to initialize it
        driverState = .initializing
        await driver.bootstrapDriver()
        if driver.isAvailable {
            driverState = .ready
            logger.info("Driver initialized successfully")
        } else if let error = driver.lastKnownError {
            driverState = .failure(error)
            logger.error("Driver failed to initialize: \(String(describing: error), privacy: .public)")
        } else {
            driverState = .idle
        }
    }

    private func performDriverInstallation(force: Bool) async {
        driverState = .installing
        logger.info("Starting driver installation (force: \(force, privacy: .public))")
        
        do {
            try await Task.detached(priority: .userInitiated) {
                try DriverInstaller.installDriverIfNeeded(forceInstall: force)
            }.value
            
            logger.info("Driver installation completed successfully")
            
            // After successful installation, initialize the driver
            await checkDriverStatus()
            
            // Show success notification
            await showSuccessAlert(
                title: "Driver Installed Successfully",
                message: "The virtual audio driver has been installed and is now active.\n\nYou can now control the volume of individual applications playing audio on your Mac."
            )
            
        } catch let installerError as DriverInstallerError {
            logger.error("Driver installation failed: \(String(describing: installerError), privacy: .public)")
            
            // If the bundled driver resource is missing, allow development builds to continue
            if case .bundleNotFound = installerError {
                logger.warning("Bundled driver resource missing; skipping install in dev mode.")
                driverState = .notInstalled
            } else {
                driverState = .installFailure(installerError)
                
                // Show error alert
                await showErrorAlert(
                    title: "Installation Failed",
                    message: installerError.localizedDescription
                )
            }
        } catch {
            logger.error("Unexpected installation error: \(error.localizedDescription, privacy: .public)")
            driverState = .installFailure(.unknown(error.localizedDescription))
            
            // Show error alert
            await showErrorAlert(
                title: "Installation Failed",
                message: error.localizedDescription
            )
        }
    }

    private func performDriverUninstallation() async {
        driverState = .uninstalling
        logger.info("Starting driver uninstallation")
        
        do {
            let wasUninstalled = try await Task.detached(priority: .userInitiated) {
                try DriverInstaller.uninstallDriver()
            }.value
            
            if wasUninstalled {
                logger.info("Driver uninstalled successfully")
                driverState = .notInstalled
                
                // Clear any cached state
                await driver.bootstrapDriver()
                
                // Show success notification
                await showSuccessAlert(
                    title: "Driver Uninstalled Successfully",
                    message: "The virtual audio driver has been removed from your system.\n\nCoreAudio has been restarted. You can reinstall the driver at any time from settings."
                )
            } else {
                logger.warning("Uninstall operation completed but driver was not present")
                driverState = .notInstalled
            }
            
        } catch let installerError as DriverInstallerError {
            logger.error("Driver uninstallation failed: \(String(describing: installerError), privacy: .public)")
            driverState = .installFailure(installerError)
            
            // Show error alert
            await showErrorAlert(
                title: "Uninstallation Failed",
                message: installerError.localizedDescription
            )
        } catch {
            logger.error("Unexpected uninstallation error: \(error.localizedDescription, privacy: .public)")
            driverState = .installFailure(.unknown(error.localizedDescription))
            
            // Show error alert
            await showErrorAlert(
                title: "Uninstallation Failed",
                message: error.localizedDescription
            )
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
