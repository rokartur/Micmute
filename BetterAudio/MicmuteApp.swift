import SwiftUI
import CoreAudio
import CoreAudioKit
import AppKit

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let shortcutPreferences: ShortcutPreferences
    @ObservedObject var contentViewModel: ContentViewModel
    let settingsUpdaterModel: SettingsUpdaterModel
    var statusBarItem: NSStatusItem!

    private var panel: MenuPanel?
    private var outsideGlobalMonitor: Any?
    private var outsideLocalMonitor: Any?

    private var preferencesWindow: PreferencesWindow!
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()

    private let refreshInterval: TimeInterval = 1.0
    private var refreshTimer: Timer?
    
    private let panelInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    private let panelCornerRadius: CGFloat = 10
    
    override init() {
        let shortcutPreferences = ShortcutPreferences()
        self.shortcutPreferences = shortcutPreferences
        self.contentViewModel = ContentViewModel(shortcutPreferences: shortcutPreferences)
        self.settingsUpdaterModel = SettingsUpdaterModel(owner: "rokartur", repository: "BetterAudio")
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

        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusBarImage),
           name: NSNotification.Name("MuteStateChanged"),
           object: nil)
    }

    private func buildPanelController() -> NSHostingController<MainMenuView> {
        let root = MainMenuView(
            unmuteGain: $contentViewModel.unmuteGain,
            selectedDeviceID: $contentViewModel.selectedDeviceID,
            availableDevices: $contentViewModel.availableDevices,
            availableOutputDevices: $contentViewModel.availableOutputDevices,
            selectedOutputDeviceID: $contentViewModel.selectedOutputDeviceID,
            outputVolume: $contentViewModel.outputVolume,
            onDeviceSelected: { [weak self] deviceID in self?.updateSelectedDevice(to: deviceID) },
            onOutputDeviceSelected: { [weak self] deviceID in self?.updateSelectedOutputDevice(to: deviceID) },
            onOutputVolumeChange: { [weak self] newVolume in
                self?.contentViewModel.outputVolume = newVolume
            },
            onSliderEditingChanged: { [weak self] isEditing in
                guard let self else { return }
                if isEditing {
                    self.stopAutoRefresh()
                } else {
                    self.startAutoRefresh()
                }
            },
            onAppear: { [weak self] in self?.openMenu() },
            onDisappear: { [weak self] in self?.closeMenu() }
        )

        let hosting = NSHostingController(rootView: root)
        return hosting
    }

    private func desiredPanelSize(for hosting: NSHostingController<MainMenuView>) -> NSSize {
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        let width = MainMenuView.preferredWidth + panelInsets.left + panelInsets.right
        let height = max(1, fitting.height) + panelInsets.top + panelInsets.bottom
        return NSSize(width: width, height: height)
    }

    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let button = statusBarItem.button,
              let window = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)

        var x = buttonRectOnScreen.midX - size.width / 2
        var y = buttonRectOnScreen.minY - size.height - 6

        let screen = NSScreen.screens.first(where: { NSMaxX($0.visibleFrame) >= buttonRectOnScreen.midX && NSMinX($0.visibleFrame) <= buttonRectOnScreen.midX }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main!.visibleFrame

        if x < visible.minX { x = visible.minX + 4 }
        if x + size.width > visible.maxX { x = visible.maxX - size.width - 4 }
        if y < visible.minY { y = buttonRectOnScreen.maxY + 6 }

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func showPanel() {
        let hosting = buildPanelController()
        let size = desiredPanelSize(for: hosting)

        let panel = MenuPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.delegate = self

        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 12.0, *) {
            effectView.material = .menu
        } else {
            effectView.material = .popover
        }
        effectView.state = .active
        effectView.blendingMode = .withinWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = panelCornerRadius
        effectView.layer?.masksToBounds = true

        let containerVC = NSViewController()
        containerVC.view = effectView
        containerVC.addChild(hosting)

        let contentView = hosting.view
        contentView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = effectView
        panel.contentViewController = containerVC

        effectView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: panelInsets.left),
            contentView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -panelInsets.right),
            contentView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: panelInsets.top),
            contentView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -panelInsets.bottom),
        ])

        positionPanel(panel, size: size)

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        installOutsideClickMonitors(for: panel)

        self.panel = panel
    }

    private func closePanel() {
        removeOutsideClickMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    private func installOutsideClickMonitors(for panel: NSPanel) {
        removeOutsideClickMonitors()

        outsideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            if self.shouldClosePanel(on: event, panel: panel) {
                self.closePanel()
                return nil
            }
            return event
        }

        outsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel else { return }
            if self.shouldClosePanel(on: event, panel: panel) {
                self.closePanel()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let global = outsideGlobalMonitor {
            NSEvent.removeMonitor(global)
            outsideGlobalMonitor = nil
        }
        if let local = outsideLocalMonitor {
            NSEvent.removeMonitor(local)
            outsideLocalMonitor = nil
        }
    }

    private func shouldClosePanel(on event: NSEvent, panel: NSPanel) -> Bool {
        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) { return false }
        if let button = statusBarItem.button,
           let window = button.window {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonRectOnScreen = window.convertToScreen(buttonRectInWindow)
            if buttonRectOnScreen.contains(location) {
                return false
            }
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        // Optional auto-close
    }

    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            if panel != nil {
                closePanel()
            } else {
                showPanel()
            }
        } else if event.type == .leftMouseUp {
            if contentViewModel.menuBehaviorOnClick == .mute {
                closePanel()
                contentViewModel.toggleMute(deviceID: contentViewModel.selectedDeviceID)
                updateStatusBarImage()
            } else if contentViewModel.menuBehaviorOnClick == .menu {
                if panel != nil {
                    closePanel()
                } else {
                    showPanel()
                }
            }
        }
    }

    @objc func updateStatusBarImage() {
        let isMuted = contentViewModel.isMuted
        statusBarItem.button?.image = isMuted ? micMute : micUnmute
    }

    @objc func showPreferences(_ sender: AnyObject?) {
        closePanel()

        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
            let preferencesRoot = PreferencesView()
                .environmentObject(settingsUpdaterModel)
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
    }

    func updateSelectedOutputDevice(to deviceID: AudioDeviceID) {
        contentViewModel.selectedOutputDeviceID = deviceID
        contentViewModel.changeDefaultOutputDevice(to: deviceID)
        contentViewModel.refreshOutputVolumeState()
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
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.contentViewModel.loadAudioDevices()
            }
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeOutsideClickMonitors()
        contentViewModel.tearDown()
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
            NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        }
    }
    return noErr
}

@main
struct BetterAudioApp: App {
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
