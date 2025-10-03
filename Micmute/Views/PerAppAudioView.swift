//
//  PerAppAudioView.swift
//  Micmute
//
//  Created by artur on 01/10/2025.
//

import SwiftUI

struct PerAppAudioView: View {
    @EnvironmentObject private var perAppVolumeManager: PerAppAudioVolumeManager
    @AppStorage(AppStorageEntry.perAppShowOnlyActive.rawValue) private var showOnlyActive = false
    
    var body: some View {
        VStack(spacing: 16) {
            CustomSectionView(title: "Per-app volume control") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Control the volume of individual apps playing audio on your Mac.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    backendBadge
                    
                    Divider()
                    
                    statusView

                    if showsActionButtons {
                        Divider()

                        actionButtons
                    }

                    if perAppVolumeManager.driverState == .ready {
                        Divider()
                        toggleRow
                        appsListSection
                    }

                    if case .notInstalled = perAppVolumeManager.driverState {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Plugin not installed", systemImage: "info.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("Install the HAL audio plugin to enable per-app volume control.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button("Install driver") {
                                perAppVolumeManager.installDriver()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if case .installFailure(let error) = perAppVolumeManager.driverState {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Installation issue", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                            
                            Text(error.localizedDescription)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button("Retry installation") {
                                perAppVolumeManager.reinstallDriver()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if case .unavailable(let message) = perAppVolumeManager.driverState {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Plugin unavailable", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                            
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Button("Reinstall driver") {
                                perAppVolumeManager.reinstallDriver()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
            
            CustomSectionView(title: "How it works") {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(
                        icon: "checkmark.circle.fill",
                        title: "Automatic detection",
                        description: "Apps are detected when they start playing audio"
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "slider.horizontal.3",
                        title: "Individual control",
                        description: "Adjust volume from 0% to 125% per app"
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "speaker.slash.fill",
                        title: "Mute support",
                        description: "Mute specific apps without affecting others"
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "arrow.clockwise",
                        title: "Live updates",
                        description: "Changes apply immediately to running apps"
                    )
                }
            }
            
            CustomSectionView(title: "Requirements") {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(
                        icon: "lock.shield.fill",
                        title: "System privileges",
                        description: "Administrator password needed for driver installation",
                        color: .orange
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Audio restart",
                        description: "CoreAudio service will restart during installation",
                        color: .orange
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding()
    }
    
    @ViewBuilder
    private var statusView: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .medium))
                
                Text(statusDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if case .installing = perAppVolumeManager.driverState {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else if case .uninstalling = perAppVolumeManager.driverState {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else if case .initializing = perAppVolumeManager.driverState {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch perAppVolumeManager.driverState {
        case .idle:
            Image(systemName: "circle.fill")
                .foregroundColor(.secondary)
        case .notInstalled:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.blue)
        case .installing, .uninstalling, .initializing:
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundColor(.blue)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .installFailure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        case .unavailable:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
    
    private var statusTitle: String {
        switch perAppVolumeManager.driverState {
        case .idle:
            return "Not started"
        case .notInstalled:
            return "Not installed"
        case .installing:
            return "Installing plugin..."
        case .uninstalling:
            return "Uninstalling plugin..."
        case .initializing:
            return "Initializing plugin..."
        case .ready:
            return "Ready"
        case .installFailure:
            return "Installation failed"
        case .unavailable:
            return "Plugin unavailable"
        }
    }
    
    private var statusDescription: String {
        switch perAppVolumeManager.driverState {
        case .idle:
            return "Plugin initialization pending"
        case .notInstalled:
            return "Plugin needs to be installed manually"
        case .installing:
            return "Installing HAL audio plugin to system"
        case .uninstalling:
            return "Removing HAL audio plugin from system"
        case .initializing:
            return "Locating HAL audio plugin"
        case .ready:
            return "Per-app audio control is active"
        case .installFailure:
            return "Failed to install HAL audio plugin"
        case .unavailable:
            return "HAL audio plugin could not be located"
        }
    }

    private var showsActionButtons: Bool {
        switch perAppVolumeManager.driverState {
        case .ready, .unavailable, .installFailure:
            return true
        default:
            return false
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if case .unavailable = perAppVolumeManager.driverState {
                Button("Retry installation") {
                    perAppVolumeManager.reinstallDriver()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button("Uninstall driver") {
                perAppVolumeManager.uninstallDriver()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if perAppVolumeManager.driverState == .ready {
                Button("Reinstall") {
                    perAppVolumeManager.reinstallDriver()
                }
                .controlSize(.small)
            }
        }
    }
}

private extension PerAppAudioView {
    var filteredApplications: [AudioApplication] {
        let apps = perAppVolumeManager.applications
        if showOnlyActive {
            return apps.filter { Date().timeIntervalSince($0.lastSeen) < 5.0 }
        }
        return apps
    }

    var toggleRow: some View {
        Toggle(isOn: $showOnlyActive) {
            Text("Show only active (last 5s)")
                .font(.system(size: 11))
        }
        .toggleStyle(.switch)
    }

    var appsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if filteredApplications.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundColor(.secondary)
                    Text("No applications matching filter")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(filteredApplications, id: \ .bundleID) { app in
                    appRow(app)
                    if app.bundleID != filteredApplications.last?.bundleID { Divider() }
                }
            }
        }
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.15), value: filteredApplications.map { $0.bundleID })
    }

    @ViewBuilder
    func appRow(_ app: AudioApplication) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .overlay(Text(app.name.prefix(1)).font(.system(size: 10)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 4) {
                    if showOnlyActive {
                        let delta = Date().timeIntervalSince(app.lastSeen)
                        Text(delta < 1 ? "now" : String(format: "%.0fs", delta))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if app.isMuted { Text("muted").font(.system(size: 9)).foregroundColor(.secondary) }
                }
            }
            Spacer()
            Slider(value: Binding(
                get: { app.volume },
                set: { perAppVolumeManager.setVolume(bundleID: app.bundleID, volume: $0) }
            ), in: 0...1.25) {
                Text("Volume")
            }
            .frame(width: 120)
            .help("Adjust volume for \(app.name)")
            Button(action: { perAppVolumeManager.setMuted(bundleID: app.bundleID, muted: !app.isMuted) }) {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .help(app.isMuted ? "Unmute" : "Mute")
        }
        .padding(.vertical, 2)
    }

    var backendBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.cross")
                .font(.system(size: 11, weight: .semibold))
            Text("HAL plugin backend")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityLabel("Active per-app audio backend")
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    var color: Color = .accentColor
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
