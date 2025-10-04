//
//  MenuView.swift
//  Micmute
//
//  Created by artur on 10/02/2025.
//

import SwiftUI
import CoreAudio

@MainActor
struct MainMenuView: View {
    @Binding var unmuteGain: CGFloat
    @Binding var selectedDeviceID: AudioDeviceID
    @Binding var availableDevices: [AudioDeviceID: String]
    @Binding var availableOutputDevices: [AudioDeviceID: String]
    @Binding var selectedOutputDeviceID: AudioDeviceID
    @Binding var outputVolume: CGFloat

    @State private var selectedDevice: DeviceEntry.ID? = nil
    @State private var selectedOutputDevice: DeviceEntry.ID? = nil

    @AppStorage(AppStorageEntry.menuInputSectionExpanded.rawValue) private var storedInputExpanded: Bool = true
    @AppStorage(AppStorageEntry.menuOutputSectionExpanded.rawValue) private var storedOutputExpanded: Bool = true
    @State private var isInputExpanded: Bool = true
    @State private var isOutputExpanded: Bool = true

    var onDeviceSelected: (AudioDeviceID) -> Void
    var onOutputDeviceSelected: (AudioDeviceID) -> Void
    var onOutputVolumeChange: (CGFloat) -> Void
    var onSliderEditingChanged: (Bool) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    static let preferredWidth: CGFloat = 320
    private let contentPadding: CGFloat = 14
    private let interSectionSpacing: CGFloat = 12

    private var inputDeviceEntries: [DeviceEntry] {
        deviceEntries(from: availableDevices)
    }

    private var outputDeviceEntries: [DeviceEntry] {
        deviceEntries(from: availableOutputDevices)
    }

    // MARK: - Per-input-device state and CoreAudio sync

    @State private var perInputVolume: [AudioDeviceID: CGFloat] = [:]
    @State private var perInputMute: [AudioDeviceID: Bool] = [:]
    @State private var perInputLastNonZeroVolume: [AudioDeviceID: CGFloat] = [:]

    // MARK: - Per-output-device state and CoreAudio sync

    @State private var perOutputVolume: [AudioDeviceID: CGFloat] = [:]
    @State private var perOutputMute: [AudioDeviceID: Bool] = [:]
    @State private var perOutputLastNonZeroVolume: [AudioDeviceID: CGFloat] = [:]

    // Inline editing of output percent
    @State private var editingOutputDevicePercent: AudioDeviceID? = nil
    @State private var tempOutputPercent: [AudioDeviceID: Int] = [:]
    @FocusState private var focusedOutputPercentEditor: AudioDeviceID?

    // Inline editing of input percent
    @State private var editingInputDevicePercent: AudioDeviceID? = nil
    @State private var tempInputPercent: [AudioDeviceID: Int] = [:]
    @FocusState private var focusedInputPercentEditor: AudioDeviceID?

    private struct ListenerEntry {
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }
    @State private var listeners: [AudioDeviceID: [ListenerEntry]] = [:]
    @State private var outputListeners: [AudioDeviceID: [ListenerEntry]] = [:]

    init(
        unmuteGain: Binding<CGFloat>,
        selectedDeviceID: Binding<AudioDeviceID>,
        availableDevices: Binding<[AudioDeviceID: String]>,
        availableOutputDevices: Binding<[AudioDeviceID: String]>,
        selectedOutputDeviceID: Binding<AudioDeviceID>,
        outputVolume: Binding<CGFloat>,
        onDeviceSelected: @escaping (AudioDeviceID) -> Void,
        onOutputDeviceSelected: @escaping (AudioDeviceID) -> Void,
        onOutputVolumeChange: @escaping (CGFloat) -> Void,
        onSliderEditingChanged: @escaping (Bool) -> Void,
        onAppear: @escaping () -> Void = { },
        onDisappear: @escaping () -> Void = { }
    ) {
        self._unmuteGain = unmuteGain
        self._selectedDeviceID = selectedDeviceID
        self._availableDevices = availableDevices
        self._availableOutputDevices = availableOutputDevices
        self._selectedOutputDeviceID = selectedOutputDeviceID
        self._outputVolume = outputVolume
        self.onDeviceSelected = onDeviceSelected
        self.onOutputDeviceSelected = onOutputDeviceSelected
        self.onOutputVolumeChange = onOutputVolumeChange
        self.onSliderEditingChanged = onSliderEditingChanged
        self.onAppear = onAppear
        self.onDisappear = onDisappear

        self._isInputExpanded = State(initialValue: storedInputExpanded)
        self._isOutputExpanded = State(initialValue: storedOutputExpanded)
        self._selectedOutputDevice = State(initialValue: selectedOutputDeviceID.wrappedValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: interSectionSpacing) {
                outputSection
                inputSection

                Button {
                    NSApp.sendAction(#selector(AppDelegate.showPreferences(_:)), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .hideScrollIndicators()
        .frame(width: Self.preferredWidth)
        .onAppear {
            // Usunięto activateApp(), bo aktywacja w tym momencie zrywa śledzenie menu i je zamyka.
            selectedDevice = selectedDeviceID
            selectedOutputDevice = selectedOutputDeviceID
            setupInputDevicesStateAndListeners()
            setupOutputDevicesStateAndListeners()
            onAppear()
        }
        .onChange(of: availableDevices) { _, _ in
            setupInputDevicesStateAndListeners()
        }
        .onChange(of: availableOutputDevices) { _, _ in
            setupOutputDevicesStateAndListeners()
        }
        .onChange(of: selectedDevice) { _, newValue in
            if let newValue, newValue != selectedDeviceID {
                selectedDeviceID = newValue
                onDeviceSelected(newValue)
            }
        }
        .onChange(of: selectedOutputDevice) { _, newValue in
            if let newValue, newValue != selectedOutputDeviceID {
                selectedOutputDeviceID = newValue
                onOutputDeviceSelected(newValue)
            }
        }
        .onChange(of: isInputExpanded) { _, newValue in
            if storedInputExpanded != newValue {
                storedInputExpanded = newValue
            }
        }
        .onChange(of: storedInputExpanded) { _, newValue in
            if newValue != isInputExpanded {
                isInputExpanded = newValue
            }
        }
        .onChange(of: isOutputExpanded) { _, newValue in
            if storedOutputExpanded != newValue {
                storedOutputExpanded = newValue
            }
        }
        .onChange(of: storedOutputExpanded) { _, newValue in
            if newValue != isOutputExpanded {
                isOutputExpanded = newValue
            }
        }
        .onChange(of: selectedOutputDeviceID) { _, newValue in
            if selectedOutputDevice != newValue {
                selectedOutputDevice = newValue
            }
        }
        // Synchronizacja zewnętrznych zmian głośności do cache per‑device
        .onChange(of: outputVolume) { _, newValue in
            perOutputVolume[selectedOutputDeviceID] = newValue
        }
        .onDisappear {
            tearDownInputListeners()
            tearDownOutputListeners()
            onDisappear()
        }
    }

    // MARK: - Sections (native macOS controls)

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isInputExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    // Available input devices (each with slider + mute)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if inputDeviceEntries.isEmpty {
                            Label("No input devices found", systemImage: "mic.slash.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(inputDeviceEntries) { entry in
                                    inputDeviceRow(entry: entry)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Input", systemImage: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    private func inputDeviceRow(entry: DeviceEntry) -> some View {
        let supportsVolume = hasInputVolume(entry.id)
        let supportsMute = hasInputMute(entry.id)
        let hasTrailingControls = supportsVolume || supportsMute

        let volumeBinding = Binding<Double>(
            get: {
                let value = perInputVolume[entry.id] ?? 1.0
                return Double(min(max(value, 0), 1))
            },
            set: { newValue in
                let clamped = CGFloat(min(max(newValue, 0), 1))
                setInputVolume(entry.id, clamped)
            }
        )
        let isMuted = perInputMute[entry.id] ?? false

        let currentPercent: Int = {
            let vol = perInputVolume[entry.id] ?? 1.0
            return Int((min(max(vol, 0), 1) * 100).rounded())
        }()

        let isSelected = (selectedDevice ?? selectedDeviceID) == entry.id

        return HStack(spacing: 8) {
            // Select indicator + Device name (clickable)
            Button {
                selectedDevice = entry.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .accent : .secondary)
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .frame(width: hasTrailingControls ? 150 : nil, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Selected input device" : "Set as active input device")

            if supportsVolume {
                // Slider + percent only if device supports volume
                Slider(value: volumeBinding, in: 0...1, onEditingChanged: { isEditing in
                    onSliderEditingChanged(isEditing)
                })
                .controlSize(.small)

                Group {
                    if editingInputDevicePercent == entry.id {
                        let textBinding = Binding<String>(
                            get: {
                                let value = tempInputPercent[entry.id] ?? currentPercent
                                return String(value)
                            },
                            set: { newValue in
                                let digits = newValue.filter { $0.isNumber }
                                let limited = String(digits.prefix(3))
                                let intVal = Int(limited) ?? 0
                                tempInputPercent[entry.id] = max(0, min(100, intVal))
                            }
                        )

                        TextField("", text: textBinding, onCommit: {
                            commitInputPercent(for: entry.id)
                        })
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 42, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($focusedInputPercentEditor, equals: entry.id)
                        .onAppear {
                            DispatchQueue.main.async {
                                focusedInputPercentEditor = entry.id
                            }
                        }
                        .onChange(of: focusedInputPercentEditor) { _, newFocus in
                            if editingInputDevicePercent == entry.id, newFocus != entry.id {
                                commitInputPercent(for: entry.id)
                            }
                        }
                    } else {
                        Text("\(currentPercent)%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                            .onTapGesture(count: 2) {
                                editingInputDevicePercent = entry.id
                                tempInputPercent[entry.id] = currentPercent
                                focusedInputPercentEditor = entry.id
                            }
                            .help("Double-click to edit")
                    }
                }
            }

            if supportsMute {
                // Mute/Unmute only if device supports mute
                Button {
                    toggleInputMute(entry.id)
                } label: {
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                }
                .help(isMuted ? "Unmute" : "Mute")
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if !hasTrailingControls {
                Spacer(minLength: 0)
            }
        }
        .opacity(isSelected ? 1.0 : 0.7)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isOutputExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    // Available output devices (name + per-device slider + mute button)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if outputDeviceEntries.isEmpty {
                            Label("No output devices found", systemImage: "questionmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(outputDeviceEntries) { entry in
                                    outputDeviceRow(entry: entry)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Output", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    private func outputDeviceRow(entry: DeviceEntry) -> some View {
        let isSelected = (selectedOutputDevice ?? selectedOutputDeviceID) == entry.id
        let supportsVolume = hasOutputVolume(entry.id)
        let supportsMute = hasOutputMute(entry.id)
        let hasTrailingControls = supportsVolume || supportsMute

        let volumeBinding = Binding<Double>(
            get: {
                let value = perOutputVolume[entry.id] ?? 1.0
                return Double(min(max(value, 0), 1))
            },
            set: { newValue in
                let clamped = CGFloat(min(max(newValue, 0), 1))
                setOutputVolume(entry.id, clamped)
            }
        )

        let currentPercent: Int = {
            let vol = perOutputVolume[entry.id] ?? 1.0
            return Int((min(max(vol, 0), 1) * 100).rounded())
        }()

        let isMuted = perOutputMute[entry.id] ?? false

        return HStack(spacing: 8) {
            Button {
                selectedOutputDevice = entry.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .accent : .secondary)
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .frame(width: hasTrailingControls ? 150 : nil, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Selected output device" : "Set as active output device")

            if supportsVolume {
                // Slider + percent only if device supports volume
                Slider(value: volumeBinding, in: 0...1, onEditingChanged: { isEditing in
                    onSliderEditingChanged(isEditing)
                })
                .controlSize(.small)

                Group {
                    if editingOutputDevicePercent == entry.id {
                        let textBinding = Binding<String>(
                            get: {
                                let value = tempOutputPercent[entry.id] ?? currentPercent
                                return String(value)
                            },
                            set: { newValue in
                                // allow only digits and clamp to 0...100, limit to 3 chars
                                let digits = newValue.filter { $0.isNumber }
                                let limited = String(digits.prefix(3))
                                let intVal = Int(limited) ?? 0
                                tempOutputPercent[entry.id] = max(0, min(100, intVal))
                            }
                        )

                        TextField("", text: textBinding, onCommit: {
                            commitOutputPercent(for: entry.id)
                        })
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 42, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($focusedOutputPercentEditor, equals: entry.id)
                        .onAppear {
                            // Ustaw fokus po wejściu w tryb edycji
                            DispatchQueue.main.async {
                                focusedOutputPercentEditor = entry.id
                            }
                        }
                        .onChange(of: focusedOutputPercentEditor) { _, newFocus in
                            // Zatwierdź przy utracie fokusu
                            if editingOutputDevicePercent == entry.id, newFocus != entry.id {
                                commitOutputPercent(for: entry.id)
                            }
                        }
                    } else {
                        Text("\(currentPercent)%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                            .onTapGesture(count: 2) {
                                // start editing
                                editingOutputDevicePercent = entry.id
                                tempOutputPercent[entry.id] = currentPercent
                                focusedOutputPercentEditor = entry.id
                            }
                            .help("Double-click to edit")
                    }
                }
            }

            if supportsMute {
                // Mute/Unmute only if device supports mute
                Button {
                    toggleOutputMute(entry.id)
                } label: {
                    if isMuted {
                        Image(systemName: "speaker.slash.fill")
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                }
                .help(isMuted ? "Unmute" : "Mute")
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if !hasTrailingControls {
                Spacer(minLength: 0)
            }
        }
        .opacity(isSelected ? 1.0 : 0.7)
    }

    // MARK: - Helpers

    private func commitOutputPercent(for deviceID: AudioDeviceID) {
        let raw = tempOutputPercent[deviceID] ?? 0
        let clamped = max(0, min(100, raw))
        let scalar = CGFloat(clamped) / 100.0
        setOutputVolume(deviceID, scalar)
        // wyczyść tryb edycji
        editingOutputDevicePercent = nil
        focusedOutputPercentEditor = nil
    }

    private func commitInputPercent(for deviceID: AudioDeviceID) {
        let raw = tempInputPercent[deviceID] ?? 0
        let clamped = max(0, min(100, raw))
        let scalar = CGFloat(clamped) / 100.0
        setInputVolume(deviceID, scalar)
        editingInputDevicePercent = nil
        focusedInputPercentEditor = nil
    }

    private func deviceEntries(from devices: [AudioDeviceID: String]) -> [DeviceEntry] {
        devices
            .map { DeviceEntry(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - CoreAudio helpers for input devices (volume + mute) and listeners

private extension MainMenuView {
    // 'vmvc' selector used by HAL for virtual master scalar volume when available
    static let virtualMasterScalarVolumeSelector = AudioObjectPropertySelector(0x766D7663) // 'vmvc'

    func setupInputDevicesStateAndListeners() {
        // Remove listeners for devices that disappeared
        let currentIDs = Set(availableDevices.keys)
        for (deviceID, entries) in listeners {
            if !currentIDs.contains(deviceID) {
                removeListeners(for: deviceID, entries: entries)
                listeners.removeValue(forKey: deviceID)
                perInputVolume.removeValue(forKey: deviceID)
                perInputMute.removeValue(forKey: deviceID)
                perInputLastNonZeroVolume.removeValue(forKey: deviceID)
            }
        }

        // Ensure state + listeners for all current devices
        for deviceID in currentIDs {
            // Load initial volume and mute
            let vol = loadInputVolume(for: deviceID) ?? 1.0
            perInputVolume[deviceID] = vol
            if vol > 0 {
                perInputLastNonZeroVolume[deviceID] = vol
            }

            if let mute = loadInputMute(for: deviceID) {
                perInputMute[deviceID] = mute
            } else {
                // If device has no mute property, infer muted from volume==0
                perInputMute[deviceID] = (vol <= 0.0001)
            }

            // Register listeners if not yet registered
            if listeners[deviceID] == nil {
                var newEntries: [ListenerEntry] = []

                if var volAddress = inputVolumePropertyAddress(for: deviceID) {
                    let block: AudioObjectPropertyListenerBlock = { _, _ in
                        let newVol = self.loadInputVolume(for: deviceID) ?? self.perInputVolume[deviceID] ?? 1.0
                        Task { @MainActor in
                            self.perInputVolume[deviceID] = newVol
                            if newVol > 0 {
                                self.perInputLastNonZeroVolume[deviceID] = newVol
                            }
                            // For devices without mute property, derive mute from volume
                            if self.loadInputMute(for: deviceID) == nil {
                                self.perInputMute[deviceID] = (newVol <= 0.0001)
                            }
                        }
                    }
                    AudioObjectAddPropertyListenerBlock(deviceID, &volAddress, DispatchQueue.main, block)
                    newEntries.append(ListenerEntry(address: volAddress, block: block))
                }

                if var muteAddress = inputMutePropertyAddress(for: deviceID), AudioObjectHasProperty(deviceID, &muteAddress) {
                    let block: AudioObjectPropertyListenerBlock = { _, _ in
                        let newMute = self.loadInputMute(for: deviceID)
                        Task { @MainActor in
                            if let newMute {
                                self.perInputMute[deviceID] = newMute
                            }
                        }
                    }
                    AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
                    newEntries.append(ListenerEntry(address: muteAddress, block: block))
                }

                if !newEntries.isEmpty {
                    listeners[deviceID] = newEntries
                }
            }
        }
    }

    func tearDownInputListeners() {
        for (deviceID, entries) in listeners {
            removeListeners(for: deviceID, entries: entries)
        }
        listeners.removeAll()
    }

    private func removeListeners(for deviceID: AudioDeviceID, entries: [ListenerEntry]) {
        for entry in entries {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, entry.block)
        }
    }

    // MARK: Volume (Input)

    func inputVolumePropertyAddress(for deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        var vmvc = AudioObjectPropertyAddress(
            mSelector: Self.virtualMasterScalarVolumeSelector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &vmvc) {
            return vmvc
        }

        var scalar = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &scalar) {
            return scalar
        }

        return nil
    }

    func loadInputVolume(for deviceID: AudioDeviceID) -> CGFloat? {
        guard deviceID != kAudioObjectUnknown,
              var address = inputVolumePropertyAddress(for: deviceID) else {
            return nil
        }
        var volume: Float32 = 1.0
        var size = UInt32(MemoryLayout.size(ofValue: volume))
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return CGFloat(min(max(volume, 0), 1))
    }

    func setInputVolume(_ deviceID: AudioDeviceID, _ volume: CGFloat) {
        guard deviceID != kAudioObjectUnknown,
              var address = inputVolumePropertyAddress(for: deviceID) else {
            return
        }
        var clamped: Float32 = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout.size(ofValue: clamped))
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped)
        if status == noErr {
            perInputVolume[deviceID] = CGFloat(clamped)
            if clamped > 0 {
                perInputLastNonZeroVolume[deviceID] = CGFloat(clamped)
            }
        } else {
            // Ignore errors silently in UI
        }
    }

    // MARK: Mute (Input)

    func inputMutePropertyAddress(for deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        return address
    }

    func loadInputMute(for deviceID: AudioDeviceID) -> Bool? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var address = inputMutePropertyAddress(for: deviceID)!
        if !AudioObjectHasProperty(deviceID, &address) { return nil }

        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: muteValue))
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue)
        guard status == noErr else { return nil }
        return muteValue != 0
    }

    func setInputMute(_ deviceID: AudioDeviceID, _ mute: Bool) -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var address = inputMutePropertyAddress(for: deviceID)!
        if !AudioObjectHasProperty(deviceID, &address) { return false }

        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        if status == noErr {
            perInputMute[deviceID] = mute
            return true
        }
        return false
    }

    func toggleInputMute(_ deviceID: AudioDeviceID) {
        let supportsMute: Bool = {
            var addr = inputMutePropertyAddress(for: deviceID)!
            return AudioObjectHasProperty(deviceID, &addr)
        }()

        if supportsMute {
            let current = loadInputMute(for: deviceID) ?? (perInputMute[deviceID] ?? false)
            let success = setInputMute(deviceID, !current)
            if success, !current == false {
                // If unmuting, optionally restore last non-zero volume
                if let last = perInputLastNonZeroVolume[deviceID], last > 0 {
                    setInputVolume(deviceID, last)
                } else {
                    // fallback to unmuteGain when no previous volume known
                    setInputVolume(deviceID, unmuteGain)
                }
            }
        } else {
            // Fallback by volume
            let isCurrentlyMuted = (perInputVolume[deviceID] ?? 0) <= 0.0001
            if isCurrentlyMuted {
                let restore = perInputLastNonZeroVolume[deviceID] ?? unmuteGain
                setInputVolume(deviceID, restore)
                perInputMute[deviceID] = false
            } else {
                if let current = perInputVolume[deviceID], current > 0 {
                    perInputLastNonZeroVolume[deviceID] = current
                }
                setInputVolume(deviceID, 0.0)
                perInputMute[deviceID] = true
            }
        }
    }

    // UI helpers: capability checks (Input)
    func hasInputVolume(_ deviceID: AudioDeviceID) -> Bool {
        return inputVolumePropertyAddress(for: deviceID) != nil
    }

    func hasInputMute(_ deviceID: AudioDeviceID) -> Bool {
        guard var address = inputMutePropertyAddress(for: deviceID) else { return false }
        return AudioObjectHasProperty(deviceID, &address)
    }
}

// MARK: - CoreAudio helpers for OUTPUT devices (volume + mute) and listeners

private extension MainMenuView {
    func setupOutputDevicesStateAndListeners() {
        // Remove listeners for devices that disappeared
        let currentIDs = Set(availableOutputDevices.keys)
        for (deviceID, entries) in outputListeners {
            if !currentIDs.contains(deviceID) {
                removeListeners(for: deviceID, entries: entries)
                outputListeners.removeValue(forKey: deviceID)
                perOutputVolume.removeValue(forKey: deviceID)
                perOutputMute.removeValue(forKey: deviceID)
                perOutputLastNonZeroVolume.removeValue(forKey: deviceID)
            }
        }

        // Ensure state + listeners for all current output devices
        for deviceID in currentIDs {
            // Load initial volume and mute
            let vol = loadOutputVolume(for: deviceID) ?? 1.0
            perOutputVolume[deviceID] = vol
            if vol > 0 {
                perOutputLastNonZeroVolume[deviceID] = vol
            }

            if let mute = loadOutputMute(for: deviceID) {
                perOutputMute[deviceID] = mute
            } else {
                perOutputMute[deviceID] = (vol <= 0.0001)
            }

            // Register listeners if not yet registered
            if outputListeners[deviceID] == nil {
                var newEntries: [ListenerEntry] = []

                if var volAddress = outputVolumePropertyAddress(for: deviceID) {
                    let block: AudioObjectPropertyListenerBlock = { _, _ in
                        let newVol = self.loadOutputVolume(for: deviceID) ?? self.perOutputVolume[deviceID] ?? 1.0
                        Task { @MainActor in
                            self.perOutputVolume[deviceID] = newVol
                            if newVol > 0 {
                                self.perOutputLastNonZeroVolume[deviceID] = newVol
                            }
                            if self.loadOutputMute(for: deviceID) == nil {
                                self.perOutputMute[deviceID] = (newVol <= 0.0001)
                            }
                        }
                    }
                    AudioObjectAddPropertyListenerBlock(deviceID, &volAddress, DispatchQueue.main, block)
                    newEntries.append(ListenerEntry(address: volAddress, block: block))
                }

                if var muteAddress = outputMutePropertyAddress(for: deviceID), AudioObjectHasProperty(deviceID, &muteAddress) {
                    let block: AudioObjectPropertyListenerBlock = { _, _ in
                        let newMute = self.loadOutputMute(for: deviceID)
                        Task { @MainActor in
                            if let newMute {
                                self.perOutputMute[deviceID] = newMute
                            }
                        }
                    }
                    AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
                    newEntries.append(ListenerEntry(address: muteAddress, block: block))
                }

                if !newEntries.isEmpty {
                    outputListeners[deviceID] = newEntries
                }
            }
        }
    }

    func tearDownOutputListeners() {
        for (deviceID, entries) in outputListeners {
            removeListeners(for: deviceID, entries: entries)
        }
        outputListeners.removeAll()
    }

    // MARK: Volume (Output)

    func outputVolumePropertyAddress(for deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        var vmvc = AudioObjectPropertyAddress(
            mSelector: Self.virtualMasterScalarVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &vmvc) {
            return vmvc
        }

        var scalar = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &scalar) {
            return scalar
        }

        return nil
    }

    func loadOutputVolume(for deviceID: AudioDeviceID) -> CGFloat? {
        guard deviceID != kAudioObjectUnknown,
              var address = outputVolumePropertyAddress(for: deviceID) else {
            return nil
        }
        var volume: Float32 = 1.0
        var size = UInt32(MemoryLayout.size(ofValue: volume))
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return CGFloat(min(max(volume, 0), 1))
    }

    func setOutputVolume(_ deviceID: AudioDeviceID, _ volume: CGFloat) {
        guard deviceID != kAudioObjectUnknown,
              var address = outputVolumePropertyAddress(for: deviceID) else {
            return
        }
        var clamped: Float32 = Float32(min(max(volume, 0), 1))
        let size = UInt32(MemoryLayout.size(ofValue: clamped))
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped)
        if status == noErr {
            perOutputVolume[deviceID] = CGFloat(clamped)
            if clamped > 0 {
                perOutputLastNonZeroVolume[deviceID] = CGFloat(clamped)
            }
            // jeśli to wybrane urządzenie, przekaż w górę (utrzymujemy dotychczasowe API)
            if deviceID == selectedOutputDeviceID {
                onOutputVolumeChange(CGFloat(clamped))
            }
        } else {
            // Ignore errors silently in UI
        }
    }

    // MARK: Mute (Output)

    func outputMutePropertyAddress(for deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return address
    }

    func loadOutputMute(for deviceID: AudioDeviceID) -> Bool? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var address = outputMutePropertyAddress(for: deviceID)!
        if !AudioObjectHasProperty(deviceID, &address) { return nil }

        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: muteValue))
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue)
        guard status == noErr else { return nil }
        return muteValue != 0
    }

    func setOutputMute(_ deviceID: AudioDeviceID, _ mute: Bool) -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var address = outputMutePropertyAddress(for: deviceID)!
        if !AudioObjectHasProperty(deviceID, &address) { return false }

        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        if status == noErr {
            perOutputMute[deviceID] = mute
            return true
        }
        return false
    }

    func toggleOutputMute(_ deviceID: AudioDeviceID) {
        let supportsMute: Bool = {
            var addr = outputMutePropertyAddress(for: deviceID)!
            return AudioObjectHasProperty(deviceID, &addr)
        }()

        if supportsMute {
            let current = loadOutputMute(for: deviceID) ?? (perOutputMute[deviceID] ?? false)
            let success = setOutputMute(deviceID, !current)
            if success, !current == false {
                // If unmuting, restore last non-zero volume or fallback
                if let last = perOutputLastNonZeroVolume[deviceID], last > 0 {
                    setOutputVolume(deviceID, last)
                } else {
                    setOutputVolume(deviceID, unmuteGain)
                }
            }
        } else {
            // Fallback by volume
            let isCurrentlyMuted = (perOutputVolume[deviceID] ?? 0) <= 0.0001
            if isCurrentlyMuted {
                let restore = perOutputLastNonZeroVolume[deviceID] ?? unmuteGain
                setOutputVolume(deviceID, restore)
                perOutputMute[deviceID] = false
            } else {
                if let current = perOutputVolume[deviceID], current > 0 {
                    perOutputLastNonZeroVolume[deviceID] = current
                }
                setOutputVolume(deviceID, 0.0)
                perOutputMute[deviceID] = true
            }
        }
    }

    // UI helpers: capability checks (Output)
    func hasOutputVolume(_ deviceID: AudioDeviceID) -> Bool {
        return outputVolumePropertyAddress(for: deviceID) != nil
    }

    func hasOutputMute(_ deviceID: AudioDeviceID) -> Bool {
        guard var address = outputMutePropertyAddress(for: deviceID) else { return false }
        return AudioObjectHasProperty(deviceID, &address)
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
