import Foundation
import Combine
import CoreAudio
import CoreFoundation

/// Public-facing bridge that wraps the virtual audio driver C interface.
@MainActor
public final class VirtualDriverBridge: ObservableObject {
    public static let shared = VirtualDriverBridge()

    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var lastKnownError: VirtualDriverBridgeError?

    private var initializationTask: Task<Void, Never>?

    private init() {
        initializationTask = Task { [weak self] in
            guard let self else { return }
            await self.bootstrapDriver()
        }
    }

    deinit {
        Task {
            _ = VirtualAudioDriverShutdown()
        }
    }

    public func bootstrapDriver() async {
        guard !isAvailable else { return }
        let status = VirtualAudioDriverInitialize()
        if status == noErr {
            isAvailable = true
            lastKnownError = nil
        } else {
            let error = VirtualDriverBridgeError.initializationFailed(status)
            lastKnownError = error
        }
    }

    public func refreshActiveApplications() -> [String] {
        guard let array = VirtualAudioDriverCopyActiveApplications() else {
            return []
        }
        let count = CFArrayGetCount(array)
        var identifiers: [String] = []
        identifiers.reserveCapacity(count)

        for index in 0..<count {
            let value = unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: CFString.self)
            identifiers.append(value as String)
        }

        return identifiers
    }

    public func setVolume(bundleID: String, volume: Float) -> Result<Void, VirtualDriverBridgeError> {
        let status = bundleID.withCFString { cfValue in
            VirtualAudioDriverSetApplicationVolume(cfValue, volume)
        }

        if status == noErr {
            return .success(())
        }

        return .failure(.setVolumeFailed(status))
    }

    public func volume(bundleID: String) -> Result<Float, VirtualDriverBridgeError> {
        var resolved: Float = 1.0
        let status = bundleID.withCFString { cfValue in
            VirtualAudioDriverGetApplicationVolume(cfValue, &resolved)
        }

        if status == noErr {
            return .success(resolved)
        }

        if status == kAudioHardwareUnknownPropertyError {
            return .success(1.0)
        }

        return .failure(.getVolumeFailed(status))
    }

    public func mute(bundleID: String, muted: Bool) -> Result<Void, VirtualDriverBridgeError> {
        let status = bundleID.withCFString { cfValue in
            VirtualAudioDriverMuteApplication(cfValue, muted)
        }

        if status == noErr {
            return .success(())
        }

        return .failure(.muteFailed(status))
    }

    public func isMuted(bundleID: String) -> Result<Bool, VirtualDriverBridgeError> {
        let result = bundleID.withCFString { cfValue in
            VirtualAudioDriverIsApplicationMuted(cfValue)
        }

        return .success(result)
    }
}

public enum VirtualDriverBridgeError: Error, Equatable {
    case initializationFailed(OSStatus)
    case setVolumeFailed(OSStatus)
    case getVolumeFailed(OSStatus)
    case muteFailed(OSStatus)
}

extension VirtualDriverBridgeError: LocalizedError {
    public var errorDescription: String? {
        func format(_ status: OSStatus) -> String {
            "OSStatus \(status)"
        }

        switch self {
        case .initializationFailed(let status):
            return "Initialization failed (\(format(status)))."
        case .setVolumeFailed(let status):
            return "Setting application volume failed (\(format(status)))."
        case .getVolumeFailed(let status):
            return "Reading application volume failed (\(format(status)))."
        case .muteFailed(let status):
            return "Muting application failed (\(format(status)))."
        }
    }
}

private extension String {
    func withCFString<Result>(_ body: (CFString) -> Result) -> Result {
        let cfString = self as CFString
        return body(cfString)
    }
}
