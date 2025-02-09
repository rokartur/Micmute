//
//  KeyboardShortcutsGlobal.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMuteShortcut = Self("toggleMuteShortcut", default: .init(.m, modifiers: [.control, .option, .shift, .command]))
}
