//
//  UpdatesView.swift
//  Micmute
//
//  Created by artur on 30/09/2025.
//

import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var updatesModel: SettingsUpdaterModel
    private let performUpdateChecks: Bool
    @State private var activeSheet: ActiveSheet?

    init(performUpdateChecks: Bool = true) {
        self.performUpdateChecks = performUpdateChecks
    }

    private enum ActiveSheet: Identifiable {
        case announcement
        case releaseNotes

        var id: Int { hashValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CustomSectionView(title: "Update status", subtitle: "Manually check for new Micmute releases") {
                    updateStatusSection
                }

                CustomSectionView(title: "Automatic checks", subtitle: "Choose how often Micmute looks for updates") {
                    automaticChecksSection
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard performUpdateChecks else { return }
            updatesModel.refreshIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .announcement:
                AnnouncementSheet(text: updatesModel.announcementText) {
                    activeSheet = nil
                    updatesModel.markAnnouncementViewed()
                }
                .frame(width: 360, height: 280)
                .padding()
            case .releaseNotes:
                ReleaseNotesSheet(releases: updatesModel.releases) {
                    activeSheet = nil
                }
                .frame(width: 420, height: 420)
                .padding()
            }
        }
    }

    private var updateStatusSection: some View {
        let statusIconName = updatesModel.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill"
        let statusColor: Color = updatesModel.updateAvailable ? .orange : .green
        let statusBackground = updatesModel.updateAvailable ? Color.orange.opacity(0.18) : Color.green.opacity(0.16)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(statusBackground)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 16, weight: .semibold))

                    Text(statusSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        Label("Installed", systemImage: "desktopcomputer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("v\(updatesModel.currentVersion)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }

            HStack(spacing: 12) {
                if let descriptor = currentOperationStatusDescriptor {
                    UpdateOperationStatusView(descriptor: descriptor)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: updatesModel.checkForUpdates) {
                        Label("Check for updates", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(UpdatesPrimaryButtonStyle())
                }

                if currentOperationStatusDescriptor == nil && updatesModel.updateAvailable {
                    Button(action: updatesModel.downloadUpdate) {
                        Label("Download update", systemImage: "arrow.down.to.line")
                            .font(.system(size: 13, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(UpdatesSecondaryButtonStyle())
                }

                // if updatesModel.announcementAvailable {
                //     Button {
                //         activeSheet = .announcement
                //     } label: {
                //         Label("View announcement", systemImage: "sparkles")
                //             .font(.system(size: 12, weight: .medium))
                //     }
                //     .buttonStyle(.link)
                // }

                if !updatesModel.releases.isEmpty {
                    Button {
                        activeSheet = .releaseNotes
                    } label: {
                        Label("Release notes", systemImage: "doc.richtext")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.link)
                }
            }

            if updatesModel.restartRequired {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Restart required")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Micmute needs to restart to finish installing the update.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Spacer()
                        Button(action: updatesModel.restartApplication) {
                            Label("Restart", systemImage: "power")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var automaticChecksSection: some View {
        let columns = [
            GridItem(.flexible(minimum: 120), spacing: 12),
            GridItem(.flexible(minimum: 120), spacing: 12)
        ]

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatic update checks")
                        .font(.system(size: 14, weight: .semibold))

                    Text(automaticChecksSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(UpdateFrequencyOption.allCases) { option in
                    FrequencyOptionRow(option: option, isSelected: updatesModel.frequency == option) {
                        updatesModel.setFrequency(option)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if updatesModel.frequency != .never {
                Label {
                    Text("Next check \(formattedNextCheck)")
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            } else {
                Label {
                    Text("Micmute won't check automatically — you'll need to run manual checks.")
                        .font(.system(size: 11))
                } icon: {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: updatesModel.frequency)
    }

    private var statusTitle: String {
        updatesModel.updateAvailable ? "A new version is available" : "You're up to date"
    }

    private var statusSubtitle: String {
        if updatesModel.updateAvailable, let latest = updatesModel.latestRelease {
            return "Download \(latest.displayTitle) to stay current."
        }
        return "Micmute is running the latest available build."
    }

    private var checkingMessage: String {
        if updatesModel.progressMessage.isEmpty {
            return "Checking for updates…"
        }
        return updatesModel.progressMessage
    }

    private var currentOperationStatusDescriptor: UpdateOperationStatusDescriptor? {
        if updatesModel.isCheckingForUpdates {
            let tint = Color.accentColor
            return UpdateOperationStatusDescriptor(
                title: checkingMessage,
                showsSpinner: true,
                iconName: nil,
                iconColor: tint,
                textColor: .primary,
                background: tintedBackground(using: tint),
                border: tintedBorder(using: tint),
                progress: nil
            )
        }

        let trimmedMessage = updatesModel.progressMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return nil }
        return descriptor(for: trimmedMessage, progress: updatesModel.progressValue)
    }

    private func descriptor(for message: String, progress: Double) -> UpdateOperationStatusDescriptor {
        let lowercased = message.lowercased()

        var iconName: String? = "info.circle.fill"
        var tint: Color = .accentColor
        var textColor: Color = .primary

        if lowercased.contains("download") {
            iconName = "arrow.down.circle.fill"
        }

        if lowercased.contains("prepar") {
            iconName = "gearshape.2.fill"
        }

        if lowercased.contains("extract") {
            iconName = "shippingbox.fill"
        }

        if lowercased.contains("install") {
            iconName = "square.and.arrow.down.on.square.fill"
        }

        if lowercased.contains("restart") || lowercased.contains("relaunch") {
            iconName = "arrow.triangle.2.circlepath.circle.fill"
        }

        if lowercased.contains("update installed") || lowercased.contains("latest release info fetched") {
            iconName = "checkmark.circle.fill"
            tint = .green
        }

        if lowercased.contains("cancel") {
            iconName = "exclamationmark.triangle.fill"
            tint = .orange
        }

        if lowercased.contains("failed") || lowercased.contains("unable") || lowercased.contains("couldn't") || lowercased.contains("error") {
            iconName = "xmark.octagon.fill"
            tint = .red
            textColor = .primary
        }

        if lowercased.contains("no releases") || lowercased.contains("no suitable") {
            iconName = "questionmark.circle.fill"
            tint = .orange
        }

        let shouldDisplayProgress = progress > 0 && progress < 0.999 && (
            lowercased.contains("prepar") ||
            lowercased.contains("download") ||
            lowercased.contains("extract") ||
            lowercased.contains("install")
        )

        let progressForDisplay: Double? = shouldDisplayProgress ? progress : nil

        return UpdateOperationStatusDescriptor(
            title: message,
            showsSpinner: false,
            iconName: iconName,
            iconColor: tint,
            textColor: textColor,
            background: tintedBackground(using: tint),
            border: tintedBorder(using: tint),
            progress: progressForDisplay
        )
    }

    private func tintedBackground(using tint: Color) -> Color {
        tint.opacity(0.12)
    }

    private func tintedBorder(using tint: Color) -> Color {
        tint.opacity(0.26)
    }

    private var automaticChecksSummary: String {
        switch updatesModel.frequency {
        case .never:
            return "Automatic checks are turned off."
        case .daily:
            return "Micmute checks for updates every day in the background."
        case .weekly:
            return "Micmute checks for updates once each week."
        case .monthly:
            return "Micmute checks for updates once each month."
        }
    }

    private var formattedNextCheck: String {
        let absoluteFormatter = DateFormatter()
        absoluteFormatter.dateStyle = .medium
        absoluteFormatter.timeStyle = .short

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .full

        let nextDate = updatesModel.nextScheduledCheck
        let relative = relativeFormatter.localizedString(for: nextDate, relativeTo: Date())
        return "\(relative) (\(absoluteFormatter.string(from: nextDate)))"
    }

}

private struct FrequencyOptionRow: View {
    let option: UpdateFrequencyOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(option.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(FrequencyOptionButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var iconName: String {
        switch option {
        case .never: return "pause.circle"
        case .daily: return "sun.max"
        case .weekly: return "calendar"
        case .monthly: return "calendar.circle"
        }
    }
}

private struct AnnouncementSheet: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Latest announcement")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                Text(text.isEmpty ? "No announcement available." : text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Button("Close", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct ReleaseNotesSheet: View {
    let releases: [SettingsRelease]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header

            if releases.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(releases, id: \.id) { release in
                            releaseCard(for: release)
                                .padding(.horizontal, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button("Close", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recent release notes")
                    .font(.headline)
                Text("Pulled straight from GitHub")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(.secondary)
            Text("Release notes are still loading")
                .font(.system(size: 14, weight: .semibold))
            Text("They will appear here once Micmute fetches them from GitHub.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    @ViewBuilder
    private func releaseCard(for release: SettingsRelease) -> some View {
        let title = release.tagName.isEmpty ? release.displayTitle : release.tagName
        let isLatest = release.id == releases.first?.id

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if isLatest {
                    ReleaseBadge(label: "Latest", style: .latest)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if let markdown = release.githubMarkdownBody() {
                Text(markdown)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                Text("No release description provided.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
        )
    }
}

private struct UpdateOperationStatusView: View {
    let descriptor: UpdateOperationStatusDescriptor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if descriptor.showsSpinner {
                ProgressView()
                    .controlSize(.small)
            } else if let icon = descriptor.iconName {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(descriptor.iconColor)
                    .frame(width: 18)
            }

            Text(descriptor.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(descriptor.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let progress = descriptor.progress {
                Text(progressFormatted(progress))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(descriptor.iconColor)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(descriptor.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(descriptor.border, lineWidth: 1)
        )
    }

    private func progressFormatted(_ value: Double) -> String {
        let clamped = max(0, min(1, value))
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }
}

private struct UpdateOperationStatusDescriptor {
    let title: String
    let showsSpinner: Bool
    let iconName: String?
    let iconColor: Color
    let textColor: Color
    let background: Color
    let border: Color
    let progress: Double?
}

struct ReleaseBadge: View {
    enum Style {
        case latest

        var foreground: Color { .white }

        var background: LinearGradient {
            LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        var border: Color { Color.accentColor.opacity(0.8) }
    }

    let label: String
    let style: Style

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(style.foreground)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(style.background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.border, lineWidth: 0.8)
            )
    }
}

private struct FrequencyOptionButtonStyle: ButtonStyle {
    var isSelected: Bool
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
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

private struct UpdatesPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let accent = Color.accentColor
        let activeOpacity: Double = configuration.isPressed ? 0.85 : 1.0
        let inactiveOpacity: Double = configuration.isPressed ? 0.65 : 0.78
        let gradientColors: [Color] = isEnabled
            ? [accent.opacity(activeOpacity), accent.opacity(inactiveOpacity)]
            : [accent.opacity(0.42), accent.opacity(0.32)]

        return configuration.label
            .foregroundColor(isEnabled ? Color.white : Color.white.opacity(0.7))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    shape.fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    shape.stroke(Color.white.opacity(isEnabled ? 0.18 : 0.1), lineWidth: 0.6)
                        .blur(radius: 0.4)
                        .clipShape(shape)
                    if configuration.isPressed {
                        shape.fill(Color.white.opacity(0.08))
                    }
                }
            )
            .overlay(
                shape.stroke(accent.opacity(isEnabled ? 0.55 : 0.32), lineWidth: 1)
            )
            .shadow(color: accent.opacity(isEnabled ? 0.45 : 0.2), radius: configuration.isPressed ? 4 : 8, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct UpdatesSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return configuration.label
            .foregroundColor(isEnabled ? Color.primary : Color.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(isEnabled ? 0.1 : 0.06))
                    if configuration.isPressed {
                        shape.fill(Color.white.opacity(0.14))
                    }
                }
            )
            .overlay(
                shape.stroke(Color.accentColor.opacity(isEnabled ? 0.45 : 0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
