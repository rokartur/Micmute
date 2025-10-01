import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationVolumeRowViewModel: ObservableObject, Identifiable {
    nonisolated let id: String
    let bundleID: String
    @Published private(set) var application: AudioApplication

    var displayName: String { application.name }
    var volume: Double { application.volume }
    var isMuted: Bool { application.isMuted }
    var icon: NSImage? { application.icon }
    var peakLevel: AudioApplication.PeakLevel { application.peakLevel }

    private let manager: PerAppAudioVolumeManager

    init(application: AudioApplication, manager: PerAppAudioVolumeManager) {
        self.application = application
        self.manager = manager
        self.id = application.bundleID
        self.bundleID = application.bundleID
    }

    func update(with application: AudioApplication) {
        guard application != self.application else { return }
        self.application = application
    }

    func setVolume(_ volume: Double) {
        manager.setVolume(bundleID: bundleID, volume: volume)
    }

    func setMuted(_ muted: Bool) {
        manager.setMuted(bundleID: bundleID, muted: muted)
    }
}
