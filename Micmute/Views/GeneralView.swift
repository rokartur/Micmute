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
        VStack(alignment: .leading, spacing: 16) {
            KeyboardShortcuts.Recorder("Keyboard shortcut:", name: .toggleMuteShortcut)
            HStack {
                Text("Startup:")
                LaunchAtLogin.Toggle {
                    Text("Launch Micmute at login")
                }
            }.padding([.leading], 67)
        }.padding(.horizontal, 24)
    }
}
