//
//  ContentView.swift
//  Micmute
//
//  Created by artur on 10/02/2025.
//

import SwiftUI
import CoreAudio
import CoreAudioKit
import MacControlCenterUI
import KeyboardShortcuts

class ContentViewModel: ObservableObject {
    @AppStorage("selectedDeviceID") private var storedSelectedDeviceID: Int = Int(kAudioObjectUnknown)
    var selectedDeviceID: AudioDeviceID {
        get { AudioDeviceID(storedSelectedDeviceID) }
        set { storedSelectedDeviceID = Int(newValue) }
    }
    
    @AppStorage("inputGain") private var storedInputGain: Double = 0.0
    var inputGain: Float {
        get { Float(storedInputGain) }
        set { storedInputGain = Double(newValue) }
    }
    
    @AppStorage("unmuteGain") private var storedUnmuteGain: Double = 1.0
    var unmuteGain: CGFloat {
        get { CGFloat(storedUnmuteGain) }
        set { storedUnmuteGain = Double(newValue) }
    }

    @Published public var availableDevices: [AudioDeviceID: String] = [:]

    @AppStorage("animationType") var animationType: AnimationType = .scale
    @AppStorage("animationDuration") var animationDuration: Double = 1.3
    @AppStorage("isNotificationEnabled") var isNotificationEnabled: Bool = true
    @AppStorage("isMuted") var isMuted: Bool = false
    @AppStorage("displayOption") var displayOption: DisplayOption = .largeBoth
    @AppStorage("placement") var placement: Placement = .centerBottom
    @AppStorage("padding") var padding: Double = 70.0
    @AppStorage("iconSize") var iconSize: Int = 70
    @AppStorage("pushToTalk") var pushToTalk: Bool = false
    @AppStorage("menuGrayscaleIcon") var menuGrayscaleIcon: Bool = false
    @AppStorage("menuBehaviorOnClick") var menuBehaviorOnClick: MenuBarBehavior = .menu

    private let refreshInterval: TimeInterval = 1.0
    @State private var refreshTimer: Timer?
    var notificationWindowController: NotificationWindowController?
    
    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleMuteShortcut) { [self] in
            self.toggleMute(deviceID: self.selectedDeviceID)
        }
        KeyboardShortcuts.onKeyUp(for: .checkMuteShortcut) { [self] in
            self.checkMuteStatus()
        }
        loadAudioDevices()
        setDefaultSystemInputDevice()
        registerDeviceChangeListener()
        startAutoRefresh()
        print("ContentViewModel initialized")
    }

    deinit {
        unregisterDeviceChangeListener()
        stopAutoRefresh()
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
            notificationWindowController = NotificationWindowController(isMuted: isMuted, animationType: animationType, animationDuration: animationDuration, displayOption: displayOption, placement: placement, padding: padding)
            notificationWindowController?.showWindow(nil)
        }
    }
    
    func checkMuteStatus() {
        notificationWindowController?.close()
        notificationWindowController = NotificationWindowController(isMuted: isMuted, animationType: animationType, animationDuration: animationDuration, displayOption: displayOption, placement: placement, padding: padding)
        notificationWindowController?.showWindow(nil)
    }

    func loadAudioDevices() {
        var updatedDevices: [AudioDeviceID: String] = [:]
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
            var inputChannels: UInt32 = 0
            var propertySize = UInt32(0)
            var inputChannelAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectGetPropertyDataSize(deviceID, &inputChannelAddress, 0, nil, &propertySize)

            let audioBufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { audioBufferList.deallocate() }

            AudioObjectGetPropertyData(deviceID, &inputChannelAddress, 0, nil, &propertySize, audioBufferList)

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for buffer in bufferList {
                inputChannels += buffer.mNumberChannels
            }

            if inputChannels > 0 {
                var deviceName: CFString = "" as CFString
                var nameSize = UInt32(MemoryLayout<CFString>.size)
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &deviceName)
                updatedDevices[deviceID] = deviceName as String
            }
        }
        
        DispatchQueue.main.async {
            self.availableDevices = updatedDevices
            
            if !updatedDevices.keys.contains(self.selectedDeviceID) {
                self.selectedDeviceID = updatedDevices.keys.first ?? kAudioObjectUnknown
                self.loadInputGain(for: self.selectedDeviceID)
            }
        }
    }
        
    func setDefaultSystemInputDevice() {
        var defaultDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout.size(ofValue: defaultDeviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultDeviceID)
        
        if status == noErr && defaultDeviceID != kAudioObjectUnknown {
            DispatchQueue.main.async {
                self.selectedDeviceID = defaultDeviceID
                self.loadInputGain(for: defaultDeviceID)
            }
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
    
    func unregisterDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, deviceChangeListener, nil)
    }
    
    func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            self.loadAudioDevices()
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
