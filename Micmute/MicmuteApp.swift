//
//  MicmuteApp.swift
//  Micmute
//
//  Created by rokartur on 23/12/23.
//

import SwiftUI
import KeyboardShortcuts
import SettingsAccess
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("isMute") var isMute: Bool = false
    @AppStorage("animationType") var animationType: String = "Fade"
    @AppStorage("animationDuration") var animationDuration: Double = 1.3
    @AppStorage("isNotificationEnabled") var isNotificationEnabled: Bool = true
    @AppStorage("displayOption") var displayOption: DisplayOption = .largeBoth
    @AppStorage("placement") var placement: Placement = .centerBottom
    @AppStorage("padding") var padding: Double = 70.0

    var notificationWindowController: NotificationWindowController?
    var appearanceObservation: NSObjectProtocol?
    var showNotification = false
    var menuBarSetup: MenuBarSetup!
    static private(set) var instance: AppDelegate!
    lazy var statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()
    lazy var updaterController: SPUStandardUpdaterController = {
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    override init() {
        super.init()
        KeyboardShortcuts.onKeyUp(for: .toggleMuteShortcut) { [self] in
            self.toggleMute()
        }
        menuBarSetup = MenuBarSetup(statusBarMenu: NSMenu(), statusBarItem: statusBarItem, isMute: isMute, micMute: micMute, micUnmute: micUnmute, updater: updaterController.updater)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleWallpaperChange), name: NSNotification.Name(rawValue: "AppleInterfaceThemeChangedNotification"), object: nil)
    }

    deinit {
        if let appearanceObservation = appearanceObservation {
            DistributedNotificationCenter.default().removeObserver(appearanceObservation)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarSetup.setupMenuBar()
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
        }
    }

    func toggleMute() {
        isMute.toggle()
        statusBarItem.button?.image = isMute ? micMute : micUnmute
        setDefaultInputVolumeDevice(isMute: isMute)

        if isNotificationEnabled {
            notificationWindowController?.close()
            notificationWindowController = NotificationWindowController(isMute: isMute, animationType: animationType, animationDuration: animationDuration, displayOption: displayOption, placement: placement, padding: padding)
            notificationWindowController?.showWindow(nil)
        }
    }
    
    @objc func handleWallpaperChange() {
        micMute = getMicMuteImage()
        micUnmute = getMicUnmuteImage()
        statusBarItem.button?.image = isMute ? micMute : micUnmute
    }
    
    @objc public func openMenuBar(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        
        switch event.type {
            case .rightMouseUp:
                statusBarItem.menu = menuBarSetup.statusBarMenu
                statusBarItem.button?.performClick(nil)
            case .leftMouseUp:
                toggleMute()
            default:
                return
        }

        statusBarItem.menu = nil
    }
}

@main
struct MicmuteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {}
        Settings {
            SettingsView()
        }
    }
}
