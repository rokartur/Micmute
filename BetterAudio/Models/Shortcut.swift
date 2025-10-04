import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let keyCode: UInt16
    private let modifierFlagsRawValue: UInt
    private let characters: String?

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, characters: String?) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.intersection(.permittedShortcutFlags).rawValue
        if let characters, characters.isEmpty == false {
            self.characters = characters.uppercased()
        } else {
            self.characters = nil
        }
    }

    init?(event: NSEvent) {
        let cleanedModifiers = event.modifierFlags.intersection(.permittedShortcutFlags)
        let keyCode = UInt16(event.keyCode)

        if keyCode == kVK_Escape {
            return nil
        }

        if Shortcut.isClearingKey(keyCode: keyCode) {
            return nil
        }

        let cleanedCharacters = ShortcutFormatter.cleanedCharacters(from: event.charactersIgnoringModifiers)
        if cleanedCharacters == nil && !ShortcutFormatter.supportsKeyCodeWithoutCharacters(keyCode) {
            return nil
        }

        self.init(keyCode: keyCode, modifierFlags: cleanedModifiers, characters: cleanedCharacters)
    }

    var displayString: String {
        ShortcutFormatter.displayString(forKeyCode: keyCode, modifiers: modifierFlags, characters: characters)
    }

    var carbonModifiers: UInt32 {
        ShortcutModifierTranslator.carbonFlags(from: modifierFlags)
    }

    static let defaultToggleMute = Shortcut(
        keyCode: UInt16(kVK_ANSI_M),
        modifierFlags: [.command, .option, .shift, .control],
        characters: "M"
    )

    static let defaultCheckMute = Shortcut(
        keyCode: UInt16(kVK_ANSI_L),
        modifierFlags: [.command, .option, .control],
        characters: "L"
    )

    static func isClearingKey(keyCode: UInt16) -> Bool {
        keyCode == kVK_Delete || keyCode == kVK_ForwardDelete
    }
}

extension NSEvent.ModifierFlags {
    static let permittedShortcutFlags: NSEvent.ModifierFlags = [.command, .option, .shift, .control, .function]
}

enum ShortcutIdentifier: UInt32, CaseIterable {
    case toggleMute = 1
    case checkMute = 2
    case pushToTalk = 3

    var defaultsKey: String {
        switch self {
        case .toggleMute:
            return "shortcut.toggleMute"
        case .checkMute:
            return "shortcut.checkMute"
        case .pushToTalk:
            return "shortcut.pushToTalk"
        }
    }
}

extension ShortcutIdentifier: CustomStringConvertible {
    var description: String {
        switch self {
        case .toggleMute:
            return "toggleMute"
        case .checkMute:
            return "checkMute"
        case .pushToTalk:
            return "pushToTalk"
        }
    }
}

private enum ShortcutModifierTranslator {
    static func carbonFlags(from modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0

        if modifierFlags.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }
        if modifierFlags.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }
        if modifierFlags.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }
        if modifierFlags.contains(.function) {
            carbonFlags |= UInt32(NX_SECONDARYFNMASK)
        }

        return carbonFlags
    }
}

private enum ShortcutFormatter {
    static func displayString(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String {
        let modifiersString = modifierSymbols(from: modifiers)
        let keyTitle = title(forKeyCode: keyCode, characters: characters)
        if modifiersString.isEmpty {
            return keyTitle
        }
        return modifiersString + keyTitle
    }

    static func cleanedCharacters(from raw: String?) -> String? {
        guard var raw else { return nil }
        if raw.isEmpty { return nil }
        if raw.count == 1, let scalar = raw.unicodeScalars.first, CharacterSet.whitespaces.contains(scalar) {
            return nil
        }
        raw = raw.uppercased()
        return raw
    }

    static func supportsKeyCodeWithoutCharacters(_ keyCode: UInt16) -> Bool {
        keyCodeTitles[keyCode] != nil
    }

    private static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> String {
        var components: [String] = []
        if flags.contains(.control) { components.append("⌃") }
        if flags.contains(.option) { components.append("⌥") }
        if flags.contains(.shift) { components.append("⇧") }
        if flags.contains(.command) { components.append("⌘") }
        if flags.contains(.function) { components.append("fn") }
        return components.joined()
    }

    private static func title(forKeyCode keyCode: UInt16, characters: String?) -> String {
        if let mapped = keyCodeTitles[keyCode] {
            return mapped
        }
        if let characters, characters.isEmpty == false {
            if characters.count == 1 {
                return characters.uppercased()
            } else {
                return characters.uppercased()
            }
        }
        return String(format: "0x%02X", keyCode)
    }

    private static let keyCodeTitles: [UInt16: String] = {
        var map: [UInt16: String] = [
            UInt16(kVK_Return): "Return",
            UInt16(kVK_ANSI_KeypadEnter): "Enter",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Tab): "Tab",
            UInt16(kVK_Delete): "Delete",
            UInt16(kVK_ForwardDelete): "Forward Delete",
            UInt16(kVK_Escape): "Escape",
            UInt16(kVK_CapsLock): "Caps Lock",
            UInt16(kVK_Help): "Help",
            UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End",
            UInt16(kVK_PageUp): "Page Up",
            UInt16(kVK_PageDown): "Page Down",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓"
        ]

        let functionKeys: [(UInt16, String)] = [
            (UInt16(kVK_F1), "F1"), (UInt16(kVK_F2), "F2"), (UInt16(kVK_F3), "F3"),
            (UInt16(kVK_F4), "F4"), (UInt16(kVK_F5), "F5"), (UInt16(kVK_F6), "F6"),
            (UInt16(kVK_F7), "F7"), (UInt16(kVK_F8), "F8"), (UInt16(kVK_F9), "F9"),
            (UInt16(kVK_F10), "F10"), (UInt16(kVK_F11), "F11"), (UInt16(kVK_F12), "F12"),
            (UInt16(kVK_F13), "F13"), (UInt16(kVK_F14), "F14"), (UInt16(kVK_F15), "F15"),
            (UInt16(kVK_F16), "F16"), (UInt16(kVK_F17), "F17"), (UInt16(kVK_F18), "F18"),
            (UInt16(kVK_F19), "F19"), (UInt16(kVK_F20), "F20")
        ]
        for (code, title) in functionKeys {
            map[code] = title
        }

        return map
    }()
}
