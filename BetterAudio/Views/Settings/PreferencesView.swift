import SwiftUI
import AppKit
import SwiftUIIntrospect

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
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .frame(width: sidebarWidth)
                .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
                .navigationTitle("Sidebar")
                .toolbarRole(.automatic)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Text("")
                    }
                }
                .toolbar(removing: .sidebarToggle)
        } detail: {
            contentArea
                .frame(minWidth: contentMinWidth, maxWidth: contentMaxWidth)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .introspect(.navigationSplitView, on: .macOS(.v14, .v15, .v26)) { splitView in
            guard let svc = splitView.delegate as? NSSplitViewController,
                  let sidebarItem = svc.splitViewItems.first else { return }
            sidebarItem.minimumThickness = sidebarWidth
            sidebarItem.maximumThickness = sidebarWidth
            sidebarItem.canCollapse = false
            if #available(macOS 14.0, *) {
                sidebarItem.canCollapseFromWindowResize = false
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                ForEach(PreferenceTab.allCases, id: \.self) { tab in
                    SettingsSidebarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 12)

            if updatesModel.updateAvailable {
                VStack(alignment: .leading) {
                    Label("Update available", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .labelStyle(.titleAndIcon)
                }
                .padding(.bottom, 12)
                .padding(.horizontal, 6)
            }
        }
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                contentView
                    .id(selectedTab)
                    .transition(.opacity)
                    .modifier(ContentOpacityTransitionIfAvailable())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.22), value: selectedTab)
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .general:
            GeneralView()
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

struct NonDraggableView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        NonDraggableHostingView(rootView: AnyView(content))
    }

    func updateNSView(_ nsView: NSHostingView<AnyView>, context: Context) {
        nsView.rootView = AnyView(content)
    }

    private final class NonDraggableHostingView: NSHostingView<AnyView> {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

private struct SettingsSidebarButton: View {
    let tab: PreferenceTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        NonDraggableView {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                        .animation(nil, value: isSelected)

                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .animation(nil, value: isSelected)
                }
            }
            .buttonStyle(SettingsSidebarButtonStyle(isSelected: isSelected))
        }
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor)
                    .opacity(isSelected ? 0.20 : 0)
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .opacity(configuration.isPressed ? 0.10 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ContentOpacityTransitionIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.opacity)
        } else {
            content
        }
    }
}
