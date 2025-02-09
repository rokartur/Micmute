import SwiftUI
import CoreAudio
import CoreAudioKit
import MacControlCenterUI


class ContentViewModel: ObservableObject {
    @AppStorage("selectedDeviceID") private var storedSelectedDeviceID: Int = Int(kAudioObjectUnknown)
    var selectedDeviceID: UInt32 {
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

    @AppStorage("isMuted") var isMuted: Bool = false

    private let refreshInterval: TimeInterval = 1.0
    @State private var refreshTimer: Timer?
    
    init() {
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
            setInputGain(for: selectedDeviceID, gain: 0.0)
        } else {
            setInputGain(for: selectedDeviceID, gain: unmuteGain)
        }
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
        
        var gain = gain
        let size = UInt32(MemoryLayout.size(ofValue: gain))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &gain)
        }
    }
    
    func muteMicrophone() {
        setInputGain(for: selectedDeviceID, gain: 0.0)
    }
    
    func unmuteMicrophone() {
        setInputGain(for: selectedDeviceID, gain: unmuteGain)
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

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuView()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusBarItem: NSStatusItem!
    var menuItem: NSMenuItem!
    @ObservedObject var contentViewModel = ContentViewModel()
    static var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "micmute"
    
        let menu = NSMenu()
        menu.delegate = self

        menuItem = NSMenuItem()
        menuView()
        menu.addItem(menuItem)

        statusBarItem.menu = menu
    }
    
    func updateSelectedDevice(to deviceID: AudioDeviceID) {
        contentViewModel.selectedDeviceID = deviceID
        contentViewModel.loadInputGain(for: deviceID)
        changeDefaultInputDevice(to: deviceID)
        contentViewModel.loadAudioDevices()
    }
    
    func openMenu() {
        contentViewModel.loadAudioDevices()
        contentViewModel.setDefaultSystemInputDevice()
        contentViewModel.registerDeviceChangeListener()
        contentViewModel.startAutoRefresh()
    }
    
    func closeMenu() {
        contentViewModel.unregisterDeviceChangeListener()
        contentViewModel.stopAutoRefresh()
    }

    @objc func menuView() {
        let volumeView = NSHostingView(rootView: MainMenuView(
            unmuteGain: $contentViewModel.unmuteGain,
            selectedDeviceID: $contentViewModel.selectedDeviceID,
            availableDevices: $contentViewModel.availableDevices,
            onDeviceSelected: { [weak self] deviceID in self?.updateSelectedDevice(to: deviceID) },
            onAppear: { [weak self ] in self?.openMenu() },
            onDisappear: { [weak self ] in self?.closeMenu() }
        ))
        volumeView.translatesAutoresizingMaskIntoConstraints = false

        let tempView = NSView()
        tempView.addSubview(volumeView)
        volumeView.layout()
        let fittingSize = volumeView.intrinsicContentSize
        volumeView.removeFromSuperview()

        volumeView.frame = NSRect(x: 0, y: 0, width: 300, height: fittingSize.height)
        menuItem.view = volumeView
    }

    @objc func showSettingsWindow() {
        // todo settings window
        AppDelegate.settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("AppDelegate deinitialized")
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == AppDelegate.settingsWindow {
            window.contentView = nil
            AppDelegate.settingsWindow = nil
        }
    }
}

private struct DeviceEntry: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
}

struct MainMenuView: View {
    @Binding var unmuteGain: CGFloat
    @Binding var selectedDeviceID: UInt32
    @Binding var availableDevices: [AudioDeviceID: String]
    var onDeviceSelected: (AudioDeviceID) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    private var deviceEntries: [DeviceEntry] {
        print(availableDevices)
        print(availableDevices.sorted { $0.key < $1.key }.map { DeviceEntry(id: $0.key, name: $0.value) })
        return availableDevices.sorted { $0.key < $1.key }.map { DeviceEntry(id: $0.key, name: $0.value) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                MenuSection("Volume after unmute", divider: false)
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
                
                MenuSlider(
                    value: $unmuteGain,
                    image: Image(systemName: "speaker.wave.2.fill")
                ).padding(.horizontal, 12)
            }
        
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                MenuSection("Available devices", divider: false)
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(deviceEntries) { device in
                        MenuToggle(
                            isOn: .constant(device.id == selectedDeviceID),
                            image: Image(systemName: device.name.lowercased().contains("macbook") ? "laptopcomputer" : "mic.fill")
                        ) {
                            Text(device.name)
                        } onClick: { _ in
                            onDeviceSelected(device.id)
                        }
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            MenuCommand("Micmute settings...") {
                
            }
            
        }
        .padding(.horizontal, 1)
        .onAppear {
            onAppear()
        }
        .onDisappear {
            onDisappear()
        }
    }
}

let deviceChangeListener: AudioObjectPropertyListenerProc = { _, _, _, _ in
    DispatchQueue.main.async {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.contentViewModel.loadAudioDevices()
            appDelegate.contentViewModel.setDefaultSystemInputDevice()
            appDelegate.menuView()
            NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        }
    }
    return noErr
}

@main
struct MicmuteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
}

@MainActor
func showStandardAboutWindow() {
    NSApp.sendAction(
        #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        to: nil,
        from: nil
    )
}

@MainActor
func quit() {
    NSApp.terminate(nil)
}
