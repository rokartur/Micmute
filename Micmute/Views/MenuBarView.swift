//
//  MenuBarView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import SettingsAccess

struct MenuBarView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Text("Click icon with left mouse button\n or use shortcut to mute/unmute")
                .foregroundStyle(colorScheme == .dark ? Color.gray : Color.black)

            HStack(spacing: 148) {
                Button(action: {
                    NSApp.hide(nil)
                    let settingsWindow = NSApp.windows.first { $0.title == "Settings" }
                    if let window = settingsWindow, !window.isKeyWindow {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        try? openSettings()
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    Image(systemName: "gearshape")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .resizable()
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

class MenuBarSetup: NSObject {
    var statusBarMenu: NSMenu!
    var statusBarItem: NSStatusItem!
    var isMute: Bool!
    var micMute: NSImage!
    var micUnmute: NSImage!
    
    init(statusBarMenu: NSMenu, statusBarItem: NSStatusItem, isMute: Bool, micMute: NSImage, micUnmute: NSImage) {
        self.statusBarMenu = statusBarMenu
        self.statusBarItem = statusBarItem
        self.isMute = isMute
        self.micMute = micMute
        self.micUnmute = micUnmute
    }

    func setupMenuBar() {
        statusBarMenu = NSMenu()
        let menu = MenuBarView().openSettingsAccess()
        let menuView = NSHostingController(rootView: menu)
        menuView.view.frame.size = CGSize(width: 250, height: 96)
        let menuItem = NSMenuItem()
        menuItem.view = menuView.view
        statusBarMenu.addItem(menuItem)

        if let statusBarItemButton = statusBarItem.button {
            statusBarItemButton.image = isMute ? micMute : micUnmute
            statusBarItemButton.imagePosition = .imageLeading
            statusBarItemButton.action = #selector(AppDelegate.clickMenuBar)
            statusBarItemButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
}
