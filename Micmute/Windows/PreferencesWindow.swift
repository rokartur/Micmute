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

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        center()
        tabbingMode = .disallowed
    }
}
