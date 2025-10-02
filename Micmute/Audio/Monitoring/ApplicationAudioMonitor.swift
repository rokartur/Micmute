import AppKit
import Combine
import Foundation
import os.log

public final class ApplicationAudioMonitor {
    public var applicationPublisher: AnyPublisher<[AudioApplication], Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<[AudioApplication], Never>()
    private let queue = DispatchQueue(label: "com.rokartur.Micmute.audio-monitor", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let logger = Logger(subsystem: "com.rokartur.Micmute", category: "ApplicationAudioMonitor")
    private let driver: VirtualDriverBridge

    private let refreshInterval: TimeInterval

    public init(driver: VirtualDriverBridge, refreshInterval: TimeInterval = 1.0) {
        self.driver = driver
        self.refreshInterval = refreshInterval
    }

    deinit {
        stop()
    }

    public func start() {
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        source.setEventHandler { [weak self] in
            self?.pollRunningApplications()
        }
        timer = source
        source.resume()
        logger.debug("Started monitoring running applications")
        pollRunningApplications()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func refresh() {
        queue.async { [weak self] in
            self?.pollRunningApplications()
        }
    }

    private func pollRunningApplications() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.publishActiveApplications()
        }
    }

    @MainActor
    private func publishActiveApplications() {
        #if DEBUG
        // In debug builds, provide mock data to allow UI prototyping without a driver.
        subject.send(AudioApplication.mockItems)
        #else
        // Get active audio bundle IDs from the driver
        let activeBundleIDs = driver.refreshActiveApplications()
        
        guard !activeBundleIDs.isEmpty else {
            subject.send([])
            return
        }
        
        logger.debug("Driver reported \(activeBundleIDs.count) active audio bundle IDs: \(activeBundleIDs.joined(separator: ", "), privacy: .public)")
        
        // Match bundle IDs with running applications to get names and icons
        let runningApps = NSWorkspace.shared.runningApplications
        let bundleIDToApp = Dictionary(uniqueKeysWithValues: runningApps.compactMap { app -> (String, NSRunningApplication)? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return (bundleID, app)
        })
        
        let applications: [AudioApplication] = activeBundleIDs.compactMap { bundleID in
            let app = bundleIDToApp[bundleID]
            let name = app?.localizedName ?? bundleID
            let icon = app?.icon
            
            // Get volume and mute state from driver
            let volume = (try? driver.volume(bundleID: bundleID).get()).map(Double.init) ?? 1.0
            let isMuted = (try? driver.isMuted(bundleID: bundleID).get()) ?? false
            
            return AudioApplication(
                name: name,
                bundleID: bundleID,
                processID: app?.processIdentifier ?? 0,
                icon: icon,
                volume: volume,
                isMuted: isMuted
            )
        }
        
        subject.send(applications)
        #endif
    }
}
