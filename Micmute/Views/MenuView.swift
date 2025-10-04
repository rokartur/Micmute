//
//  MenuView.swift
//  Micmute
//
//  Created by artur on 10/02/2025.
//

import SwiftUI
import CoreAudio
import Carbon.HIToolbox

@MainActor
struct MainMenuView: View {
    @Binding var unmuteGain: CGFloat
    @Binding var selectedDeviceID: AudioDeviceID
    @Binding var availableDevices: [AudioDeviceID: String]
    @Binding var availableOutputDevices: [AudioDeviceID: String]
    @Binding var selectedOutputDeviceID: AudioDeviceID
    @Binding var outputVolume: CGFloat

    // Lokalny, natychmiastowy stan zaznaczenia (naprawia opóźnienie przy Bindingach/AppStorage)
    @State private var localSelectedInputID: AudioDeviceID = kAudioObjectUnknown
    @State private var localSelectedOutputID: AudioDeviceID = kAudioObjectUnknown

    var onDeviceSelected: (AudioDeviceID) -> Void
    var onOutputDeviceSelected: (AudioDeviceID) -> Void
    var onOutputVolumeChange: (CGFloat) -> Void
    var onSliderEditingChanged: (Bool) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    static let preferredWidth: CGFloat = 320
    private let contentPadding: CGFloat = 14
    private let interSectionSpacing: CGFloat = 12

    private let volumeEpsilon: CGFloat = 0.005
    private let debounceInterval: TimeInterval = 0.5

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

    // UI drag tracking + debounce (input)
    @State private var draggingInputDevices: Set<AudioDeviceID> = []
    @State private var inputSetTimers: [AudioDeviceID: DispatchSourceTimer] = [:]
    @State private var inputPendingVolume: [AudioDeviceID: CGFloat] = [:]
    @State private var lastInputSetByUI: [AudioDeviceID: CGFloat] = [:]

    // MARK: - Per-output-device state and CoreAudio sync

    @State private var perOutputVolume: [AudioDeviceID: CGFloat] = [:]
    @State private var perOutputMute: [AudioDeviceID: Bool] = [:]
    @State private var perOutputLastNonZeroVolume: [AudioDeviceID: CGFloat] = [:]

    // UI drag tracking + debounce (output)
    @State private var draggingOutputDevices: Set<AudioDeviceID> = []
    @State private var outputSetTimers: [AudioDeviceID: DispatchSourceTimer] = [:]
    @State private var outputPendingVolume: [AudioDeviceID: CGFloat] = [:]
    @State private var lastOutputSetByUI: [AudioDeviceID: CGFloat] = [:]

    // Inline editing of output percent
    @State private var editingOutputDevicePercent: AudioDeviceID? = nil
    @State private var tempOutputPercent: [AudioDeviceID: Int] = [:]
    @FocusState private var focusedOutputPercentEditor: AudioDeviceID?

    // Inline editing of input percent
    @State private var editingInputDevicePercent: AudioDeviceID? = nil
    @State private var tempInputPercent: [AudioDeviceID: Int] = [:]
    @FocusState private var focusedInputPercentEditor: AudioDeviceID?

    // Hover states for device selection buttons
    @State private var hoveredInputButtons: Set<AudioDeviceID> = []
    @State private var hoveredOutputButtons: Set<AudioDeviceID> = []

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

        // Inicjalizuj lokalne zaznaczenie na podstawie przekazanych Bindingów
        self._localSelectedInputID = State(initialValue: selectedDeviceID.wrappedValue)
        self._localSelectedOutputID = State(initialValue: selectedOutputDeviceID.wrappedValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: interSectionSpacing) {
                outputSection
                
                Divider()
                
                inputSection

                Button {
                    NSApp.sendAction(#selector(AppDelegate.showPreferences(_:)), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hideScrollIndicators()
        .frame(width: Self.preferredWidth)
        .onAppear {
            // Upewnij się, że lokalny stan jest zsynchronizowany przy otwarciu
            localSelectedInputID = selectedDeviceID
            localSelectedOutputID = selectedOutputDeviceID

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
        .onChange(of: outputVolume) { _, newValue in
            let current = perOutputVolume[selectedOutputDeviceID] ?? 1.0
            if !approxEqual(current, newValue, eps: volumeEpsilon) {
                perOutputVolume[selectedOutputDeviceID] = newValue
            }
        }
        // Synchronizacja lokalnych zaznaczeń z zewnętrznymi Bindingami (gdy zmienią się „z zewnątrz”)
        .onChange(of: selectedDeviceID) { _, newValue in
            if localSelectedInputID != newValue {
                localSelectedInputID = newValue
            }
        }
        .onChange(of: selectedOutputDeviceID) { _, newValue in
            if localSelectedOutputID != newValue {
                localSelectedOutputID = newValue
            }
        }
        .onDisappear {
            tearDownInputListeners()
            tearDownOutputListeners()
            cancelAllTimers()
            onDisappear()
        }
    }

    // MARK: - Sections

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Statyczny nagłówek sekcji (bez możliwość zwijania)
            Label("Input", systemImage: "mic.fill")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
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
            .padding(.top, 2)
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
                perInputVolume[entry.id] = clamped
                let isDragging = draggingInputDevices.contains(entry.id)
                debouncedSetInputVolume(entry.id, clamped, isEditing: isDragging)
            }
        )
        let isMuted = perInputMute[entry.id] ?? false

        let currentPercent: Int = {
            let vol = perInputVolume[entry.id] ?? 1.0
            return Int((min(max(vol, 0), 1) * 100).rounded())
        }()

        let isSelected = localSelectedInputID == entry.id
        let isHovered = hoveredInputButtons.contains(entry.id)

        return VStack(alignment: .leading) {
            // Górny rząd: przycisk wyboru + nazwa
            Button {
                if localSelectedInputID != entry.id {
                    localSelectedInputID = entry.id
                    selectedDeviceID = entry.id
                    onDeviceSelected(entry.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .accent : .secondary)
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Selected input device" : "Set as active input device")

            // Dolny rząd: suwak + procent + mute (jeśli dostępne)
            if hasTrailingControls {
                HStack(spacing: 8) {
                    if supportsVolume {
                        Slider(value: volumeBinding, in: 0...1, onEditingChanged: { isEditing in
                            onSliderEditingChanged(isEditing)
                            if isEditing {
                                draggingInputDevices.insert(entry.id)
                            } else {
                                draggingInputDevices.remove(entry.id)
                                if let final = perInputVolume[entry.id] {
                                    debouncedSetInputVolume(entry.id, final, isEditing: false)
                                }
                            }
                        })
                        .controlSize(.small)
                        .frame(minWidth: 75, maxWidth: .infinity)

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
                                .background(
                                    EscapeKeyHandler {
                                        commitInputPercent(for: entry.id)
                                    }
                                )
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
                        Button {
                            toggleInputMute(entry.id)
                        } label: {
                            if isMuted {
                                Image(systemName: "mic.slash.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "mic.fill")
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .help(isMuted ? "Unmute" : "Mute")
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .padding(.top, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredInputButtons.insert(entry.id)
            } else {
                hoveredInputButtons.remove(entry.id)
            }
        }
        // Wybór urządzenia po kliknięciu w dowolnym miejscu wiersza
        .onTapGesture {
            if localSelectedInputID != entry.id {
                localSelectedInputID = entry.id
                selectedDeviceID = entry.id
                onDeviceSelected(entry.id)
            }
        }
        .opacity(isSelected ? 1.0 : 0.7)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Statyczny nagłówek sekcji (bez możliwość zwijania)
            Label("Output", systemImage: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
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
    }

    private func outputDeviceRow(entry: DeviceEntry) -> some View {
        let isSelected = localSelectedOutputID == entry.id
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
                perOutputVolume[entry.id] = clamped
                let isDragging = draggingOutputDevices.contains(entry.id)
                debouncedSetOutputVolume(entry.id, clamped, isEditing: isDragging)
            }
        )

        let currentPercent: Int = {
            let vol = perOutputVolume[entry.id] ?? 1.0
            return Int((min(max(vol, 0), 1) * 100).rounded())
        }()

        let isMuted = perOutputMute[entry.id] ?? false
        let isHovered = hoveredOutputButtons.contains(entry.id)

        return VStack(alignment: .leading, spacing: 6) {
            // Górny rząd: przycisk wyboru + nazwa
            Button {
                if localSelectedOutputID != entry.id {
                    localSelectedOutputID = entry.id
                    selectedOutputDeviceID = entry.id
                    onOutputDeviceSelected(entry.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .accent : .secondary)
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Selected output device" : "Set as active output device")

            // Dolny rząd: suwak + procent + mute (jeśli dostępne)
            if hasTrailingControls {
                HStack(spacing: 8) {
                    if supportsVolume {
                        Slider(value: volumeBinding, in: 0...1, onEditingChanged: { isEditing in
                            onSliderEditingChanged(isEditing)
                            if isEditing {
                                draggingOutputDevices.insert(entry.id)
                            } else {
                                draggingOutputDevices.remove(entry.id)
                                if let final = perOutputVolume[entry.id] {
                                    debouncedSetOutputVolume(entry.id, final, isEditing: false)
                                }
                            }
                        })
                        .controlSize(.small)
                        .frame(minWidth: 75, maxWidth: .infinity)

                        Group {
                            if editingOutputDevicePercent == entry.id {
                                let textBinding = Binding<String>(
                                    get: {
                                        let value = tempOutputPercent[entry.id] ?? currentPercent
                                        return String(value)
                                    },
                                    set: { newValue in
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
                                    DispatchQueue.main.async {
                                        focusedOutputPercentEditor = entry.id
                                    }
                                }
                                .onChange(of: focusedOutputPercentEditor) { _, newFocus in
                                    if editingOutputDevicePercent == entry.id, newFocus != entry.id {
                                        commitOutputPercent(for: entry.id)
                                    }
                                }
                                .background(
                                    EscapeKeyHandler {
                                        commitOutputPercent(for: entry.id)
                                    }
                                )
                            } else {
                                Text("\(currentPercent)%")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                                    .onTapGesture(count: 2) {
                                        editingOutputDevicePercent = entry.id
                                        tempOutputPercent[entry.id] = currentPercent
                                        focusedOutputPercentEditor = entry.id
                                    }
                                    .help("Double-click to edit")
                            }
                        }
                    }

                    if supportsMute {
                        Button {
                            toggleOutputMute(entry.id)
                        } label: {
                            if isMuted {
                                Image(systemName: "speaker.slash.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "speaker.wave.2.fill")
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .help(isMuted ? "Unmute" : "Mute")
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .padding(.top, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredOutputButtons.insert(entry.id)
            } else {
                hoveredOutputButtons.remove(entry.id)
            }
        }
        // Wybór urządzenia po kliknięciu w dowolnym miejscu wiersza
        .onTapGesture {
            if localSelectedOutputID != entry.id {
                localSelectedOutputID = entry.id
                selectedOutputDeviceID = entry.id
                onOutputDeviceSelected(entry.id)
            }
        }
        .opacity(isSelected ? 1.0 : 0.7)
    }

    // MARK: - Helpers

    private func commitOutputPercent(for deviceID: AudioDeviceID) {
        let raw = tempOutputPercent[deviceID] ?? 0
        let clamped = max(0, min(100, raw))
        let scalar = CGFloat(clamped) / 100.0
        cancelTimer(for: deviceID, output: true)
        setOutputVolume(deviceID, scalar)
        editingOutputDevicePercent = nil
        focusedOutputPercentEditor = nil
    }

    private func commitInputPercent(for deviceID: AudioDeviceID) {
        let raw = tempInputPercent[deviceID] ?? 0
        let clamped = max(0, min(100, raw))
        let scalar = CGFloat(clamped) / 100.0
        cancelTimer(for: deviceID, output: false)
        setInputVolume(deviceID, scalar)
        editingInputDevicePercent = nil
        focusedInputPercentEditor = nil
    }

    private func deviceEntries(from devices: [AudioDeviceID: String]) -> [DeviceEntry] {
        devices
            .map { DeviceEntry(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Debounce helpers

    private func debouncedSetOutputVolume(_ deviceID: AudioDeviceID, _ volume: CGFloat, isEditing: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        if !isEditing {
            cancelTimer(for: deviceID, output: true)
            setOutputVolume(deviceID, volume)
            return
        }
        outputPendingVolume[deviceID] = volume
        if let t = outputSetTimers.removeValue(forKey: deviceID) {
            t.cancel()
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + debounceInterval, repeating: .never)
        timer.setEventHandler {
            guard let pending = self.outputPendingVolume[deviceID] else { return }
            self.setOutputVolume(deviceID, pending)
            self.outputPendingVolume.removeValue(forKey: deviceID)
            self.outputSetTimers.removeValue(forKey: deviceID)?.cancel()
        }
        outputSetTimers[deviceID] = timer
        timer.resume()
    }

    private func debouncedSetInputVolume(_ deviceID: AudioDeviceID, _ volume: CGFloat, isEditing: Bool) {
        guard deviceID != kAudioObjectUnknown else { return }
        if !isEditing {
            cancelTimer(for: deviceID, output: false)
            setInputVolume(deviceID, volume)
            return
        }
        inputPendingVolume[deviceID] = volume
        if let t = inputSetTimers.removeValue(forKey: deviceID) {
            t.cancel()
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + debounceInterval, repeating: .never)
        timer.setEventHandler {
            guard let pending = self.inputPendingVolume[deviceID] else { return }
            self.setInputVolume(deviceID, pending)
            self.inputPendingVolume.removeValue(forKey: deviceID)
            self.inputSetTimers.removeValue(forKey: deviceID)?.cancel()
        }
        inputSetTimers[deviceID] = timer
        timer.resume()
    }

    private func cancelTimer(for deviceID: AudioDeviceID, output: Bool) {
        if output {
            if let t = outputSetTimers.removeValue(forKey: deviceID) {
                t.cancel()
            }
            outputPendingVolume.removeValue(forKey: deviceID)
        } else {
            if let t = inputSetTimers.removeValue(forKey: deviceID) {
                t.cancel()
            }
            inputPendingVolume.removeValue(forKey: deviceID)
        }
    }

    private func cancelAllTimers() {
        for (_, t) in outputSetTimers { t.cancel() }
        for (_, t) in inputSetTimers { t.cancel() }
        outputSetTimers.removeAll()
        inputSetTimers.removeAll()
        outputPendingVolume.removeAll()
        inputPendingVolume.removeAll()
    }

    private func approxEqual(_ a: CGFloat, _ b: CGFloat, eps: CGFloat) -> Bool {
        return abs(a - b) <= eps
    }
}

// MARK: - CoreAudio helpers (input)

private extension MainMenuView {
    static let virtualMasterScalarVolumeSelector = AudioObjectPropertySelector(0x766D7663) // 'vmvc'

    func setupInputDevicesStateAndListeners() {
        let currentIDs = Set(availableDevices.keys)
        for (deviceID, entries) in listeners {
            if !currentIDs.contains(deviceID) {
                removeListeners(for: deviceID, entries: entries)
                listeners.removeValue(forKey: deviceID)
                perInputVolume.removeValue(forKey: deviceID)
                perInputMute.removeValue(forKey: deviceID)
                perInputLastNonZeroVolume.removeValue(forKey: deviceID)
                lastInputSetByUI.removeValue(forKey: deviceID)
                cancelTimer(for: deviceID, output: false)
            }
        }

        for deviceID in currentIDs {
            let vol = loadInputVolume(for: deviceID) ?? 1.0
            perInputVolume[deviceID] = vol
            if vol > 0 {
                perInputLastNonZeroVolume[deviceID] = vol
            }

            if let mute = loadInputMute(for: deviceID) {
                perInputMute[deviceID] = mute
            } else {
                perInputMute[deviceID] = (vol <= 0.0001)
            }

            if listeners[deviceID] == nil {
                var newEntries: [ListenerEntry] = []

                if var volAddress = inputVolumePropertyAddress(for: deviceID) {
                    let block: AudioObjectPropertyListenerBlock = { _, _ in
                        let newVol = self.loadInputVolume(for: deviceID) ?? self.perInputVolume[deviceID] ?? 1.0
                        Task { @MainActor in
                            if let lastUI = self.lastInputSetByUI[deviceID], self.approxEqual(lastUI, newVol, eps: self.volumeEpsilon) {
                                self.lastInputSetByUI.removeValue(forKey: deviceID)
                                return
                            }
                            let current = self.perInputVolume[deviceID] ?? 1.0
                            if !self.approxEqual(current, newVol, eps: self.volumeEpsilon) {
                                self.perInputVolume[deviceID] = newVol
                                if newVol > 0 {
                                    self.perInputLastNonZeroVolume[deviceID] = newVol
                                }
                                if self.loadInputMute(for: deviceID) == nil {
                                    self.perInputMute[deviceID] = (newVol <= 0.0001)
                                }
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
                                if self.perInputMute[deviceID] != newMute {
                                    self.perInputMute[deviceID] = newMute
                                }
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
        let clampedCGFloat = CGFloat(min(max(volume, 0), 1))
        var clamped: Float32 = Float32(clampedCGFloat)
        let size = UInt32(MemoryLayout.size(ofValue: clamped))
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped)
        if status == noErr {
            let cg = CGFloat(clamped)
            perInputVolume[deviceID] = cg
            lastInputSetByUI[deviceID] = cg
            if cg > 0 {
                perInputLastNonZeroVolume[deviceID] = cg
            }
        } else {
            // Ignore errors silently in UI
        }
    }

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
                if let last = perInputLastNonZeroVolume[deviceID], last > 0 {
                    setInputVolume(deviceID, last)
                } else {
                    setInputVolume(deviceID, unmuteGain)
                }
            }
        } else {
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

    func hasInputVolume(_ deviceID: AudioDeviceID) -> Bool {
        return inputVolumePropertyAddress(for: deviceID) != nil
    }

    func hasInputMute(_ deviceID: AudioDeviceID) -> Bool {
        guard var address = inputMutePropertyAddress(for: deviceID) else { return false }
        return AudioObjectHasProperty(deviceID, &address)
    }
}

// MARK: - CoreAudio helpers (output)

private extension MainMenuView {
    func setupOutputDevicesStateAndListeners() {
        let currentIDs = Set(availableOutputDevices.keys)
        for (deviceID, entries) in outputListeners {
            if !currentIDs.contains(deviceID) {
                removeListeners(for: deviceID, entries: entries)
                outputListeners.removeValue(forKey: deviceID)
                perOutputVolume.removeValue(forKey: deviceID)
                perOutputMute.removeValue(forKey: deviceID)
                perOutputLastNonZeroVolume.removeValue(forKey: deviceID)
                lastOutputSetByUI.removeValue(forKey: deviceID)
                cancelTimer(for: deviceID, output: true)
            }
        }

        for deviceID in currentIDs {
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

            if outputListeners[deviceID] == nil {
                var newEntries: [ListenerEntry] = []

                if var volAddress = outputVolumePropertyAddress(for: deviceID) {
                    let block: AudioObjectPropertyListenerBlock = { _, _ in
                        let newVol = self.loadOutputVolume(for: deviceID) ?? self.perOutputVolume[deviceID] ?? 1.0
                        Task { @MainActor in
                            if let lastUI = self.lastOutputSetByUI[deviceID], self.approxEqual(lastUI, newVol, eps: self.volumeEpsilon) {
                                self.lastOutputSetByUI.removeValue(forKey: deviceID)
                                return
                            }
                            let current = self.perOutputVolume[deviceID] ?? 1.0
                            if !self.approxEqual(current, newVol, eps: self.volumeEpsilon) {
                                self.perOutputVolume[deviceID] = newVol
                                if newVol > 0 {
                                    self.perOutputLastNonZeroVolume[deviceID] = newVol
                                }
                                if self.loadOutputMute(for: deviceID) == nil {
                                    self.perOutputMute[deviceID] = (newVol <= 0.0001)
                                }
                                if deviceID == self.selectedOutputDeviceID {
                                    self.onOutputVolumeChange(newVol)
                                }
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
                                if self.perOutputMute[deviceID] != newMute {
                                    self.perOutputMute[deviceID] = newMute
                                }
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
        let clampedCGFloat = CGFloat(min(max(volume, 0), 1))
        var clamped: Float32 = Float32(clampedCGFloat)
        let size = UInt32(MemoryLayout.size(ofValue: clamped))
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped)
        if status == noErr {
            let cg = CGFloat(clamped)
            perOutputVolume[deviceID] = cg
            lastOutputSetByUI[deviceID] = cg
            if cg > 0 {
                perOutputLastNonZeroVolume[deviceID] = cg
            }
            if deviceID == selectedOutputDeviceID {
                onOutputVolumeChange(cg)
            }
        } else {
            // Ignore errors silently in UI
        }
    }

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
                if let last = perOutputLastNonZeroVolume[deviceID], last > 0 {
                    setOutputVolume(deviceID, last)
                } else {
                    setOutputVolume(deviceID, unmuteGain)
                }
            }
        } else {
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

// MARK: - Escape key handler for inline editors

private struct EscapeKeyHandler: NSViewRepresentable {
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
    }

    final class Coordinator {
        var onEscape: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
        }

        func attach(to view: NSView) {
            self.view = view
            installMonitor()
        }

        deinit {
            removeMonitor()
        }

        private func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == UInt16(kVK_Escape) {
                    self.onEscape()
                    // Consume event so default escape behavior doesn't interfere
                    return nil
                }
                return event
            } as Any
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
