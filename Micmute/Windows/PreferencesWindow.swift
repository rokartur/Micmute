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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .fullSizeContentView, .miniaturizable, .closable],
            backing: .buffered,
            defer: false)
        
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
    }
    
}
