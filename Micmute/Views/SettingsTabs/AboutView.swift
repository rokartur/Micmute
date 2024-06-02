//
//  AboutView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import Sparkle

struct AboutView: View {    
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some View {
        VStack {
            HStack(alignment: .center) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)

                VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Micmute")
                            .font(.title)
                        Text("Version \(Constants.AppInfo.appVersion) (\(Constants.AppInfo.appBuildNumber))")
                            .font(.system(size: 16))
                            .fontWeight(.light)
                            .foregroundColor(.secondary)
                    }
                    CheckForUpdatesView(updater: updaterController.updater)
                }
                Spacer()
            }
            .padding(24)
            
            Divider()
            
            HStack {
                Spacer()
                
                Button {
                    NSWorkspace.shared.open(Constants.AppInfo.whatsNew)
                } label: {
                    Text("What's New")
                }
                
                Button {
                    NSWorkspace.shared.open(Constants.AppInfo.repo)
                } label: {
                    Text("Repository")
                }
                
                Button {
                    NSWorkspace.shared.open(Constants.AppInfo.author)
                } label: {
                    Text("Author")
                }
            }
            .padding([.top], 16)
            .padding([.bottom], 24)
            .padding([.trailing])
        }
    }
}
