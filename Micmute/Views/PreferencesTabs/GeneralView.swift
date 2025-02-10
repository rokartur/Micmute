//
//  KeyboardShortcutSettingsView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct CustomSection<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                content
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(6)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
    }
}

struct GeneralView: View {
    @AppStorage("isNotificationEnabled") var isNotificationEnabled: Bool = true
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable
    @AppStorage("displayOption") var displayOption: DisplayOption = .largeBoth
    
    var body: some View {
        VStack {
            CustomSection {
                VStack(spacing: 12) {
                    HStack {
                        Text("Launch Micmute at login")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin.isEnabled).controlSize(.mini)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Show notification")
                        Spacer()
                        Toggle("", isOn: $isNotificationEnabled).controlSize(.mini)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Keyboard shortcut")
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .toggleMuteShortcut)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding()
        }.padding(0)
    }
}
