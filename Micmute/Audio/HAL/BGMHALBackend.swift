import Foundation
import CoreAudio
import os.log

/// Experimental backend targeting a CoreAudio HAL plugin based virtual device (BackgroundMusic style).
/// This is a skeleton; full property selector based IPC still to be implemented.
final class BGMHALBackend {
    private let logger = Logger(subsystem: "com.rokartur.Micmute", category: "BGMHALBackend")
    private(set) var deviceID: AudioDeviceID = kAudioObjectUnknown

    // Custom property selectors we would negotiate with the HAL plugin.
    // Placeholder four-char codes – real plugin must implement these.
    private let processListSelector: AudioObjectPropertySelector = 0x706c7374 // 'plst'
    private let processVolumeSelector: AudioObjectPropertySelector = 0x70766f6c // 'pvol'
    private let processMuteSelector: AudioObjectPropertySelector = 0x706d7574 // 'pmut'

    private let deviceUID = "BGMDevice" // Must match plugin Info.plist

    init() {
        locateDevice()
    }

    var isAvailable: Bool { deviceID != kAudioObjectUnknown }

    @discardableResult
    func setAsDefaultOutput() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev = deviceID
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
        if status != noErr { logger.error("Failed to set HAL device as default output status=\(status)") }
        return status == noErr
    }

    // Cache mapping bundleID -> pid for quicker reverse lookups
    private var bundleToPID: [String: pid_t] = [:]

    // MARK: - PerAppAudioBackend
    func refreshDevice() {
        locateDevice()
    }

    struct ProcessEntry {
        let pid: pid_t
        let volume: Float
        let muted: Bool
        let bundleID: String
    }

    func processEntries() -> [ProcessEntry] {
        guard isAvailable else {
            bundleToPID = [:]
            return []
        }

        let entries = fetchProcessEntries()
        var map: [String: pid_t] = [:]
        entries.forEach { entry in
            let bundleID = entry.bundleIDString
            if !bundleID.isEmpty {
                map[bundleID] = entry.pid
            } else {
                map["pid_\(entry.pid)"] = entry.pid
            }
        }
        bundleToPID = map
        return entries.map { entry in
            ProcessEntry(pid: entry.pid, volume: entry.volume, muted: entry.muted, bundleID: entry.bundleIDString)
        }
    }

    func activeBundleIDs() -> [String] {
        processEntries().map { $0.bundleID }
    }

    func volume(bundleID: String) -> Result<Float, Error> {
        guard let pid = bundleToPID[bundleID] else { return .success(1.0) }
        return queryFloat(selector: processVolumeSelector, pid: pid)
    }

    func isMuted(bundleID: String) -> Result<Bool, Error> {
        guard let pid = bundleToPID[bundleID] else { return .success(false) }
        switch queryUInt32(selector: processMuteSelector, pid: pid) {
        case .success(let v): return .success(v != 0)
        case .failure(let e): return .failure(e)
        }
    }

    func setVolume(bundleID: String, volume: Float) -> Result<Void, Error> {
        guard let pid = bundleToPID[bundleID] else { return .success(()) }
        return setFloat(selector: processVolumeSelector, pid: pid, value: max(0,min(volume,2)))
    }

    func mute(bundleID: String, muted: Bool) -> Result<Void, Error> {
        guard let pid = bundleToPID[bundleID] else { return .success(()) }
        return setUInt32(selector: processMuteSelector, pid: pid, value: muted ? 1 : 0)
    }

    // MARK: - Device Discovery
    private func locateDevice() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize) == noErr else { return }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &devices) == noErr else { return }
        for dev in devices {
            if deviceUIDFor(device: dev) == deviceUID {
                deviceID = dev
                logger.info("HAL backend located device id: \(dev)")
                return
            }
        }
    }

    private func deviceUIDFor(device: AudioDeviceID) -> String? {
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
}

// MARK: - Private helpers (C bridge)
private extension BGMHALBackend {
    struct RawProcessEntry {
        var pid: pid_t
        var volume: Float
        var muted: Bool
        var bundleID: String
        init(from entry: BGMProcessEntry) {
            pid = entry.pid
            volume = entry.volume
            muted = entry.muted != 0
            bundleID = withUnsafeBytes(of: entry.bundleID) { rawBytes -> String in
                guard let base = rawBytes.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
        }

        var bundleIDString: String { bundleID }
    }

    func fetchProcessEntries() -> [RawProcessEntry] {
        guard deviceID != kAudioObjectUnknown else { return [] }
        var addr = AudioObjectPropertyAddress(
            mSelector: processListSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let statusSize = AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size)
        guard statusSize == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<BGMProcessEntry>.size
        guard count > 0 else { return [] }
        let buffer = UnsafeMutablePointer<BGMProcessEntry>.allocate(capacity: count)
        defer { buffer.deallocate() }
        var mutableSize = size
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &mutableSize, buffer)
        guard status == noErr else { return [] }
        let entries = Array(UnsafeBufferPointer(start: buffer, count: count))
        return entries.map { RawProcessEntry(from: $0) }
    }

    func queryFloat(selector: AudioObjectPropertySelector, pid: pid_t) -> Result<Float, Error> {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        var qPID = pid
        let status = AudioObjectGetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &qPID, &size, &value)
        if status == noErr { return .success(value) }
        return .failure(NSError(domain: "BGMHALBackend", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Get volume failed status=\(status)"]))
    }

    func queryUInt32(selector: AudioObjectPropertySelector, pid: pid_t) -> Result<UInt32, Error> {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var qPID = pid
        let status = AudioObjectGetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &qPID, &size, &value)
        if status == noErr { return .success(value) }
        return .failure(NSError(domain: "BGMHALBackend", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Get mute failed status=\(status)"]))
    }

    func setFloat(selector: AudioObjectPropertySelector, pid: pid_t, value: Float) -> Result<Void, Error> {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = value
        var qPID = pid
        let status = AudioObjectSetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &qPID, UInt32(MemoryLayout<Float>.size), &v)
        if status == noErr { return .success(()) }
        return .failure(NSError(domain: "BGMHALBackend", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Set volume failed status=\(status)"]))
    }

    func setUInt32(selector: AudioObjectPropertySelector, pid: pid_t, value: UInt32) -> Result<Void, Error> {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = value
        var qPID = pid
        let status = AudioObjectSetPropertyData(deviceID, &addr, UInt32(MemoryLayout<pid_t>.size), &qPID, UInt32(MemoryLayout<UInt32>.size), &v)
        if status == noErr { return .success(()) }
        return .failure(NSError(domain: "BGMHALBackend", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Set mute failed status=\(status)"]))
    }
}
