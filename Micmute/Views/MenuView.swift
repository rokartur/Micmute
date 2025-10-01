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
    @State private var sliderGain: CGFloat = 1.0
    @State private var selectedDevice: DeviceEntry.ID? = nil
    var onDeviceSelected: (AudioDeviceID) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    private var deviceEntries: [DeviceEntry] {
        availableDevices.sorted { $0.key < $1.key }.map { DeviceEntry(id: $0.key, name: $0.value) }
    }
    
    init(
        unmuteGain: Binding<CGFloat>,
        selectedDeviceID: Binding<AudioDeviceID>,
        availableDevices: Binding<[AudioDeviceID: String]>,
        onDeviceSelected: @escaping (AudioDeviceID) -> Void,
        onAppear: @escaping () -> Void = { },
        onDisappear: @escaping () -> Void = { }
    ) {
        self._unmuteGain = unmuteGain
        self._selectedDeviceID = selectedDeviceID
        self._availableDevices = availableDevices
        self.onDeviceSelected = onDeviceSelected
        self.onAppear = onAppear
        self.onDisappear = onDisappear
        self._sliderGain = State(initialValue: unmuteGain.wrappedValue)
    }

    private var sliderGainPercentage: String {
        let clampedGain = min(max(sliderGain, .zero), CGFloat(1))
        let percentValue = Int((clampedGain * 100).rounded())
        return "\(percentValue)%"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                MenuSection("Volume after unmute", divider: false)
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
                
                HStack(alignment: .center, spacing: 8) {
                    MenuVolumeSlider(value: $sliderGain)
                        .layoutPriority(1)
                        .onChange(of: sliderGain) { _, newValue in
                            unmuteGain = newValue
                        }
                    Text(sliderGainPercentage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
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
            sliderGain = unmuteGain
            onAppear()
        }
        .onChange(of: selectedDevice) { oldValue, newValue in
            if let newValue = newValue, newValue != selectedDeviceID {
                selectedDeviceID = newValue
                onDeviceSelected(newValue)
            }
        }
        .onChange(of: unmuteGain) { _, newValue in
            if sliderGain != newValue {
                sliderGain = newValue
            }
        }
        .onDisappear {
            onDisappear()
        }
    }
}
