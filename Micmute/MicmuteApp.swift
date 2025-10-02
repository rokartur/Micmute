import SwiftUI
import CoreAudio
import CoreAudioKit
import Combine
import AlinFoundation
import AppKit


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let shortcutPreferences: ShortcutPreferences
    @ObservedObject var contentViewModel: ContentViewModel
    let perAppVolumeManager = PerAppAudioVolumeManager()
    let updater = Updater(owner: "rokartur", repo: "Micmute")
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!
    var statusBarMenuItem: NSMenuItem!

    private var preferencesWindow: PreferencesWindow!
    private var updaterWindow: NSWindow?
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()

    private let refreshInterval: TimeInterval = 1.0
    @State private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        let shortcutPreferences = ShortcutPreferences()
        self.shortcutPreferences = shortcutPreferences
        self.contentViewModel = ContentViewModel(shortcutPreferences: shortcutPreferences)
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UpdaterSupport.ensureDownloadDirectoryExists()

        // Observe updater sheet state and trigger windows when needed
        updater.$sheet
            .receive(on: RunLoop.main)
            .sink { [weak self] showSheet in
                guard let self else { return }
                if showSheet {
                    self.presentUpdaterWindow()
                } else {
                    self.closeUpdaterWindow()
                }
            }
            .store(in: &cancellables)

        // Initialize updater and check for updates
        updater.checkAndUpdateIfNeeded()
        
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
        .environmentObject(updater)
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
            let preferencesRoot = PreferencesView(parentWindow: preferencesWindow)
                .environmentObject(updater)
                .environmentObject(perAppVolumeManager)
                .environmentObject(shortcutPreferences)
            let hostedPrefView = NSHostingView(rootView: preferencesRoot)
            preferencesWindow.contentView = hostedPrefView
            let fittingSize = hostedPrefView.intrinsicContentSize
            preferencesWindow.setContentSize(fittingSize)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.preferencesWindow.center()
            self.preferencesWindow.makeKeyAndOrderFront(nil)
            self.preferencesWindow.makeKey()
        }
    }

    private func presentUpdaterWindow() {
        if updaterWindow == nil {
            let hostView = UpdateSheetHost(updater: updater) { [weak self] in
                guard let self else { return }
                updater.sheet = false
                closeUpdaterWindow()
            }

            let hostingController = NSHostingController(rootView: hostView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.alphaValue = 0.01
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.contentViewController = hostingController
            updaterWindow = window
        }

        guard let window = updaterWindow else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeUpdaterWindow() {
        updaterWindow?.close()
        updaterWindow = nil
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
        contentViewModel.setDefaultSystemInputDevice()
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

private struct UpdateSheetHost: View {
    @ObservedObject var updater: Updater
    var onDismiss: () -> Void
    @State private var showSheet = true

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .sheet(isPresented: $showSheet, onDismiss: onDismiss) {
                updater.getUpdateView()
                    .onAppear {
                        UpdaterSupport.ensureDownloadDirectoryExists()
                    }
            }
            .onAppear {
                showSheet = true
            }
            .onChange(of: updater.sheet, initial: false) { _, newValue in
                if showSheet != newValue {
                    showSheet = newValue
                }
            }
    }
}
