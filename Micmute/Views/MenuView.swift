//
//  MenuView.swift
//  Micmute
//
//  Created by artur on 10/02/2025.
//

import SwiftUI
import CoreAudio
import MacControlCenterUI
import AlinFoundation


@MainActor
struct MainMenuView: View {
    @EnvironmentObject private var updater: Updater
    @Binding var unmuteGain: CGFloat
    @Binding var selectedDeviceID: AudioDeviceID
    @Binding var availableDevices: [AudioDeviceID: String]
    @State private var selectedDevice: DeviceEntry.ID? = nil
    var onDeviceSelected: (AudioDeviceID) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    private var deviceEntries: [DeviceEntry] {
        availableDevices.sorted { $0.key < $1.key }.map { DeviceEntry(id: $0.key, name: $0.value) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                MenuSection("Volume after unmute", divider: false)
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
                
                MenuVolumeSlider(value: $unmuteGain)
                    .padding(.horizontal, 12)
            }
        
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                MenuSection("Available devices", divider: false)
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 0) {
                    MenuList(deviceEntries, selection: $selectedDevice) { item, isSelected, itemClicked in
                        MenuToggle(
                            isOn: .constant(isSelected),
                            image: Image(systemName: item.name.lowercased().contains("macbook") ? "laptopcomputer" : "mic.fill")
                        ) {
                            Text(item.name)
                        } onClick: { click in
                            if !click {
                                itemClicked()
                            }
                            onDeviceSelected(item.id)
                        }
                    }
                }
            }
            
            Divider().padding(.vertical, 4)
            
            MenuCommand("Micmute settings...") {
                NSApp.sendAction(#selector(AppDelegate.showPreferences(_:)), to: nil, from: nil)
            }
        }
        .padding(.horizontal, 1)
        .onAppear {
            selectedDevice = selectedDeviceID
            onAppear()
        }
        .onChange(of: selectedDevice) { oldValue, newValue in
            if let newValue = newValue, newValue != selectedDeviceID {
                selectedDeviceID = newValue
                onDeviceSelected(newValue)
            }
        }
        .onDisappear {
            onDisappear()
        }
    }
}
