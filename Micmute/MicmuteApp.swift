//
//  MicmuteApp.swift
//  Micmute
//
//  Created by rokartur on 23/12/23.
//

import SwiftUI
import KeyboardShortcuts
import SettingsAccess

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("isMute") var isMute: Bool = false

    var appearanceObservation: NSObjectProtocol?
    var showNotification = false
    var menuBarSetup: MenuBarSetup!
    static private(set) var instance: AppDelegate!
    lazy var statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var micMute: NSImage = getMicMuteImage()
    var micUnmute: NSImage = getMicUnmuteImage()
    
    override init() {
        super.init()
        KeyboardShortcuts.onKeyUp(for: .toggleMuteShortcut) { [self] in
            self.toggleMute()
        }
        menuBarSetup = MenuBarSetup(statusBarMenu: NSMenu(), statusBarItem: statusBarItem, isMute: isMute, micMute: micMute, micUnmute: micUnmute)
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

        let muteNotificationWindowController = MuteNotificationWindowController(isMute: isMute)
        muteNotificationWindowController.showWindow(nil)
    }
    
    @objc func handleWallpaperChange() {
        micMute = getMicMuteImage()
        micUnmute = getMicUnmuteImage()
        statusBarItem.button?.image = isMute ? micMute : micUnmute
    }
    
    @objc public func clickMenuBar(_ sender: AnyObject?) {
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
        Settings {
            SettingsView()
        }
    }
}
