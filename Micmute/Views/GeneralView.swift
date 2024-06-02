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
            HStack(spacing: 12) {
                Text("Startup:")
                LaunchAtLogin.Toggle {
                    Text("Start at login")
                }
            }
            .padding([.leading], 36)
            
            HStack(spacing: 0) {
                Text("Keyboard shortcut:")
                KeyboardShortcuts.Recorder("", name: .toggleMuteShortcut)
                    
            }
        }.padding(24)
    }
}
