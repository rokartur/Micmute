//
//  SettingsView.swift
//  Micmute
//
//  Created by Artur Rok on 02/06/2024.
//

import SwiftUI

struct PreferencesView: View {
    @State private var selectedTab: String = "General"
    
    private weak var parentWindow: PreferencesWindow!
    var minWidth: CGFloat = 496
    var minHeight: CGFloat = 64
    
    init(parentWindow: PreferencesWindow) {
        self.parentWindow = parentWindow
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag("General")
            NotificationView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("Notification", systemImage: "bell.badge")
                }
                .tag("Notification")
            AboutView()
                .frame(minWidth: minWidth, maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity)
                .tabItem {
                    Label("About", systemImage: "rectangle.topthird.inset.filled")
                }
                .tag("About")
        }.fixedSize()
    }
}
