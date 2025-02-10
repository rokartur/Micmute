import SwiftUI
import CoreAudio
import CoreAudioKit
import MacControlCenterUI

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuView()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    @ObservedObject var contentViewModel = ContentViewModel()
    private var statusBarItem: NSStatusItem!
    private var menuItem: NSMenuItem!
    private var preferencesWindow: PreferencesWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusBar()
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
    
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "micmute"
    
        let menu = NSMenu()
        menu.delegate = self

        menuItem = NSMenuItem()
        menuView()
        menu.addItem(menuItem)

        statusBarItem.menu = menu
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

    @objc func showPreferences(_ sender: AnyObject?) {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
            let preferencesView = PreferencesView(parentWindow: preferencesWindow) // Create the SwiftUI view
            let hostedPrefView = NSHostingView(rootView: preferencesView)
            preferencesWindow.contentView = hostedPrefView

            // Calculate the fitting size for the content
            let fittingSize = hostedPrefView.intrinsicContentSize
            
            // Set the window's content size to fit the content
            preferencesWindow.setContentSize(fittingSize)
        }
        
        preferencesWindow.center()
        preferencesWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
