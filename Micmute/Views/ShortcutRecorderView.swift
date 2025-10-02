import SwiftUI
import AppKit
import Carbon.HIToolbox

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var isEnabled: Bool = true
    var placeholder: String = "Record Shortcut"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.placeholderText = placeholder
        field.shortcut = shortcut
        field.isEnabled = isEnabled
        field.onShortcutChange = { [weak coordinator = context.coordinator] newShortcut in
            coordinator?.updateShortcut(newShortcut)
        }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        context.coordinator.parent = self
        if nsView.shortcut != shortcut {
            nsView.shortcut = shortcut
        }
        nsView.isEnabled = isEnabled
        nsView.placeholderText = placeholder
    }

    final class Coordinator {
        var parent: ShortcutRecorderView
        weak var field: ShortcutRecorderField?

        init(parent: ShortcutRecorderView) {
            self.parent = parent
        }

        func updateShortcut(_ shortcut: Shortcut?) {
            parent.shortcut = shortcut
        }
    }
}

final class ShortcutRecorderField: NSSearchField, NSSearchFieldDelegate {
    var onShortcutChange: ((Shortcut?) -> Void)?
    var placeholderText: String = "Record Shortcut" {
        didSet { updatePlaceholder() }
    }
    var shortcut: Shortcut? {
        didSet {
            guard !isRecording else { return }
            updateTextFieldContents()
        }
    }

    private let minimumWidth: CGFloat = 130
    private let clearedShortcutDisplayText = "None"
    private var eventMonitor: LocalEventMonitor?
    private var cancelButtonCell: NSButtonCell?
    private var isRecording = false {
        didSet {
            updateAppearance()
            updatePlaceholder()
        }
    }
    private var previousShortcut: Shortcut?
    private var windowDidResignKeyObserver: NSObjectProtocol?
    private var windowWillCloseObserver: NSObjectProtocol?
    private var hasUserInitiatedFocus = false

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
        delegate = self
        alignment = .center
        focusRingType = .default
        placeholderString = placeholderText
        wantsLayer = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        cancelButtonCell = (cell as? NSSearchFieldCell)?.cancelButtonCell
        showsCancelButton = false
        updateAppearance()
        updateTextFieldContents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        eventMonitor?.stop()
        removeWindowObservers()
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width = max(size.width, minimumWidth)
        return size
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
        hasUserInitiatedFocus = false
    }

    override func becomeFirstResponder() -> Bool {
        guard isEnabled else { return false }
        if !hasUserInitiatedFocus {
            if let event = NSApp.currentEvent {
                switch event.type {
                case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown:
                    hasUserInitiatedFocus = true
                default:
                    break
                }
            }
        }

        if !hasUserInitiatedFocus {
            return false
        }

        let shouldBecome = super.becomeFirstResponder()
        if shouldBecome {
            beginRecording()
        }
        return shouldBecome
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            endRecording(commitChanges: false)
        }
        return super.resignFirstResponder()
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording {
            endRecording(commitChanges: false)
        } else {
            applyShortcut(nil, notify: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        hasUserInitiatedFocus = true
        super.mouseDown(with: event)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isRecording else { return }
        if stringValue.isEmpty, shortcut != nil {
            applyShortcut(nil, notify: true)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if isRecording {
            endRecording(commitChanges: true)
        }
    }

    // MARK: - Recording

    private func beginRecording() {
        guard !isRecording else { return }
        previousShortcut = shortcut
        isRecording = true
        hasUserInitiatedFocus = true
        showsCancelButton = false
        hideCaret()
        stringValue = ""
        NotificationCenter.default.post(name: .shortcutRecorderActiveDidChange, object: self, userInfo: ["isActive": true])
        startEventMonitor()
    }

    private func endRecording(commitChanges: Bool) {
        guard isRecording else { return }
        isRecording = false
        eventMonitor?.stop()
        eventMonitor = nil
        restoreCaret()
        if !commitChanges {
            shortcut = previousShortcut
        }
        updateTextFieldContents()
        previousShortcut = nil
        NotificationCenter.default.post(name: .shortcutRecorderActiveDidChange, object: self, userInfo: ["isActive": false])
    }

    private func startEventMonitor() {
        eventMonitor?.stop()
        eventMonitor = LocalEventMonitor(events: [.keyDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
            guard let self else { return event }

            switch event.type {
            case .leftMouseUp, .rightMouseUp:
                let point = self.convert(event.locationInWindow, from: nil)
                let margin: CGFloat = 3
                if !self.bounds.insetBy(dx: -margin, dy: -margin).contains(point) {
                    self.endRecording(commitChanges: false)
                    return event
                }
                return nil
            case .keyDown:
                return self.handleKeyDown(event)
            default:
                return event
            }
        }.start()
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let keyCode = UInt16(event.keyCode)

        if keyCode == kVK_Tab {
            endRecording(commitChanges: false)
            return event
        }

        if keyCode == kVK_Escape {
            applyShortcut(nil, notify: true)
            endRecording(commitChanges: true)
            window?.makeFirstResponder(nil)
            return nil
        }

        if Shortcut.isClearingKey(keyCode: keyCode) {
            applyShortcut(nil, notify: true)
            endRecording(commitChanges: true)
            return nil
        }

        let modifiers = event.modifierFlags.intersection(.permittedShortcutFlags)
        if !allowsShortcutWithoutModifiers(keyCode: keyCode, modifiers: modifiers) {
            NSSound.beep()
            return nil
        }

        guard let newShortcut = Shortcut(event: event) else {
            NSSound.beep()
            return nil
        }

        applyShortcut(newShortcut, notify: true)
        endRecording(commitChanges: true)
        return nil
    }

    private func allowsShortcutWithoutModifiers(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let permittingKey: Bool = {
            switch keyCode {
            case UInt16(kVK_Return),
                 UInt16(kVK_ANSI_KeypadEnter),
                 UInt16(kVK_Space),
                 UInt16(kVK_Tab),
                 UInt16(kVK_Delete),
                 UInt16(kVK_ForwardDelete),
                 UInt16(kVK_Escape),
                 UInt16(kVK_CapsLock),
                 UInt16(kVK_Help),
                 UInt16(kVK_Home),
                 UInt16(kVK_End),
                 UInt16(kVK_PageUp),
                 UInt16(kVK_PageDown),
                 UInt16(kVK_LeftArrow),
                 UInt16(kVK_RightArrow),
                 UInt16(kVK_UpArrow),
                 UInt16(kVK_DownArrow):
                return true
            case UInt16(kVK_F1),
                 UInt16(kVK_F2),
                 UInt16(kVK_F3),
                 UInt16(kVK_F4),
                 UInt16(kVK_F5),
                 UInt16(kVK_F6),
                 UInt16(kVK_F7),
                 UInt16(kVK_F8),
                 UInt16(kVK_F9),
                 UInt16(kVK_F10),
                 UInt16(kVK_F11),
                 UInt16(kVK_F12),
                 UInt16(kVK_F13),
                 UInt16(kVK_F14),
                 UInt16(kVK_F15),
                 UInt16(kVK_F16),
                 UInt16(kVK_F17),
                 UInt16(kVK_F18),
                 UInt16(kVK_F19),
                 UInt16(kVK_F20):
                return true
            default:
                return false
            }
        }()

        if modifiers.isEmpty {
            return permittingKey
        }

        let disallowedOnlyShiftOrFunction = modifiers.subtracting([.shift, .function]).isEmpty
        return permittingKey || !disallowedOnlyShiftOrFunction
    }

    private func applyShortcut(_ newShortcut: Shortcut?, notify: Bool) {
        shortcut = newShortcut
        if notify {
            onShortcutChange?(newShortcut)
        }
        if isRecording {
            stringValue = newShortcut?.displayString ?? clearedShortcutDisplayText
        } else {
            updateTextFieldContents()
        }
    }

    private func updateTextFieldContents() {
        if let shortcut {
            stringValue = shortcut.displayString
            showsCancelButton = true
        } else {
            stringValue = clearedShortcutDisplayText
            showsCancelButton = false
        }
    }

    private func updatePlaceholder() {
        placeholderString = isRecording ? "Press shortcut" : placeholderText
    }

    private func updateAppearance() {
        wantsLayer = true
        guard let layer else { return }
        let borderColor: NSColor
        if !isEnabled {
            borderColor = NSColor.separatorColor.withAlphaComponent(0.25)
        } else if isRecording {
            borderColor = NSColor.controlAccentColor
        } else {
            borderColor = NSColor.separatorColor.withAlphaComponent(0.45)
        }

        let background = isEnabled ? NSColor.controlBackgroundColor : NSColor.controlBackgroundColor.withAlphaComponent(0.6)

        layer.cornerRadius = 6
        layer.borderWidth = isRecording ? 1.5 : 1
        layer.borderColor = borderColor.cgColor
        layer.backgroundColor = background.cgColor
        layer.shadowOpacity = 0
        alphaValue = isEnabled ? 1 : 0.6
    }

    // MARK: - Window observers

    private func installWindowObservers() {
        removeWindowObservers()
        guard let window else { return }
        windowDidResignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: nil) { [weak self] _ in
            self?.endRecording(commitChanges: false)
        }
        windowWillCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
            self?.endRecording(commitChanges: false)
        }
    }

    private func removeWindowObservers() {
        if let observer = windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = windowWillCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        windowDidResignKeyObserver = nil
        windowWillCloseObserver = nil
    }

    private var showsCancelButton: Bool {
        get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
        set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButtonCell : nil }
    }
}

private final class LocalEventMonitor {
    private let events: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    private weak var monitor: AnyObject?

    init(events: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.events = events
        self.handler = handler
    }

    @discardableResult
    func start() -> Self {
        monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: handler) as AnyObject
        return self
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

private extension NSSearchField {
    func hideCaret() {
        (currentEditor() as? NSTextView)?.insertionPointColor = .clear
    }

    func restoreCaret() {
        (currentEditor() as? NSTextView)?.insertionPointColor = .labelColor
    }
}

extension Notification.Name {
    static let shortcutRecorderActiveDidChange = Notification.Name("com.rokartur.Micmute.shortcutRecorderActiveDidChange")
}
