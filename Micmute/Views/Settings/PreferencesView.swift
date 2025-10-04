import SwiftUI
import AppKit

enum PreferenceTab: String, CaseIterable {
    case general = "General"
    case notification = "Notification"
    case updates = "Updates"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .notification:
            return "bell.badge"
        case .updates:
            return "arrow.down.app"
        case .about:
            return "info.circle"
        }
    }
}

struct SidebarItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let systemImage: String
}

struct DetailView: View {
    let item: SidebarItem

    var body: some View {
        VStack {
            Text("Wybrano: \(item.title)")
                .font(.largeTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var updatesModel: SettingsUpdaterModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: PreferenceTab = .general

    private let sidebarWidth: CGFloat = 216
    private let contentMinWidth: CGFloat = 520
    private let contentMaxWidth: CGFloat = 640
    private let windowMinHeight: CGFloat = 520
    private let chromeCornerRadius: CGFloat = 12
    private let chromeTopInset: CGFloat = 30
    private let chromeHorizontalInset: CGFloat = 26
    private let chromeBottomInset: CGFloat = 24

    @State private var selection: SidebarItem? = SidebarItem(title: "Home", systemImage: "house")
    let sidebarItems: [SidebarItem] = [
        SidebarItem(title: "Home", systemImage: "house"),
        SidebarItem(title: "Settings", systemImage: "gear"),
        SidebarItem(title: "Profile", systemImage: "person.crop.circle")
    ]
    
    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                
        } detail: {
            contentArea
                .frame(minWidth: contentMinWidth, maxWidth: contentMaxWidth)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PreferenceTab.allCases, id: \.self) { tab in
                    SettingsSidebarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Version")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                         Text("v\(AppInfo.appVersion) (\(AppInfo.appBuildNumber))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)

                if updatesModel.updateAvailable {
                    Label("Update available", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.bottom, 12)
            .padding(.horizontal, 6)
        }
    .padding(.vertical, 18)
    .padding(.horizontal, 14)
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                contentView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .general:
            GeneralView()
//        case .perAppAudio:
//            PerAppAudioView()
        case .notification:
            NotificationView()
        case .updates:
            UpdatesView()
        case .about:
            AboutView()
        }
    }

    private var sidebarBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var contentBackground: some View {
        Group {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var chromeBackground: some View {
        Group {
            if #available(macOS 26, *) {
                RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous)
                    .fill(chromeFillColor(isModernStyle: true))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous)
                    .fill(chromeFillColor(isModernStyle: false))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous))
            }
        }
        .ignoresSafeArea()
    }

    private var chromeBorder: some View {
        RoundedRectangle(cornerRadius: chromeCornerRadius, style: .continuous)
            .strokeBorder(chromeBorderColor, lineWidth: 1)
            .blendMode(colorScheme == .dark ? .plusLighter : .normal)
    }

    private func closePreferencesWindow() {
        if let window = NSApp?.windows.first(where: { $0 is PreferencesWindow }) {
            window.performClose(nil)
        } else {
            NSApp?.keyWindow?.performClose(nil)
        }
    }
}

private extension PreferencesView {
    func chromeFillColor(isModernStyle: Bool) -> Color {
        if colorScheme == .dark {
            return isModernStyle ? Color.black.opacity(0.28) : Color.black.opacity(0.24)
        } else {
            return isModernStyle ? Color.white.opacity(0.88) : Color.white.opacity(0.82)
        }
    }

    var chromeBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}

private struct SettingsSidebarButton: View {
    let tab: PreferenceTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SettingsSidebarButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    var isSelected: Bool
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if isHovered {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    }

                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.3 : 0.12), lineWidth: isSelected ? 1.1 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
