//
//  PreferencesView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AboutView()
                .tabItem {
                    Label("About", systemImage: "rectangle.topthird.inset.filled")
                }
        }
        .frame(minWidth: 352, maxWidth: 352, minHeight: 128, maxHeight: 128)
    }
}
