import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            CustomSectionView {
                HStack(alignment: .top, spacing: 18) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .overlay(
                            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                                .resizable()
                                .scaledToFit()
                                .padding(18)
                        )
                        .frame(width: 148, height: 148)

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Micmute")
                                .font(.system(size: 28, weight: .bold))

                            Text("v\(AppInfo.appVersion) • build \(AppInfo.appBuildNumber)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Made with ❤️ by rokartur")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Text("Micmute helps you stay in control of your microphone with quick shortcuts, per-app audio and a native macOS design.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            CustomSectionView(title: "Stay in touch") {
                VStack(spacing: 10) {
                    AboutLinkRow(
                        title: "Star on GitHub",
                        subtitle: "Support the project and follow releases",
                        systemImage: "star.fill",
                        tint: LinearGradient(colors: [.yellow.opacity(0.9), .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    ) {
                        NSWorkspace.shared.open(AppInfo.repo)
                    }

                    AboutLinkRow(
                        title: "What's new",
                        subtitle: "Browse the latest release notes",
                        systemImage: "doc.text.fill",
                        tint: LinearGradient(colors: [.blue.opacity(0.85), .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    ) {
                        NSWorkspace.shared.open(AppInfo.whatsNew)
                    }

                    AboutLinkRow(
                        title: "Author",
                        subtitle: "@rokartur on GitHub",
                        systemImage: "person.fill",
                        tint: LinearGradient(colors: [.pink.opacity(0.85), .purple.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    ) {
                        NSWorkspace.shared.open(AppInfo.author)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AboutLinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: LinearGradient
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white)
                    )
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.03))
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(isHovered ? 0.45 : 0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hover
            }
        }
    }
}
