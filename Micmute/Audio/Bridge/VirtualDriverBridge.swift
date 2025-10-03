import Foundation
import Combine
import CoreAudio
import os.log

private let kBGMPropertyProcessList: AudioObjectPropertySelector = 0x706C7374 // 'plst'
private let kBGMPropertyProcessVolume: AudioObjectPropertySelector = 0x70766F6C // 'pvol'
private let kBGMPropertyProcessMute: AudioObjectPropertySelector = 0x706D7574 // 'pmut'
private let kBGMDeviceUID = "BGMDevice"

private struct ProcessSnapshot {
    let pid: pid_t
    var volume: Float
    var muted: Bool
}

/// Swift bridge that talks directly to the HAL plugin via CoreAudio properties.
@MainActor
public final class VirtualDriverBridge: ObservableObject {
    public static let shared = VirtualDriverBridge()

    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var lastKnownError: VirtualDriverBridgeError?

    private let logger = Logger(subsystem: "com.rokartur.Micmute", category: "VirtualDriverBridge")
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var processCache: [String: ProcessSnapshot] = [:]

    private init() {
        Task { [weak self] in
            await self?.bootstrapDriver()
        }
    }

    public func bootstrapDriver() async {
        locateDevice()
        if deviceID != kAudioObjectUnknown {
            isAvailable = true
            lastKnownError = nil
            logger.info("HAL device located (id: \(self.deviceID))")
        } else {
            isAvailable = false
            let errorStatus: OSStatus = kAudioHardwareBadDeviceError
            lastKnownError = .initializationFailed(errorStatus)
            logger.error("HAL device not found")
        }
    }

    public func refreshActiveApplications() -> [String] {
        guard deviceID != kAudioObjectUnknown else {
            processCache.removeAll()
            return []
        }

        var addr = AudioObjectPropertyAddress(
            mSelector: kBGMPropertyProcessList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize)
        guard status == noErr, dataSize >= UInt32(MemoryLayout<BGMProcessEntry>.stride) else {
            if status != noErr {
                logger.error("Failed to query process list size status=\(status)")
            }
            processCache.removeAll()
            return []
        }

        var buffer = [UInt8](repeating: 0, count: Int(dataSize))
        var mutableSize = dataSize
        status = buffer.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &mutableSize, base)
        }

        guard status == noErr else {
            logger.error("Failed to read process list status=\(status)")
            processCache.removeAll()
            return []
        }

        let entryCount = Int(mutableSize) / MemoryLayout<BGMProcessEntry>.stride
        var orderedBundleIDs: [String] = []
        orderedBundleIDs.reserveCapacity(entryCount)
        var newCache: [String: ProcessSnapshot] = [:]

        buffer.withUnsafeBytes { raw in
            let entries = raw.bindMemory(to: BGMProcessEntry.self)
            for index in 0..<entryCount {
                let entry = entries[index]
                let bundleID = bundleIdentifier(from: entry)
                let key = bundleID.isEmpty ? "pid_\(entry.pid)" : bundleID
                orderedBundleIDs.append(key)
                newCache[key] = ProcessSnapshot(pid: entry.pid, volume: entry.volume, muted: entry.muted != 0)
            }
        }

        processCache = newCache
        return orderedBundleIDs
    }

    public func setVolume(bundleID: String, volume: Float) -> Result<Void, VirtualDriverBridgeError> {
        guard let pid = processCache[bundleID]?.pid else {
            return querySetVolume(bundleID: bundleID, volume: volume)
        }
        let status = setFloat(selector: kBGMPropertyProcessVolume, pid: pid, value: max(0, min(volume, 2)))
        if status == noErr {
            processCache[bundleID]?.volume = max(0, min(volume, 2))
            return .success(())
        }
        return .failure(.setVolumeFailed(status))
    }

    public func volume(bundleID: String) -> Result<Float, VirtualDriverBridgeError> {
        if let cached = processCache[bundleID]?.volume {
            return .success(cached)
        }
        guard let pid = processCache[bundleID]?.pid ?? lookupPID(bundleID: bundleID) else {
            return .success(1.0)
        }
        var value: Float = 1.0
        var addr = AudioObjectPropertyAddress(
            mSelector: kBGMPropertyProcessVolume,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidCopy = pid
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &pidCopy, &size, &value)
        if status == noErr {
            processCache[bundleID] = ProcessSnapshot(pid: pid, volume: value, muted: processCache[bundleID]?.muted ?? false)
            return .success(value)
        }
        return .failure(.getVolumeFailed(status))
    }

    public func mute(bundleID: String, muted: Bool) -> Result<Void, VirtualDriverBridgeError> {
        guard let pid = processCache[bundleID]?.pid ?? lookupPID(bundleID: bundleID) else {
            return .success(())
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: kBGMPropertyProcessMute,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = muted ? 1 : 0
        var pidCopy = pid
        let status = AudioObjectSetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &pidCopy, UInt32(MemoryLayout<UInt32>.size), &value)
        if status == noErr {
            if var snapshot = processCache[bundleID] {
                snapshot.muted = muted
                processCache[bundleID] = snapshot
            }
            return .success(())
        }
        return .failure(.muteFailed(status))
    }

    public func isMuted(bundleID: String) -> Result<Bool, VirtualDriverBridgeError> {
        if let cached = processCache[bundleID]?.muted {
            return .success(cached)
        }
        guard let pid = processCache[bundleID]?.pid ?? lookupPID(bundleID: bundleID) else {
            return .success(false)
        }
        var addr = AudioObjectPropertyAddress(
            mSelector: kBGMPropertyProcessMute,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var pidCopy = pid
        let status = AudioObjectGetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &pidCopy, &size, &value)
        if status == noErr {
            if var snapshot = processCache[bundleID] {
                snapshot.muted = value != 0
                processCache[bundleID] = snapshot
            }
            return .success(value != 0)
        }
        return .failure(.getVolumeFailed(status))
    }

    // MARK: - Helpers

    private func locateDevice() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            deviceID = kAudioObjectUnknown
            return
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr else {
            deviceID = kAudioObjectUnknown
            return
        }

        for dev in devices {
            if deviceUID(for: dev) == kBGMDeviceUID {
                deviceID = dev
                return
            }
        }

        deviceID = kAudioObjectUnknown
    }

    private func deviceUID(for device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return nil }
        var uid: CFString? = nil
        let status = withUnsafeMutablePointer(to: &uid) { pointer -> OSStatus in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else { return nil }
        return uid as String
    }

    private func bundleIdentifier(from entry: BGMProcessEntry) -> String {
        return withUnsafeBytes(of: entry.bundleID) { rawBytes -> String in
            guard let base = rawBytes.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    private func setFloat(selector: AudioObjectPropertySelector, pid: pid_t, value: Float) -> OSStatus {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableValue = value
        var pidCopy = pid
        return AudioObjectSetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &pidCopy, UInt32(MemoryLayout<Float>.size), &mutableValue)
    }

    private func lookupPID(bundleID: String) -> pid_t? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        _ = refreshActiveApplications()
        return processCache[bundleID]?.pid
    }

    private func querySetVolume(bundleID: String, volume: Float) -> Result<Void, VirtualDriverBridgeError> {
        guard let pid = lookupPID(bundleID: bundleID) else { return .success(()) }
        let status = setFloat(selector: kBGMPropertyProcessVolume, pid: pid, value: max(0, min(volume, 2)))
        if status == noErr {
            processCache[bundleID] = ProcessSnapshot(pid: pid, volume: max(0, min(volume, 2)), muted: processCache[bundleID]?.muted ?? false)
            return .success(())
        }
        return .failure(.setVolumeFailed(status))
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
        func format(_ status: OSStatus) -> String { "OSStatus \(status)" }

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
