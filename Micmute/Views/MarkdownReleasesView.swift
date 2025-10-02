import SwiftUI
import AppKit

struct MarkdownReleasesView: View {
    let releases: [SettingsRelease]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if releases.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(releases, id: \.id) { release in
                            releaseView(for: release)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 1)
                }

                Text("Showing last \\(releases.count) releases")
                    .font(.callout)
                    .opacity(0.55)
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Release notes are still loading")
                .font(.headline)
            Text("They will appear here right after Micmute fetches them from GitHub.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func releaseView(for release: SettingsRelease) -> some View {
        let isLatest = release.id == releases.first?.id

        VStack(alignment: .leading, spacing: 12) {
            header(for: release, isLatest: isLatest)

            if let markdown = release.githubMarkdownBody() {
                Text(markdown)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No release notes available")
                    .foregroundColor(.secondary)
            }

            if !release.assets.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloads")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(release.assets.prefix(3)) { asset in
                        if let url = asset.downloadURL ?? asset.apiURL {
                            Link(asset.name, destination: url)
                                .font(.footnote)
                        }
                    }

                    if release.assets.count > 3, let releaseURL = release.githubURL {
                        Link("View all assets on GitHub", destination: releaseURL)
                            .font(.footnote)
                    }
                }
            }

            if let releaseURL = release.githubURL {
                Link("View on GitHub", destination: releaseURL)
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }

    @ViewBuilder
    private func header(for release: SettingsRelease, isLatest: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(release.displayTitle)
                .font(.headline)
                .fontWeight(.semibold)

            Spacer(minLength: 6)

            if isLatest {
                ReleaseBadge(label: "Latest", style: .latest)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
