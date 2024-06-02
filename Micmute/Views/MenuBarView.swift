//
//  MenuBarView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import Foundation
import AppKit
import SwiftUI
import SettingsAccess
import Sparkle

struct MenuBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Click icon with left mouse button\n or use shortcut to mute/unmute")
            .foregroundStyle(colorScheme == .dark ? Color.gray : Color.black)
    }
}

class MenuBarSetup: NSObject {
    @Environment(\.openSettings) var openSettings
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    
    var statusBarMenu: NSMenu!
    var statusBarItem: NSStatusItem!
    var isMute: Bool!
    var micMute: NSImage!
    var micUnmute: NSImage!
    private let updater: SPUUpdater

    init(statusBarMenu: NSMenu, statusBarItem: NSStatusItem, isMute: Bool, micMute: NSImage, micUnmute: NSImage, updater: SPUUpdater) {
        self.statusBarMenu = statusBarMenu
        self.statusBarItem = statusBarItem
        self.isMute = isMute
        self.micMute = micMute
        self.micUnmute = micUnmute
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    func setupMenuBar() {
        statusBarMenu = NSMenu()
        let menu = MenuBarView().openSettingsAccess()
        let menuView = NSHostingController(rootView: menu)
        menuView.view.frame.size = CGSize(width: 248, height: 48)
        let menuItem = NSMenuItem()
        menuItem.view = menuView.view
        statusBarMenu.addItem(menuItem)
        
        statusBarMenu.addItem(.separator())

        let aboutMenuItem = NSMenuItem(title: "About Micmute...", action: #selector(Self.about), keyEquivalent: "")
        aboutMenuItem.target = self
        statusBarMenu.addItem(aboutMenuItem)
        
        let updatesMenuItem = NSMenuItem(title: "Check for Updates...", action: #selector(Self.updates), keyEquivalent: "")
        updatesMenuItem.target = self
        statusBarMenu.addItem(updatesMenuItem)
        
        statusBarMenu.addItem(.separator())
        
        let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(Self.settings), keyEquivalent: ",")
        settingsMenuItem.target = self
        statusBarMenu.addItem(settingsMenuItem)
        
        statusBarMenu.addItem(.separator())
        
        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(Self.quit), keyEquivalent: "")
        quitMenuItem.target = self
        statusBarMenu.addItem(quitMenuItem)
        
        if let statusBarItemButton = statusBarItem.button {
            statusBarItemButton.image = isMute ? micMute : micUnmute
            statusBarItemButton.imagePosition = .imageLeading
            statusBarItemButton.action = #selector(AppDelegate.openMenuBar)
            statusBarItemButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func about(_ sender: NSMenuItem) {
        let settingsWindow = NSApp.windows.first { $0.title == "About" || $0.title == "General" || $0.title == "Appearance" || $0.title == "Animation" }
        if settingsWindow != nil {
            NSApp.activate(ignoringOtherApps: true)
            UserDefaults.standard.set("About", forKey: "selectedTab")
        } else {
            try? openSettings()
            NSApp.activate(ignoringOtherApps: true)
            UserDefaults.standard.set("About", forKey: "selectedTab")
        }
    }

    @objc func updates(_ sender: NSMenuItem) {
        updater.checkForUpdates()
    }

    @objc func settings(_ sender: NSMenuItem) {
        try? openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
