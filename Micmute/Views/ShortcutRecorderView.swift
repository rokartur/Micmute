import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var isEnabled: Bool = true
    var placeholder: String = "Record Shortcut"

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.placeholder = placeholder
        button.isEnabled = isEnabled
        button.shortcut = shortcut
        button.onShortcutChange = { [weak coordinator = context.coordinator] newShortcut in
            coordinator?.updateShortcut(newShortcut)
        }
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.shortcut = shortcut
        nsView.isEnabled = isEnabled
        nsView.placeholder = placeholder
    }

    final class Coordinator {
        private var parent: ShortcutRecorderView

        init(_ parent: ShortcutRecorderView) {
            self.parent = parent
        }

        func updateShortcut(_ shortcut: Shortcut?) {
            parent.shortcut = shortcut
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var placeholder: String = "Record Shortcut" {
        didSet { updateTitle() }
    }

    var shortcut: Shortcut? {
        didSet { updateTitle() }
    }

    var onShortcutChange: ((Shortcut?) -> Void)?

    private var isRecording = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 13)
        focusRingType = .default
        target = self
        action = #selector(toggleRecording)
        setButtonType(.momentaryPushIn)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if Shortcut.isClearingKey(keyCode: UInt16(event.keyCode)) {
            onShortcutChange?(nil)
            endRecording()
            return
        }

        if event.keyCode == kVK_Escape {
            endRecording()
            return
        }

        guard let newShortcut = Shortcut(event: event) else {
            NSSound.beep()
            return
        }

        onShortcutChange?(newShortcut)
        endRecording()
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording {
            endRecording()
        }
    }

    @objc private func toggleRecording() {
        if isRecording {
            endRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
        title = "Recording…"
    }

    private func endRecording() {
        isRecording = false
        updateTitle()
    }

    private func updateAppearance() {
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        wantsLayer = true
        if isEnabled {
            layer?.backgroundColor = (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.windowBackgroundColor).cgColor
            layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        } else {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
        layer?.borderWidth = 1
        updateTitle()
    }

    private func updateTitle() {
        if isRecording {
            return
        }

        if let shortcut {
            title = shortcut.displayString
        } else {
            title = placeholder
        }
    }
}
