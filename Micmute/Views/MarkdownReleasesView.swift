import SwiftUI
import AppKit
import AlinFoundation

struct MarkdownReleasesView: View {
    @ObservedObject var updater: Updater

    private var releases: [Release] { updater.releases }

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

                Text("Showing last \(releases.count) releases")
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
    private func releaseView(for release: Release) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(for: release)

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

                    ForEach(release.assets.prefix(3), id: \.name) { asset in
                        if let url = URL(string: asset.browser_download_url) {
                            Link(asset.name, destination: url)
                                .font(.footnote)
                        }
                    }

                    if release.assets.count > 3, let releaseURL = url(for: release) {
                        Link("View all assets on GitHub", destination: releaseURL)
                            .font(.footnote)
                    }
                }
            }

            if let releaseURL = url(for: release) {
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
    private func header(for release: Release) -> some View {
        Text(releaseDisplayName(for: release))
            .font(.headline)
            .fontWeight(.semibold)
    }

    private func releaseDisplayName(for release: Release) -> String {
        release.name.isEmpty ? release.tag_name : release.name
    }

    private func url(for release: Release) -> URL? {
        guard let owner = GitHubReleaseConfiguration.owner,
              let repo = GitHubReleaseConfiguration.repository else { return nil }
        let encodedTag = release.tag_name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? release.tag_name
        return URL(string: "https://github.com/\(owner)/\(repo)/releases/tag/\(encodedTag)")
    }
}

#Preview {
    MarkdownReleasesView(updater: Updater(owner: "rokartur", repo: "Micmute"))
}
