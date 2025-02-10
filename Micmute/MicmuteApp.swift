import SwiftUI
import CoreAudio
import CoreAudioKit
import MacControlCenterUI



func getMicMuteImage() -> NSImage {
    let isDarkMode = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let imageName = isDarkMode ? "mic.mute.dark" : "mic.mute.light"
    let image = NSImage(named: imageName)!
    let ratio = image.size.height / image.size.width
    image.size.height = 16
    image.size.width = 16 / ratio
    return image
}

func getMicUnmuteImage() -> NSImage {
    let isDarkMode = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let imageName = isDarkMode ? "mic.unmute.dark" : "mic.unmute.light"
    let image = NSImage(named: imageName)!
    let ratio = image.size.height / image.size.width
    image.size.height = 16
    image.size.width = 16 / ratio
    return image
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @ObservedObject var contentViewModel = ContentViewModel()
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var statusBarMenuItem: NSMenuItem!

    private var preferencesWindow: PreferencesWindow!
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let statusBar = NSStatusBar.system
        statusBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        
        statusBarItem.button?.title = "micmute"
        
        statusBarItem.button?.action = #selector(self.statusBarButtonClicked(sender:))
        statusBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        statusBarMenu = NSMenu(title: "Status Bar Menu")
        statusBarMenu.delegate = self
        statusBarMenuItem = NSMenuItem()
        menuView()
        statusBarMenu.addItem(statusBarMenuItem)
//        statusBarItem.statusBarMenu = statusBarMenu
        
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }
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
        
        switch event.type {
            case .rightMouseUp:
                statusBarItem.menu = statusBarMenu
                statusBarItem.button?.performClick(nil)
            case .leftMouseUp:
                if contentViewModel.menuBehaviorOnClick == .mute {
                    contentViewModel.toggleMute(deviceID: contentViewModel.selectedDeviceID)
                } else if contentViewModel.menuBehaviorOnClick == .menu {
                    statusBarItem.menu = statusBarMenu
                    statusBarItem.button?.performClick(nil)
                }
            default:
                return
        }
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
        contentViewModel.startAutoRefresh()
    }
    
    func closeMenu() {
        contentViewModel.unregisterDeviceChangeListener()
        contentViewModel.stopAutoRefresh()
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
