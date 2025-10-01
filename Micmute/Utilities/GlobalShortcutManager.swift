import AppKit
import Carbon

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyReferences: [ShortcutIdentifier: EventHotKeyRef?] = [:]
    private var callbacks: [ShortcutIdentifier: ShortcutCallbacks] = [:]

    private init() {
        installEventHandler()
    }

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ identifier: ShortcutIdentifier, shortcut: Shortcut?, keyDown: (() -> Void)? = nil, keyUp: (() -> Void)? = nil) {
        unregister(identifier)

        guard let shortcut else {
            callbacks.removeValue(forKey: identifier)
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        if status == noErr {
            hotKeyReferences[identifier] = hotKeyRef
            callbacks[identifier] = ShortcutCallbacks(keyDown: keyDown, keyUp: keyUp)
        } else {
            NSLog("Failed to register hotkey for identifier: \(identifier) with status: \(status)")
        }
    }

    func unregister(_ identifier: ShortcutIdentifier) {
        if let hotKeyRef = hotKeyReferences[identifier] ?? nil {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyReferences.removeValue(forKey: identifier)
        callbacks.removeValue(forKey: identifier)
    }

    private func installEventHandler() {
        var eventTypeSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = eventTypeSpecs.withUnsafeBufferPointer { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(paramErr) }
            return InstallEventHandler(
                GetEventDispatcherTarget(),
                Self.eventHandlerCallback,
                Int(buffer.count),
                baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandler
            )
        }

        if status != noErr {
            NSLog("Failed to install event handler for global shortcuts: \(status)")
        }
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let error = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

        if error != noErr {
            return error
        }

        guard hotKeyID.signature == Self.signature,
              let identifier = ShortcutIdentifier(rawValue: hotKeyID.id),
              let callback = callbacks[identifier] else {
            return noErr
        }

        let eventKind = GetEventKind(event)

        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            if let action = callback.keyDown {
                DispatchQueue.main.async { action() }
            }
        case UInt32(kEventHotKeyReleased):
            if let action = callback.keyUp {
                DispatchQueue.main.async { action() }
            }
        default:
            break
        }

        return noErr
    }
}

private extension GlobalShortcutManager {
    struct ShortcutCallbacks {
        let keyDown: (() -> Void)?
        let keyUp: (() -> Void)?
    }

    static let signature: OSType = 0x4D49434D // 'MICM'

    static let eventHandlerCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handle(event: event)
    }
}
