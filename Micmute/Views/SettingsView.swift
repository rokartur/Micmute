//
//  SettingsView.swift
//  Micmute
//
//  Created by Artur Rok on 02/06/2024.
//

import SwiftUI

struct SettingsView: View {
    var minWidth: CGFloat = 512
    var minHeight: CGFloat = 64

    @AppStorage("selectedTab") var selectedTab: String = "General"

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("General")
            AppearanceView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
                .tag("Appearance")
            AnimationView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("Animation", systemImage: "cursorarrow.motionlines.click")
                }
                .tag("Animation")
            AboutView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("About", systemImage: "rectangle.topthird.inset.filled")
                }
                .tag("About")
        }
        .fixedSize()
    }
}
