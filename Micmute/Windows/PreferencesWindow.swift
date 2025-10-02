//
//  PreferencesWindow.swift
//  Micmute
//
//  Created by artur on 09/02/2025.
//

import Foundation
import AppKit

final class PreferencesWindow: NSWindow {
    static let defaultSize = NSSize(width: 860, height: 605)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Settings"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        center()

        if let titlebarContainer = standardWindowButton(.closeButton)?.superview {
            titlebarContainer.wantsLayer = true
            titlebarContainer.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if let closeButton = standardWindowButton(.closeButton) {
            closeButton.isHidden = true
            closeButton.isEnabled = true
        }

        if let minimizeButton = standardWindowButton(.miniaturizeButton) {
            minimizeButton.isHidden = true
            minimizeButton.isEnabled = false
        }

        if let zoomButton = standardWindowButton(.zoomButton) {
            zoomButton.isHidden = true
            zoomButton.isEnabled = false
        }

        tabbingMode = .disallowed
    }
}
