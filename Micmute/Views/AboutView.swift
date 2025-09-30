//
//  AboutView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import AlinFoundation

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Micmute")
                        .font(.system(size: 32, weight: .bold))
                    
                    Text("Version \(AppInfo.appVersion)  Build (\(AppInfo.appBuildNumber))")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    Text("Made with ❤️ by rokartur")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 6)
            }
            
            VStack(spacing: 8) {
                VStack {
                    LinkButton(
                        title: "Star on GitHub",
                        subtitle: "Support the project",
                        icon: "star.fill",
                        color: .yellow
                    ) {
                        NSWorkspace.shared.open(AppInfo.repo)
                    }
                    
                    LinkButton(
                        title: "What's New",
                        subtitle: "View release notes",
                        icon: "doc.text.fill",
                        color: .blue
                    ) {
                        NSWorkspace.shared.open(AppInfo.whatsNew)
                    }
                    
                    LinkButton(
                        title: "Author",
                        subtitle: "@rokartur",
                        icon: "person.fill",
                        color: .purple
                    ) {
                        NSWorkspace.shared.open(AppInfo.author)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Link Button Component
struct LinkButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
