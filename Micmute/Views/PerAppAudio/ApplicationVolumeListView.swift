import AppKit
import SwiftUI

struct ApplicationVolumeListView: View {
    @ObservedObject private var manager: PerAppAudioVolumeManager
    @StateObject private var viewModel: ApplicationVolumeListViewModel

    @State private var isEditingFilter = false
    @State private var filterText: String = ""
    private let showsHeader: Bool

    init(manager: PerAppAudioVolumeManager, showsHeader: Bool = true) {
        self.showsHeader = showsHeader
        _manager = ObservedObject(wrappedValue: manager)
        _viewModel = StateObject(wrappedValue: ApplicationVolumeListViewModel(manager: manager))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                header
            }

            driverStateContent
        }
        .onChange(of: filterText, initial: false) { _, newValue in
            viewModel.updateFilter(to: newValue)
        }
        .onAppear {
            if filterText.isEmpty {
                viewModel.updateFilter(to: "")
            }
        }
    }

    @ViewBuilder
    private var driverStateContent: some View {
        switch manager.driverState {
        case .notInstalled:
            notInstalledPanel
        case .installing:
            progressPanel(title: "Installing virtual audio driver…", subtitle: "You'll be asked for administrator permission so we can place the driver in the HAL folder.")
        case .uninstalling:
            progressPanel(title: "Uninstalling virtual audio driver…", subtitle: "Removing driver and restarting audio services.")
        case .initializing, .idle:
            progressPanel(title: "Preparing virtual audio driver…", subtitle: "This takes only a moment.")
        case .ready:
            if viewModel.hasActiveApplications {
                listContent
            } else {
                emptyState
            }
        case .installFailure(let error):
            installFailurePanel(error)
        case .failure(let driverError):
            driverFailurePanel(driverError)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Label("Per-app volume", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh active applications list")

            if manager.driverState == .ready {
                Button(action: manager.uninstallDriver) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Uninstall virtual audio driver")
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        VStack(spacing: 10) {
            searchField

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.rows) { rowViewModel in
                        ApplicationVolumeRow(viewModel: rowViewModel)
                            .glassPanel()
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No audio sources detected", systemImage: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            Text("Launch an app that plays audio to adjust its individual volume. We'll update automatically when new sessions appear.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassPanel()
    }

    private func progressPanel(title: LocalizedStringKey, subtitle: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
        }
        .padding(16)
        .glassPanel()
    }

    private func installFailurePanel(_ error: DriverInstallerError) -> some View {
        actionPanel(
            title: "Virtual audio driver required",
            primaryMessage: "Micmute needs administrator permission to install its virtual audio driver. We'll restart audio services automatically.",
            secondaryMessage: Text(verbatim: error.localizedDescription)
                .font(.system(size: 12))
                .foregroundColor(.secondary),
            actionTitle: "Install driver"
        ) {
            manager.reinstallDriver()
        }
    }

    private var notInstalledPanel: some View {
        actionPanel(
            title: "Driver not installed",
            primaryMessage: "Install the virtual audio driver to enable per-app volume control. You'll need to provide administrator permission.",
            secondaryMessage: nil,
            actionTitle: "Install driver"
        ) {
            manager.installDriver()
        }
    }

    private func driverFailurePanel(_ error: VirtualDriverBridgeError) -> some View {
        actionPanel(
            title: "Virtual audio driver unavailable",
            primaryMessage: "Micmute couldn't start its virtual audio driver. Try reinstalling or rebooting your Mac.",
            secondaryMessage: Text(verbatim: error.localizedDescription)
                .font(.system(size: 12))
                .foregroundColor(.secondary),
            actionTitle: "Retry installation"
        ) {
            manager.reinstallDriver()
        }
    }

    private func actionPanel(
        title: LocalizedStringKey,
        primaryMessage: LocalizedStringKey,
        secondaryMessage: Text?,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Text(primaryMessage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let secondaryMessage {
                secondaryMessage
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(16)
        .glassPanel()
    }

    @ViewBuilder
    private var searchField: some View {
        if #available(macOS 14.0, *) {
            SearchField(text: $filterText)
                .textFieldStyle(.roundedBorder)
                .onTapGesture { isEditingFilter = true }
        } else {
            TextField("Search apps", text: $filterText)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(string: text)
        searchField.placeholderString = "Search apps"
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

private extension View {
    func glassPanel(cornerRadius: CGFloat = 14, strokeOpacity: Double = 0.25) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }
}
