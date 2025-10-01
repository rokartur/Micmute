//
//  SettingsView.swift
//  Micmute
//
//  Created by Artur Rok on 02/06/2024.
//

import SwiftUI
import AlinFoundation

enum PreferenceTab: String, CaseIterable {
    case general = "General"
    case perAppAudio = "Per-app Audio"
    case notification = "Notification"
    case updates = "Updates"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .perAppAudio:
            return "slider.horizontal.3"
        case .notification:
            return "bell.badge"
        case .updates:
            return "arrow.down.app"
        case .about:
            return "info.circle"
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var updater: Updater
    @State private var selectedTab: PreferenceTab = .general
    @State private var updatesViewHeight: CGFloat = 620

    private let windowWidth: CGFloat = 700
    private let contentWidth: CGFloat = 520
    private let defaultWindowHeight: CGFloat = 620
    private let windowVerticalPadding: CGFloat = 0
    private var contentAreaHeight: CGFloat {
        max(updatesViewHeight - windowVerticalPadding, defaultWindowHeight - windowVerticalPadding)
    }
    
    private weak var parentWindow: PreferencesWindow!
    
    init(parentWindow: PreferencesWindow) {
        self.parentWindow = parentWindow
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(PreferenceTab.allCases, id: \.self) { tab in
                        SidebarButton(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            action: {
                                selectedTab = tab
                            }
                        )
                    }
                }
                .padding(.top, 16)
                
                Spacer()
                
                // Version info at bottom
                VStack(spacing: 4) {
                    Text("v\(AppInfo.appVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if updater.updateAvailable {
                        Label("Update available", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(width: 180)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Content area with fixed height based on About tab
            VStack(spacing: 0) {
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: contentWidth, height: contentAreaHeight)
        }
        .frame(width: windowWidth, height: updatesViewHeight)
        .overlay(
            UpdatesHeightMeasurer(contentWidth: contentWidth)
                .allowsHitTesting(false)
        )
        .onPreferenceChange(UpdatesContentHeightPreferenceKey.self) { measuredHeight in
            guard measuredHeight > 0 else { return }
            let adjustedHeight = measuredHeight + windowVerticalPadding
            updatesViewHeight = max(adjustedHeight, defaultWindowHeight)
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .general:
            GeneralView()
        case .perAppAudio:
            PerAppAudioView()
        case .notification:
            NotificationView()
        case .updates:
            UpdatesView()
        case .about:
            AboutView()
        }
    }
}

struct SidebarButton: View {
    let tab: PreferenceTab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16))
                    .frame(width: 20)
                
                Text(tab.rawValue)
                    .font(.system(size: 13))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .foregroundColor(isSelected ? .accentColor : .primary)
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct UpdatesHeightMeasurer: View {
    @EnvironmentObject private var updater: Updater
    let contentWidth: CGFloat

    var body: some View {
        UpdatesView(performUpdateChecks: false)
            .environmentObject(updater)
            .frame(width: contentWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: UpdatesContentHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
            .hidden()
    }
}

private struct UpdatesContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
