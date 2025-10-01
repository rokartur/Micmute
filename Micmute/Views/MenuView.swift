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
    @EnvironmentObject private var perAppVolumeManager: PerAppAudioVolumeManager
    @Binding var unmuteGain: CGFloat
    @Binding var selectedDeviceID: AudioDeviceID
    @Binding var availableDevices: [AudioDeviceID: String]
    @State private var sliderGain: CGFloat = 1.0
    @State private var selectedDevice: DeviceEntry.ID? = nil
    var onDeviceSelected: (AudioDeviceID) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    static let preferredWidth: CGFloat = 320
    private let contentPadding: CGFloat = 16
    private let interSectionSpacing: CGFloat = 16

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
        ScrollView {
            VStack(alignment: .leading, spacing: interSectionSpacing) {
                ApplicationVolumeListView(manager: perAppVolumeManager)

                Divider()

                volumeAfterUnmuteSection

                Divider()

                availableDevicesSection

                Divider()

                MenuCommand("Micmute settings...") {
                    NSApp.sendAction(#selector(AppDelegate.showPreferences(_:)), to: nil, from: nil)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentPadding)
            .padding(.vertical, contentPadding)
        }
        .hideScrollIndicators()
        .frame(width: Self.preferredWidth)
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

    private var volumeAfterUnmuteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSection("Volume after unmute", divider: false)

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
        }
    }

    private var availableDevicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuSection("Available devices", divider: false)

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
}

private extension View {
    @ViewBuilder
    func hideScrollIndicators() -> some View {
        if #available(macOS 13.0, *) {
            scrollIndicators(.hidden)
        } else {
            self
        }
    }
}
