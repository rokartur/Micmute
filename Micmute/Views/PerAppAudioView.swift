//
//  PerAppAudioView.swift
//  Micmute
//
//  Created by artur on 01/10/2025.
//

import SwiftUI

struct PerAppAudioView: View {
    @EnvironmentObject private var perAppVolumeManager: PerAppAudioVolumeManager
    
    var body: some View {
        VStack(spacing: 16) {
            CustomSectionView(title: "Per-app volume control") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Control the volume of individual apps playing audio on your Mac.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Divider()
                    
                    statusView

                    if showsActionButtons {
                        Divider()

                        actionButtons
                    }

                    if case .notInstalled = perAppVolumeManager.driverState {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Driver not installed", systemImage: "info.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("Install the virtual audio driver to enable per-app volume control.")
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
                    
                    if case .failure(let error) = perAppVolumeManager.driverState {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Driver unavailable", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                            
                            Text(error.localizedDescription)
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
        case .failure:
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
            return "Installing driver..."
        case .uninstalling:
            return "Uninstalling driver..."
        case .initializing:
            return "Initializing driver..."
        case .ready:
            return "Ready"
        case .installFailure:
            return "Installation failed"
        case .failure:
            return "Driver unavailable"
        }
    }
    
    private var statusDescription: String {
        switch perAppVolumeManager.driverState {
        case .idle:
            return "Driver initialization pending"
        case .notInstalled:
            return "Driver needs to be installed manually"
        case .installing:
            return "Installing virtual audio driver to system"
        case .uninstalling:
            return "Removing virtual audio driver from system"
        case .initializing:
            return "Starting virtual audio driver"
        case .ready:
            return "Per-app audio control is active"
        case .installFailure:
            return "Failed to install virtual audio driver"
        case .failure:
            return "Virtual audio driver failed to start"
        }
    }

    private var showsActionButtons: Bool {
        switch perAppVolumeManager.driverState {
        case .ready, .failure, .installFailure:
            return true
        default:
            return false
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if case .failure = perAppVolumeManager.driverState {
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
        }
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
