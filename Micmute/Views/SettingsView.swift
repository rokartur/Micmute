//
//  PreferencesView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    var minWidth: CGFloat = 512
    var minHeight: CGFloat = 64

    var body: some View {
        TabView {
            GeneralView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            AnimationView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("Animation", systemImage: "cursorarrow.motionlines.click")
                }
            AboutView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("About", systemImage: "rectangle.topthird.inset.filled")
                }
        }
        .fixedSize()
    }
}
