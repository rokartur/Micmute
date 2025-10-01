import AppKit
import Foundation

public struct AudioApplication: Identifiable, Hashable {
    public struct PeakLevel: Hashable {
        public var left: Float
        public var right: Float

        public static let silent = PeakLevel(left: 0, right: 0)
    }

    public let id: String
    public var name: String
    public var bundleID: String
    public var processID: pid_t
    public var icon: NSImage?
    public var volume: Double
    public var isMuted: Bool
    public var peakLevel: PeakLevel
    public var lastSeen: Date

    public init(
        name: String,
        bundleID: String,
        processID: pid_t,
        icon: NSImage?,
        volume: Double,
        isMuted: Bool,
        peakLevel: PeakLevel = .silent,
        lastSeen: Date = .now
    ) {
        self.id = bundleID
        self.name = name
        self.bundleID = bundleID
        self.processID = processID
        self.icon = icon
        self.volume = volume
        self.isMuted = isMuted
        self.peakLevel = peakLevel
        self.lastSeen = lastSeen
    }

    public static let mockItems: [AudioApplication] = [
        AudioApplication(
            name: "Music",
            bundleID: "com.apple.Music",
            processID: 302,
            icon: NSImage(systemSymbolName: "music.note", accessibilityDescription: nil),
            volume: 0.85,
            isMuted: false,
            peakLevel: PeakLevel(left: 0.18, right: 0.16)
        ),
        AudioApplication(
            name: "Safari",
            bundleID: "com.apple.Safari",
            processID: 112,
            icon: NSImage(systemSymbolName: "safari", accessibilityDescription: nil),
            volume: 0.42,
            isMuted: false,
            peakLevel: PeakLevel(left: 0.07, right: 0.05)
        ),
        AudioApplication(
            name: "Discord",
            bundleID: "com.hnc.Discord",
            processID: 871,
            icon: NSImage(systemSymbolName: "bubble.left.and.exclamationmark.bubble.right", accessibilityDescription: nil),
            volume: 0.13,
            isMuted: true,
            peakLevel: PeakLevel(left: 0.0, right: 0.0)
        )
    ]
}
