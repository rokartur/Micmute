import SwiftUI
import CoreAudio
import CoreAudioKit
import AppKit


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let shortcutPreferences: ShortcutPreferences
    @ObservedObject var contentViewModel: ContentViewModel
    let perAppVolumeManager = PerAppAudioVolumeManager()
    let settingsUpdaterModel: SettingsUpdaterModel
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var statusBarMenuItem: NSMenuItem!

    private var preferencesWindow: PreferencesWindow!
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()

    private let refreshInterval: TimeInterval = 1.0
    @State private var refreshTimer: Timer?
    
    override init() {
        let shortcutPreferences = ShortcutPreferences()
        self.shortcutPreferences = shortcutPreferences
        self.contentViewModel = ContentViewModel(shortcutPreferences: shortcutPreferences)
        self.settingsUpdaterModel = SettingsUpdaterModel(owner: "rokartur", repository: "Micmute")
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UpdaterSupport.ensureDownloadDirectoryExists()
        settingsUpdaterModel.bootstrapOnLaunch()
        
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        let isMuted = contentViewModel.isMuted
     
        statusBarItem.button?.image = isMuted ? micMute : micUnmute
        statusBarItem.button?.action = #selector(self.statusBarButtonClicked(sender:))
        statusBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusBarMenu = NSMenu()
        statusBarMenu.delegate = self
        statusBarMenuItem = NSMenuItem()
        menuView()
        statusBarMenu.addItem(statusBarMenuItem)
        
        if contentViewModel.menuBehaviorOnClick == .menu {
            statusBarItem.menu = statusBarMenu
        } else {
            statusBarItem.menu = nil
        }
    
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusBarImage),
           name: NSNotification.Name("MuteStateChanged"),
           object: nil)
    }

    @objc func menuView() {
        let volumeView = NSHostingView(rootView: MainMenuView(
            unmuteGain: $contentViewModel.unmuteGain,
            selectedDeviceID: $contentViewModel.selectedDeviceID,
            availableDevices: $contentViewModel.availableDevices,
            availableOutputDevices: $contentViewModel.availableOutputDevices,
            selectedOutputDeviceID: $contentViewModel.selectedOutputDeviceID,
            outputVolume: $contentViewModel.outputVolume,
            onDeviceSelected: { [weak self] deviceID in self?.updateSelectedDevice(to: deviceID) },
            onOutputDeviceSelected: { [weak self] deviceID in self?.updateSelectedOutputDevice(to: deviceID) },
            onOutputVolumeChange: { [weak self] newVolume in
                guard let self else { return }
                self.contentViewModel.setOutputVolume(for: self.contentViewModel.selectedOutputDeviceID, volume: newVolume)
            },
            onAppear: { [weak self ] in self?.openMenu() },
            onDisappear: { [weak self ] in self?.closeMenu() }
        )
        .environmentObject(perAppVolumeManager))
        volumeView.translatesAutoresizingMaskIntoConstraints = false

        let targetWidth = MainMenuView.preferredWidth
        let tempView = NSView()
        tempView.addSubview(volumeView)
        volumeView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 10)
        volumeView.layoutSubtreeIfNeeded()
        let fittingSize = volumeView.fittingSize
        volumeView.removeFromSuperview()

        volumeView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: fittingSize.height)
        statusBarMenuItem.view = volumeView
    }

    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            statusBarItem.menu = statusBarMenu
            statusBarItem.button?.performClick(nil)
        } else if event.type == .leftMouseUp {
            if contentViewModel.menuBehaviorOnClick == .mute {
                statusBarItem.menu = nil
                contentViewModel.toggleMute(deviceID: contentViewModel.selectedDeviceID)
                updateStatusBarImage()
            } else if contentViewModel.menuBehaviorOnClick == .menu {
                statusBarItem.menu = statusBarMenu
                statusBarItem.button?.performClick(nil)
            }
        }
    }

    @objc func updateStatusBarImage() {
        let isMuted = contentViewModel.isMuted
        statusBarItem.button?.image = isMuted ? micMute : micUnmute
    }
    
    @objc func menuDidClose(_ menu: NSMenu) {
        statusBarItem.menu = nil
    }

    @objc func showPreferences(_ sender: AnyObject?) {
        statusBarMenu.cancelTracking()
        statusBarItem.menu = nil

        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
            let preferencesRoot = PreferencesView()
                .environmentObject(settingsUpdaterModel)
                .environmentObject(perAppVolumeManager)
                .environmentObject(shortcutPreferences)
                .environmentObject(contentViewModel)
            let hostedPrefView = NSHostingView(rootView: preferencesRoot)
            preferencesWindow.contentView = hostedPrefView
            preferencesWindow.setContentSize(PreferencesWindow.defaultSize)
        }

        guard let preferencesWindow else { return }

        let shouldCenter = !preferencesWindow.isVisible

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak preferencesWindow] in
            guard let self, let preferencesWindow else { return }

            self.settingsUpdaterModel.refreshIfNeeded()
            NSApplication.shared.activate(ignoringOtherApps: true)

            if shouldCenter {
                preferencesWindow.center()
            }

            preferencesWindow.makeKeyAndOrderFront(nil)
        }
    }

    func updateSelectedDevice(to deviceID: AudioDeviceID) {
        contentViewModel.selectedDeviceID = deviceID
        contentViewModel.loadInputGain(for: deviceID)
        contentViewModel.changeDefaultInputDevice(to: deviceID)
        contentViewModel.loadAudioDevices()
    }

    func updateSelectedOutputDevice(to deviceID: AudioDeviceID) {
        contentViewModel.selectedOutputDeviceID = deviceID
        contentViewModel.changeDefaultOutputDevice(to: deviceID)
        contentViewModel.refreshOutputVolumeState()
        contentViewModel.loadAudioDevices()
    }
    
    func openMenu() {
        contentViewModel.loadAudioDevices()
        contentViewModel.syncSelectedInputDeviceWithSystemDefault()
        contentViewModel.setDefaultSystemOutputDevice()
        contentViewModel.registerDeviceChangeListener()
        startAutoRefresh()
    }
    
    func closeMenu() {
        contentViewModel.unregisterDeviceChangeListener()
        stopAutoRefresh()
    }
    
    func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            self.contentViewModel.loadAudioDevices()
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        menuView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("AppDelegate deinitialized")
    }
}

let deviceChangeListener: AudioObjectPropertyListenerProc = { _, _, _, _ in
    Task { @MainActor in
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.contentViewModel.loadAudioDevices()
//             appDelegate.contentViewModel.setDefaultSystemInputDevice()
//             appDelegate.menuView()
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
        }.commands {
            CommandGroup(replacing: .appSettings) {
                Button("") {
                    appDelegate.showPreferences(nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
}
