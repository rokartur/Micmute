//
//  ContentView.swift
//  Micmute
//
//  Created by artur on 10/02/2025.
//

import SwiftUI
import CoreAudio
import CoreAudioKit
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    private let shortcutPreferences: ShortcutPreferences
    private var shortcutCancellables: Set<AnyCancellable> = []

    @AppStorage(AppStorageEntry.selectedDeviceID.rawValue) private var storedSelectedDeviceID: Int = Int(kAudioObjectUnknown)
    var selectedDeviceID: AudioDeviceID {
        get { AudioDeviceID(storedSelectedDeviceID) }
        set { storedSelectedDeviceID = Int(newValue) }
    }

    @AppStorage(AppStorageEntry.selectedOutputDeviceID.rawValue) private var storedSelectedOutputDeviceID: Int = Int(kAudioObjectUnknown)
    var selectedOutputDeviceID: AudioDeviceID {
        get { AudioDeviceID(storedSelectedOutputDeviceID) }
        set { storedSelectedOutputDeviceID = Int(newValue) }
    }
    
    @AppStorage(AppStorageEntry.inputGain.rawValue) private var storedInputGain: Double = 0.0
    var inputGain: Float {
        get { Float(storedInputGain) }
        set { storedInputGain = Double(newValue) }
    }
    
    @AppStorage(AppStorageEntry.unmuteGain.rawValue) private var storedUnmuteGain: Double = 1.0
    var unmuteGain: CGFloat {
        get { CGFloat(storedUnmuteGain) }
        set { storedUnmuteGain = Double(newValue) }
    }

    @Published public var availableDevices: [AudioDeviceID: String] = [:]
    @Published public var availableOutputDevices: [AudioDeviceID: String] = [:]

    @AppStorage(AppStorageEntry.animationType.rawValue) var animationType: AnimationType = .scale
    @AppStorage(AppStorageEntry.animationDuration.rawValue) var animationDuration: Double = 1.3
    @AppStorage(AppStorageEntry.isNotificationEnabled.rawValue) var isNotificationEnabled: Bool = true
    @AppStorage(AppStorageEntry.isMuted.rawValue) var isMuted: Bool = false
    @AppStorage(AppStorageEntry.displayOption.rawValue) var displayOption: DisplayOption = .largeBoth
    @AppStorage(AppStorageEntry.placement.rawValue) var placement: Placement = .centerBottom
    @AppStorage(AppStorageEntry.padding.rawValue) var padding: Double = 70.0
    @AppStorage(AppStorageEntry.notificationPinBehavior.rawValue) var notificationPinBehavior: NotificationPinBehavior = .disabled
    @AppStorage(AppStorageEntry.iconSize.rawValue) var iconSize: Int = 70
    @AppStorage(AppStorageEntry.pushToTalk.rawValue) var pushToTalk: Bool = false
    @AppStorage(AppStorageEntry.menuGrayscaleIcon.rawValue) var menuGrayscaleIcon: Bool = false
    @AppStorage(AppStorageEntry.menuBehaviorOnClick.rawValue) var menuBehaviorOnClick: MenuBarBehavior = .menu

    var notificationWindowController: NotificationWindowController?
    private var isPushToTalkActive = false
    private var wasMutedBeforePushToTalk = true
    
    init(shortcutPreferences: ShortcutPreferences) {
        self.shortcutPreferences = shortcutPreferences
        configureShortcutBindings()
    loadAudioDevices()
    setDefaultSystemInputDevice()
    setDefaultSystemOutputDevice()
        registerDeviceChangeListener()
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotificationConfigurationChange(_:)), name: .notificationConfigurationDidChange, object: nil)

        print("ContentViewModel initialized")
    }

    deinit {
        GlobalShortcutManager.shared.unregister(.toggleMute)
        GlobalShortcutManager.shared.unregister(.checkMute)
        GlobalShortcutManager.shared.unregister(.pushToTalk)
        unregisterDeviceChangeListener()
        NotificationCenter.default.removeObserver(self, name: .notificationConfigurationDidChange, object: nil)
        print("ContentViewModel deinitialized")
    }
    
    func toggleMute(deviceID: AudioDeviceID) {
        isMuted.toggle()
        if isMuted {
            muteMicrophone(selectedDevice: deviceID)
        } else {
            unmuteMicrophone(selectedDevice: deviceID)
        }
        
        if isNotificationEnabled {
            notificationWindowController?.close()
            notificationWindowController = NotificationWindowController(
                isMuted: isMuted,
                animationType: animationType,
                animationDuration: animationDuration,
                displayOption: displayOption,
                placement: placement,
                padding: padding,
                pinBehavior: notificationPinBehavior
            )
            notificationWindowController?.showWindow(nil)
        }

        NotificationCenter.default.post(name: NSNotification.Name("MuteStateChanged"), object: nil)
    }
    
    func checkMuteStatus() {
        notificationWindowController?.close()
        notificationWindowController = NotificationWindowController(
            isMuted: isMuted,
            animationType: animationType,
            animationDuration: animationDuration,
            displayOption: displayOption,
            placement: placement,
            padding: padding,
            pinBehavior: notificationPinBehavior
        )
        notificationWindowController?.showWindow(nil)
    }

    @objc private func handleNotificationConfigurationChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.refreshPinnedNotification()
        }
    }

    private func refreshPinnedNotification() {
        guard let controller = notificationWindowController,
              let window = controller.window,
              window.isVisible else { return }

        if !isNotificationEnabled || notificationPinBehavior.shouldAutoHide(isMuted: isMuted) {
            controller.close()
            notificationWindowController = nil
            return
        }

        controller.close()
        let newController = NotificationWindowController(
            isMuted: isMuted,
            animationType: animationType,
            animationDuration: animationDuration,
            displayOption: displayOption,
            placement: placement,
            padding: padding,
            pinBehavior: notificationPinBehavior
        )
        notificationWindowController = newController
        newController.showWindow(nil)
    }

    private func configureShortcutBindings() {
        registerToggleMuteShortcut(shortcutPreferences.toggleMuteShortcut)
        registerCheckMuteShortcut(shortcutPreferences.checkMuteShortcut)
        registerPushToTalkShortcut(shortcutPreferences.pushToTalkShortcut)

        shortcutPreferences.$toggleMuteShortcut
            .sink { [weak self] shortcut in
                self?.registerToggleMuteShortcut(shortcut)
            }
            .store(in: &shortcutCancellables)

        shortcutPreferences.$checkMuteShortcut
            .sink { [weak self] shortcut in
                self?.registerCheckMuteShortcut(shortcut)
            }
            .store(in: &shortcutCancellables)

        shortcutPreferences.$pushToTalkShortcut
            .sink { [weak self] shortcut in
                self?.registerPushToTalkShortcut(shortcut)
            }
            .store(in: &shortcutCancellables)
    }

    private func registerToggleMuteShortcut(_ shortcut: Shortcut?) {
        GlobalShortcutManager.shared.register(.toggleMute, shortcut: shortcut, keyUp: { [weak self] in
            guard let self else { return }
            self.toggleMute(deviceID: self.selectedDeviceID)
        })
    }

    private func registerCheckMuteShortcut(_ shortcut: Shortcut?) {
        GlobalShortcutManager.shared.register(.checkMute, shortcut: shortcut, keyUp: { [weak self] in
            self?.checkMuteStatus()
        })
    }

    private func registerPushToTalkShortcut(_ shortcut: Shortcut?) {
        GlobalShortcutManager.shared.register(
            .pushToTalk,
            shortcut: shortcut,
            keyDown: { [weak self] in self?.handlePushToTalkDown() },
            keyUp: { [weak self] in self?.handlePushToTalkUp() }
        )
    }

    private func handlePushToTalkDown() {
        guard pushToTalk else { return }
        guard !isPushToTalkActive else { return }

        isPushToTalkActive = true
        wasMutedBeforePushToTalk = isMuted

        if isMuted {
            toggleMute(deviceID: selectedDeviceID)
        }
    }

    private func handlePushToTalkUp() {
        guard isPushToTalkActive else { return }

        isPushToTalkActive = false

        if wasMutedBeforePushToTalk && !isMuted {
            toggleMute(deviceID: selectedDeviceID)
        }
    }

    func loadAudioDevices() {
        var updatedInputDevices: [AudioDeviceID: String] = [:]
        var updatedOutputDevices: [AudioDeviceID: String] = [:]
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)

        for deviceID in deviceIDs {
            guard let deviceName = deviceName(for: deviceID) else { continue }

            if channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput) > 0 {
                if !deviceName.lowercased().contains("iphone") {
                    updatedInputDevices[deviceID] = deviceName
                }
            }

            if channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0 {
                updatedOutputDevices[deviceID] = deviceName
            }
        }
        
        DispatchQueue.main.async {
            self.availableDevices = updatedInputDevices
            self.availableOutputDevices = updatedOutputDevices
            
            if !updatedInputDevices.keys.contains(self.selectedDeviceID) {
                self.selectedDeviceID = updatedInputDevices.keys.first ?? kAudioObjectUnknown
                self.loadInputGain(for: self.selectedDeviceID)
            }

            if !updatedOutputDevices.keys.contains(self.selectedOutputDeviceID) {
                if let systemDefault = self.systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice),
                   updatedOutputDevices.keys.contains(systemDefault) {
                    self.selectedOutputDeviceID = systemDefault
                } else {
                    self.selectedOutputDeviceID = updatedOutputDevices.keys.first ?? kAudioObjectUnknown
                }
            }
        }
    }
    
    private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var channelCount: UInt32 = 0
        var propertySize = UInt32(0)
        var channelAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyDataSize(deviceID, &channelAddress, 0, nil, &propertySize) == noErr else {
            return 0
        }

        let audioBufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { audioBufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &channelAddress, 0, nil, &propertySize, audioBufferList) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)

        for buffer in bufferList {
            channelCount += buffer.mNumberChannels
        }

        return channelCount
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status: OSStatus = withUnsafeMutableBytes(of: &deviceName) { bytes in
            guard let pointer = bytes.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }

            return AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, pointer)
        }
        guard status == noErr else { return nil }

        let name = deviceName as String
        return name.isEmpty ? nil : name
    }
        
    private func systemDefaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var defaultDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout.size(ofValue: defaultDeviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDeviceID)
        guard status == noErr, defaultDeviceID != kAudioObjectUnknown else { return nil }
        return defaultDeviceID
    }
    
    func setDefaultSystemInputDevice() {
        guard let defaultDeviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice) else { return }

        DispatchQueue.main.async {
            self.selectedDeviceID = defaultDeviceID
            self.loadInputGain(for: defaultDeviceID)
        }
    }

    func setDefaultSystemOutputDevice() {
        guard let defaultDeviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice) else { return }

        DispatchQueue.main.async {
            self.selectedOutputDeviceID = defaultDeviceID
        }
    }
    
    func changeDefaultInputDevice(to deviceID: AudioDeviceID) {
        var newDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address,
                                                0,
                                                nil,
                                                size,
                                                &newDeviceID)
        if status != noErr {
            print("Error setting default input device: \(status)")
        }
    }

    func changeDefaultOutputDevice(to deviceID: AudioDeviceID) {
        var newDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address,
                                                0,
                                                nil,
                                                size,
                                                &newDeviceID)
        if status != noErr {
            print("Error setting default output device: \(status)")
        }
    }
    
    func loadInputGain(for deviceID: AudioDeviceID) {
        guard availableDevices.keys.contains(deviceID) else {
            inputGain = 0.0
            return
        }
        
        var gain: Float32 = 0.0
        var size = UInt32(MemoryLayout.size(ofValue: gain))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &gain)
            inputGain = gain
        } else {
            inputGain = 0.0
        }
    }
        
    func setInputGain(for deviceID: AudioDeviceID, gain: CGFloat) {
        guard availableDevices.keys.contains(deviceID) else { return }
        
        var gainFloat: Float32 = Float(gain)
        let size = UInt32(MemoryLayout.size(ofValue: gainFloat))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if AudioObjectHasProperty(deviceID, &address) {
            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &gainFloat)
            if status != noErr {
                print("Error setting input gain: \(status)")
            }
        }
    }
    
    func muteMicrophone(selectedDevice: AudioDeviceID) {
        setInputGain(for: selectedDevice, gain: 0.0)
    }
    
    func unmuteMicrophone(selectedDevice: AudioDeviceID) {
        setInputGain(for: selectedDevice, gain: unmuteGain)
    }
    
    func registerDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, deviceChangeListener, nil)
    }
    
    nonisolated(unsafe) func unregisterDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, deviceChangeListener, nil)
    }
}
