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

    private let refreshInterval: TimeInterval

    public init(refreshInterval: TimeInterval = 1.0) {
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

    private func pollRunningApplications() {
        #if DEBUG
        // In debug builds, provide mock data to allow UI prototyping without a driver.
        subject.send(AudioApplication.mockItems)
        #else
        let runningApps = NSWorkspace.shared.runningApplications
        let applications = runningApps
            .compactMap { app -> AudioApplication? in
                guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else {
                    return nil
                }

                return AudioApplication(
                    name: app.localizedName ?? bundleID,
                    bundleID: bundleID,
                    processID: app.processIdentifier,
                    icon: app.icon,
                    volume: 1.0,
                    isMuted: false
                )
            }
        subject.send(applications)
        #endif
    }
}
