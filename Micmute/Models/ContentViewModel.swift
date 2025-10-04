import SwiftUI
import CoreAudio
import CoreAudioKit
import AudioToolbox
import Combine

private let virtualMasterScalarVolumeSelector = AudioObjectPropertySelector(0x766D7663) // 'vmvc'

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
    @Published public var outputVolume: CGFloat = 1.0

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
    @AppStorage(AppStorageEntry.syncSoundEffectsWithOutput.rawValue) var syncSoundEffectsWithOutput: Bool = true

    var notificationWindowController: NotificationWindowController?
    private var isPushToTalkActive = false
    private var wasMutedBeforePushToTalk = true
    private var observedOutputVolumeDeviceID: AudioDeviceID?
    private var outputVolumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var didTearDown = false
    
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

    func tearDown() {
        guard !didTearDown else { return }
        didTearDown = true

        GlobalShortcutManager.shared.unregister(.toggleMute)
        GlobalShortcutManager.shared.unregister(.checkMute)
        GlobalShortcutManager.shared.unregister(.pushToTalk)
        unregisterDeviceChangeListener()
        stopObservingOutputVolume()
        NotificationCenter.default.removeObserver(self, name: .notificationConfigurationDidChange, object: nil)
        notificationWindowController?.close()
        notificationWindowController = nil
        print("ContentViewModel torn down")
    }
    
    func toggleMute(deviceID: AudioDeviceID) {
        let resolvedDeviceID = syncSelectedInputDeviceWithSystemDefault() ?? selectedDeviceID

        let currentMute = currentDeviceMuteState(deviceID: resolvedDeviceID, scope: kAudioObjectPropertyScopeInput) ?? isMuted
        let targetMute = !currentMute

        if targetMute {
            muteMicrophone(selectedDevice: resolvedDeviceID)
            isMuted = true
        } else {
            unmuteMicrophone(selectedDevice: resolvedDeviceID)
            isMuted = false
        }

        publishMuteStateChange()
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

    private func publishMuteStateChange() {
        notificationWindowController?.close()
        notificationWindowController = nil

        if isNotificationEnabled {
            let controller = NotificationWindowController(
                isMuted: isMuted,
                animationType: animationType,
                animationDuration: animationDuration,
                displayOption: displayOption,
                placement: placement,
                padding: padding,
                pinBehavior: notificationPinBehavior
            )
            notificationWindowController = controller
            controller.showWindow(nil)
        }

        NotificationCenter.default.post(name: NSNotification.Name("MuteStateChanged"), object: nil)
    }

    // MARK: - Mute state reconciliation

    private func reconcileMuteState(deviceID: AudioDeviceID, fallbackGain: Float) {
        if let mute = currentDeviceMuteState(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput) {
            if mute != isMuted {
                isMuted = mute
                publishMuteStateChange()
            }
            return
        }

        let threshold: Float = 0.0001
        if fallbackGain <= threshold {
            if !isMuted {
                isMuted = true
                publishMuteStateChange()
            }
        } else {
            if isMuted {
                isMuted = false
                publishMuteStateChange()
            }
        }
    }

    // MARK: - Shortcuts

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

    // MARK: - Audio devices listing / selection

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
        
        availableDevices = updatedInputDevices
        availableOutputDevices = updatedOutputDevices

        // Preferuj aktualnie wybrane urządzenie; dopiero potem system default; na końcu pierwsze dostępne.
        let systemInputDefault = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        var resolvedInputDevice = selectedDeviceID

        if !updatedInputDevices.keys.contains(resolvedInputDevice) {
            if let sys = systemInputDefault, updatedInputDevices.keys.contains(sys) {
                resolvedInputDevice = sys
            } else {
                resolvedInputDevice = updatedInputDevices.keys.first ?? kAudioObjectUnknown
            }
        }

        if selectedDeviceID != resolvedInputDevice {
            selectedDeviceID = resolvedInputDevice
        }
        loadInputGain(for: resolvedInputDevice)

        let systemOutputDefault = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        var resolvedOutputDevice = selectedOutputDeviceID

        if !updatedOutputDevices.keys.contains(resolvedOutputDevice) {
            if let sys = systemOutputDefault, updatedOutputDevices.keys.contains(sys) {
                resolvedOutputDevice = sys
            } else {
                resolvedOutputDevice = updatedOutputDevices.keys.first ?? kAudioObjectUnknown
            }
        }

        if selectedOutputDeviceID != resolvedOutputDevice {
            selectedOutputDeviceID = resolvedOutputDevice
        }

        refreshOutputVolumeState()
        syncSoundEffectsToCurrentOutput()
    }

    @discardableResult
    func syncSelectedInputDeviceWithSystemDefault() -> AudioDeviceID? {
        guard let defaultDeviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice) else {
            return nil
        }

        if !availableDevices.keys.contains(defaultDeviceID) {
            loadAudioDevices()
        }

        if availableDevices.keys.contains(defaultDeviceID) && selectedDeviceID != defaultDeviceID {
            selectedDeviceID = defaultDeviceID
            loadInputGain(for: defaultDeviceID)
        } else if selectedDeviceID == defaultDeviceID {
            loadInputGain(for: defaultDeviceID)
        }

        return defaultDeviceID
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

        selectedDeviceID = defaultDeviceID
        loadInputGain(for: defaultDeviceID)
    }

    func setDefaultSystemOutputDevice() {
        guard let defaultDeviceID = systemDefaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice) else { return }

        selectedOutputDeviceID = defaultDeviceID
        refreshOutputVolumeState()
        syncSoundEffectsToCurrentOutput()
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
        } else if syncSoundEffectsWithOutput {
            changeSystemSoundEffectsDevice(to: deviceID)
        }
    }

    private func changeSystemSoundEffectsDevice(to deviceID: AudioDeviceID) {
        guard deviceID != kAudioObjectUnknown else { return }

        var newDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &newDeviceID
        )

        if status != noErr {
            print("Error setting system sound effects device: \(status)")
        }
    }

    func syncSoundEffectsToCurrentOutput() {
        guard syncSoundEffectsWithOutput else { return }
        let currentOutput = selectedOutputDeviceID
        guard currentOutput != kAudioObjectUnknown else { return }
        changeSystemSoundEffectsDevice(to: currentOutput)
    }

    // MARK: - Output volume

    func refreshOutputVolumeState() {
        let deviceID = selectedOutputDeviceID
        loadOutputVolume(for: deviceID)
        observeOutputVolume(for: deviceID)
    }

    func loadOutputVolume(for deviceID: AudioDeviceID) {
        guard deviceID != kAudioObjectUnknown,
              availableOutputDevices.keys.contains(deviceID),
              var address = outputVolumePropertyAddress(for: deviceID) else {
            outputVolume = 1.0
            return
        }

        var volume: Float32 = 1.0
        var size = UInt32(MemoryLayout.size(ofValue: volume))
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)

        if status == noErr {
            outputVolume = CGFloat(min(max(volume, 0), 1))
        } else {
            print("Error loading output volume: \(status)")
        }
    }

    func setOutputVolume(for deviceID: AudioDeviceID, volume: CGFloat) {
        guard deviceID != kAudioObjectUnknown,
              availableOutputDevices.keys.contains(deviceID),
              var address = outputVolumePropertyAddress(for: deviceID) else {
            return
        }

        var clampedVolume = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout.size(ofValue: clampedVolume))
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clampedVolume)

        if status != noErr {
            print("Error setting output volume: \(status)")
        } else {
            outputVolume = CGFloat(clampedVolume)
        }
    }

    private func observeOutputVolume(for deviceID: AudioDeviceID) {
        guard deviceID != kAudioObjectUnknown,
              availableOutputDevices.keys.contains(deviceID) else {
            stopObservingOutputVolume()
            return
        }

        if observedOutputVolumeDeviceID == deviceID,
           outputVolumeListenerBlock != nil {
            return
        }

        stopObservingOutputVolume()

        guard var address = outputVolumePropertyAddress(for: deviceID) else {
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.loadOutputVolume(for: deviceID)
        }

        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        observedOutputVolumeDeviceID = deviceID
        outputVolumeListenerBlock = block
    }

    private func stopObservingOutputVolume() {
        guard let deviceID = observedOutputVolumeDeviceID,
              let block = outputVolumeListenerBlock else {
            observedOutputVolumeDeviceID = nil
            outputVolumeListenerBlock = nil
            return
        }

        if var address = outputVolumePropertyAddress(for: deviceID) {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }

        observedOutputVolumeDeviceID = nil
        outputVolumeListenerBlock = nil
    }

    private func outputVolumePropertyAddress(for deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        var virtualMasterAddress = AudioObjectPropertyAddress(
            mSelector: virtualMasterScalarVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &virtualMasterAddress) {
            return virtualMasterAddress
        }

        var scalarAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(deviceID, &scalarAddress) {
            return scalarAddress
        }

        return nil
    }
    
    // MARK: - Input gain and mute

    func loadInputGain(for deviceID: AudioDeviceID) {
        guard availableDevices.keys.contains(deviceID) else {
            inputGain = 0.0
            reconcileMuteState(deviceID: deviceID, fallbackGain: 0.0)
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
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &gain)
            if status != noErr {
                gain = 0.0
            }
        }

        inputGain = gain
        reconcileMuteState(deviceID: deviceID, fallbackGain: gain)
    }
        
    func setInputGain(for deviceID: AudioDeviceID, gain: CGFloat) {
        guard deviceID != kAudioObjectUnknown else { return }

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
            } else if deviceID == selectedDeviceID {
                inputGain = Float(gain)
            }
        }
    }

    private func deviceSupportsMute(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(deviceID, &address)
    }

    private func currentDeviceMuteState(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool? {
        guard deviceSupportsMute(deviceID: deviceID, scope: scope) else { return nil }
        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: muteValue))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue)
        guard status == noErr else {
            print("Error reading mute state: \(status)")
            return nil
        }
        return muteValue != 0
    }

    private func setDeviceMute(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, mute: Bool) -> Bool {
        var muteValue: UInt32 = mute ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &muteValue
        )
        if status != noErr {
            print("Error setting mute: \(status)")
            return false
        }
        return true
    }
    
    func muteMicrophone(selectedDevice: AudioDeviceID) {
        guard selectedDevice != kAudioObjectUnknown else { return }

        if deviceSupportsMute(deviceID: selectedDevice, scope: kAudioObjectPropertyScopeInput) {
            if setDeviceMute(deviceID: selectedDevice, scope: kAudioObjectPropertyScopeInput, mute: true) {
                return
            }
        }
        setInputGain(for: selectedDevice, gain: 0.0)
    }
    
    func unmuteMicrophone(selectedDevice: AudioDeviceID) {
        guard selectedDevice != kAudioObjectUnknown else { return }

        if deviceSupportsMute(deviceID: selectedDevice, scope: kAudioObjectPropertyScopeInput) {
            _ = setDeviceMute(deviceID: selectedDevice, scope: kAudioObjectPropertyScopeInput, mute: false)
            setInputGain(for: selectedDevice, gain: unmuteGain)
            return
        }

        setInputGain(for: selectedDevice, gain: unmuteGain)
    }
    
    // MARK: - Device change notifications

    func registerDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, deviceChangeListener, nil)
    }
    
    nonisolated func unregisterDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, deviceChangeListener, nil)
    }
}
