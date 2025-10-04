import SwiftUI

struct CustomSectionView<Content: View>: View {
    let title: String?
    let subtitle: String?
    let content: Content

    private let cornerRadius: CGFloat = 12
    
    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasHeader {
                header
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, hasHeader ? 18 : 16)
        .padding(.horizontal, 20)
        .background(sectionBackground)
        .overlay(sectionBorder)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var hasHeader: Bool {
        (title?.isEmpty == false) || (subtitle?.isEmpty == false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }
}
