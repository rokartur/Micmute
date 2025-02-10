import SwiftUI
import CoreAudio
import CoreAudioKit
import MacControlCenterUI
import Combine


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @ObservedObject var contentViewModel = ContentViewModel()
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var statusBarMenuItem: NSMenuItem!

    private var preferencesWindow: PreferencesWindow!
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()

    private let refreshInterval: TimeInterval = 1.0
    @State private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
        statusBarItem.menu = statusBarMenu
        
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
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
            let preferencesView = PreferencesView(parentWindow: preferencesWindow)
            let hostedPrefView = NSHostingView(rootView: preferencesView)
            preferencesWindow.contentView = hostedPrefView
            let fittingSize = hostedPrefView.intrinsicContentSize
            preferencesWindow.setContentSize(fittingSize)
        }
        
        preferencesWindow.center()
        preferencesWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func updateSelectedDevice(to deviceID: AudioDeviceID) {
        contentViewModel.selectedDeviceID = deviceID
        contentViewModel.loadInputGain(for: deviceID)
        contentViewModel.changeDefaultInputDevice(to: deviceID)
        contentViewModel.loadAudioDevices()
    }
    
    func openMenu() {
        contentViewModel.loadAudioDevices()
        contentViewModel.setDefaultSystemInputDevice()
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
            // appDelegate.contentViewModel.setDefaultSystemInputDevice()
            // appDelegate.menuView()
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
