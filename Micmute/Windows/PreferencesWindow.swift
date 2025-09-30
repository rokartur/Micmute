//
//  PreferencesWindow.swift
//  Micmute
//
//  Created by artur on 09/02/2025.
//

import Foundation
import AppKit

class PreferencesWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Settings"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
    }
}
