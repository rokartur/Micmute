//
//  UpdatesView.swift
//  Micmute
//
//  Created by GitHub Copilot on 30/09/2025.
//

import SwiftUI
import AlinFoundation

struct UpdatesView: View {
    @EnvironmentObject private var updater: Updater
    private let performUpdateChecks: Bool

    init(performUpdateChecks: Bool = true) {
        self.performUpdateChecks = performUpdateChecks
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CustomSectionView(title: "Update status", subtitle: "Manually check for new Micmute releases") {
                    VStack(alignment: .leading, spacing: 12) {
                        UpdateBadge(updater: updater)
                        FeatureBadge(updater: updater)
                    }
                }

                CustomSectionView(title: "Automatic checks", subtitle: "Choose how often Micmute looks for updates") {
                    FrequencyView(updater: updater)
                        .padding(.vertical, 4)
                }

                CustomSectionView(title: "Recent release notes", subtitle: "See what's new in the latest versions") {
                    MarkdownReleasesView(updater: updater)
                        .frame(minHeight: 200, maxHeight: 320)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard performUpdateChecks else { return }
            updater.checkReleaseNotes()
            updater.checkForAnnouncement()
        }
    }
}

#Preview {
    UpdatesView()
        .environmentObject(Updater(owner: "rokartur", repo: "Micmute"))
}
