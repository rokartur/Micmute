import SwiftUI
import AppKit
import Carbon.HIToolbox
import QuartzCore

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
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 9
    private let shortcutFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
    private let placeholderFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    var placeholder: String = "Record Shortcut" {
        didSet { updateTitle() }
    }

    var shortcut: Shortcut? {
        didSet {
            updateTitle()
            updateImage()
        }
    }

    var onShortcutChange: ((Shortcut?) -> Void)?

    private var isRecording = false {
        didSet {
            updateAppearance(animated: true)
            if isRecording {
                updateTitle()
                updateImage()
            } else {
                updateTitle()
                updateImage()
            }
        }
    }
    private var isHovered = false {
        didSet { updateAppearance(animated: true) }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .regularSquare
        isBordered = false
        font = shortcutFont
        focusRingType = .default
        target = self
        action = #selector(toggleRecording)
        setButtonType(.momentaryPushIn)
        imagePosition = .imageLeading
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        updateAppearance(animated: false)
        updateImage()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isEnabled: Bool {
        didSet { updateAppearance(animated: true) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
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
            onShortcutChange?(nil)
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

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += horizontalPadding * 2
        size.height += verticalPadding * 2
        return size
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
    }

    private func endRecording() {
        isRecording = false
        updateTitle()
    }

    private func updateAppearance(animated: Bool = true) {
        guard let layer else { return }
        wantsLayer = true

        let accent = NSColor.controlAccentColor
        let baseBackground: NSColor
        let border: NSColor
        let shadowOpacity: Float

        if !isEnabled {
            baseBackground = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
            border = NSColor.separatorColor.withAlphaComponent(0.4)
            shadowOpacity = 0
        } else if isRecording {
            baseBackground = accent.withAlphaComponent(0.25)
            border = accent.withAlphaComponent(0.9)
            shadowOpacity = 0.35
        } else if isHovered {
            baseBackground = accent.withAlphaComponent(0.14)
            border = accent.withAlphaComponent(0.45)
            shadowOpacity = 0.28
        } else {
            baseBackground = NSColor.windowBackgroundColor.withAlphaComponent(0.65)
            border = NSColor.separatorColor.withAlphaComponent(0.35)
            shadowOpacity = 0.18
        }

        let duration: CFTimeInterval = animated ? 0.18 : 0

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        layer.backgroundColor = baseBackground.cgColor
        layer.borderColor = border.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 12
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.withAlphaComponent(0.45).cgColor
        layer.shadowOpacity = shadowOpacity
        layer.shadowRadius = isRecording ? 8 : (isHovered ? 6 : 4)
        layer.shadowOffset = CGSize(width: 0, height: -1.5)

        CATransaction.commit()

        let tint = isEnabled ? (isRecording ? accent : NSColor.labelColor) : NSColor.secondaryLabelColor

        if animated, window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().contentTintColor = tint
            }
        } else {
            contentTintColor = tint
        }

        updateTitle()
    }

    private func updateTitle() {
        if isRecording {
            applyAttributedTitle("Recording…", color: NSColor.controlAccentColor)
            return
        }

        if let shortcut {
            applyAttributedTitle(shortcut.displayString, color: NSColor.labelColor, font: shortcutFont, kern: 2.0)
        } else {
            applyAttributedTitle(placeholder, color: NSColor.secondaryLabelColor, font: placeholderFont)
        }
    }

    private func applyAttributedTitle(_ string: String, color: NSColor, font: NSFont = NSFont.systemFont(ofSize: 13, weight: .semibold), kern: CGFloat? = nil) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: font,
            .paragraphStyle: paragraph
        ]

        let attributed = NSMutableAttributedString(string: string, attributes: attributes)

        if let kern, attributed.length > 1 {
            attributed.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: attributed.length - 1))
        }

        attributedTitle = attributed
        invalidateIntrinsicContentSize()
    }

    private func updateImage() {
        guard let symbol = NSImage(systemSymbolName: imageSymbolName(), accessibilityDescription: nil) else {
            image = nil
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        image = symbol.withSymbolConfiguration(configuration)
    }

    private func imageSymbolName() -> String {
        if isRecording {
            return "record.circle.fill"
        }

        if shortcut != nil {
            return "keyboard"
        }

        return "plus.circle"
    }
}
