import Foundation
import AppKit

final class PreferencesWindow: NSWindow {
    static let defaultSize = NSSize(width: 830, height: 630)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [
                .titled,
                .closable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        title = ""
        
        contentMinSize = Self.defaultSize
        contentMaxSize = Self.defaultSize

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        tabbingMode = .disallowed
        titlebarSeparatorStyle = .none

        center()
    }
}
