//
//  KeyboardShortcutSettingsView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct GeneralView: View {
    var body: some View {
        VStack(spacing: 16) {
            LaunchAtLogin.Toggle()
            KeyboardShortcuts.Recorder("", name: .toggleMuteShortcut)
        }
    }
}
