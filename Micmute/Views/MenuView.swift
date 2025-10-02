//
//  MenuView.swift
//  Micmute
//
//  Created by artur on 10/02/2025.
//

import SwiftUI
import CoreAudio
import AlinFoundation


@MainActor
struct MainMenuView: View {
    @EnvironmentObject private var updater: Updater
    @EnvironmentObject private var perAppVolumeManager: PerAppAudioVolumeManager
    @Binding var unmuteGain: CGFloat
    @Binding var selectedDeviceID: AudioDeviceID
    @Binding var availableDevices: [AudioDeviceID: String]
    @Binding var availableOutputDevices: [AudioDeviceID: String]
    @Binding var selectedOutputDeviceID: AudioDeviceID
    @Binding var outputVolume: CGFloat
    @State private var sliderGain: CGFloat = 1.0
    @State private var selectedDevice: DeviceEntry.ID? = nil
    @State private var selectedOutputDevice: DeviceEntry.ID? = nil
    @AppStorage(AppStorageEntry.menuInputSectionExpanded.rawValue) private var storedInputExpanded: Bool = true
    @AppStorage(AppStorageEntry.menuOutputSectionExpanded.rawValue) private var storedOutputExpanded: Bool = true
    @State private var isInputExpanded: Bool = true
    @State private var isOutputExpanded: Bool = true
    @State private var isDeviceSelectionLocked = false
    var onDeviceSelected: (AudioDeviceID) -> Void
    var onOutputDeviceSelected: (AudioDeviceID) -> Void
    var onOutputVolumeChange: (CGFloat) -> Void
    var onAppear: () -> Void = { }
    var onDisappear: () -> Void = { }

    static let preferredWidth: CGFloat = 320
    private let contentPadding: CGFloat = 14
    private let interSectionSpacing: CGFloat = 12
    private let deviceSelectionCooldown: TimeInterval = 0.5

    private var inputDeviceEntries: [DeviceEntry] {
        deviceEntries(from: availableDevices)
    }

    private var outputDeviceEntries: [DeviceEntry] {
        deviceEntries(from: availableOutputDevices)
    }
    
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
        self.onAppear = onAppear
        self.onDisappear = onDisappear
        self._sliderGain = State(initialValue: unmuteGain.wrappedValue)
        self._isInputExpanded = State(initialValue: storedInputExpanded)
        self._isOutputExpanded = State(initialValue: storedOutputExpanded)
        self._selectedOutputDevice = State(initialValue: selectedOutputDeviceID.wrappedValue)
    }

    private var sliderGainPercentage: String {
        let clampedGain = min(max(sliderGain, .zero), CGFloat(1))
        let percentValue = Int((clampedGain * 100).rounded())
        return "\(percentValue)%"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: interSectionSpacing) {
//                ApplicationVolumeListView(manager: perAppVolumeManager)

                outputSection

                inputSection

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
            selectedOutputDevice = selectedOutputDeviceID
            sliderGain = unmuteGain
            onAppear()
        }
        .onChange(of: selectedDevice) { oldValue, newValue in
            if let newValue = newValue, newValue != selectedDeviceID {
                selectedDeviceID = newValue
                onDeviceSelected(newValue)
            }
        }
        .onChange(of: selectedOutputDevice) { oldValue, newValue in
            if let newValue = newValue, newValue != selectedOutputDeviceID {
                selectedOutputDeviceID = newValue
                onOutputDeviceSelected(newValue)
            }
        }
        .onChange(of: unmuteGain) { _, newValue in
            if sliderGain != newValue {
                sliderGain = newValue
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
        .onDisappear {
            onDisappear()
        }
    }

    private var inputSection: some View {
        CollapsibleMenuSection(title: "Input", isExpanded: $isInputExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                volumeAfterUnmuteContent

                Divider()

                availableDevicesContent
            }
        }
    }

    private var outputVolumePercentage: String {
        let clampedVolume = min(max(outputVolume, .zero), CGFloat(1))
        let percentValue = Int((clampedVolume * 100).rounded())
        return "\(percentValue)%"
    }

    private var outputSection: some View {
        CollapsibleMenuSection(title: "Output", isExpanded: $isOutputExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                outputVolumeContent

                Divider()

                availableOutputDevicesContent
            }
        }
    }

    private var volumeAfterUnmuteContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuSectionHeader("Volume after unmute")

            HStack(alignment: .center, spacing: 8) {
                MenuVolumeSlider(value: $sliderGain)
                    .onChange(of: sliderGain) { _, newValue in
                        unmuteGain = newValue
                    }

                Text(sliderGainPercentage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var availableDevicesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuSectionHeader("Available devices")

            VStack(spacing: 6) {
                ForEach(inputDeviceEntries) { item in
                    SelectableMenuRow(
                        title: item.name,
                        systemImage: icon(for: item.name, defaultSymbol: "mic.fill"),
                        isSelected: selectedDevice == item.id,
                        isDisabled: isDeviceSelectionLocked
                    ) {
                        performWithDeviceSelectionLock {
                            let wasSelected = selectedDevice == item.id
                            selectedDevice = item.id

                            if wasSelected {
                                onDeviceSelected(item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var outputVolumeContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuSectionHeader("Output volume")

            HStack(alignment: .center, spacing: 8) {
                MenuVolumeSlider(
                    value: Binding(
                        get: { outputVolume },
                        set: { newValue in
                            let clampedValue = min(max(newValue, 0), 1)
                            if outputVolume != clampedValue {
                                outputVolume = clampedValue
                            }
                            onOutputVolumeChange(clampedValue)
                        }
                    ),
                    accessibilityLabel: "Output device volume"
                )

                Text(outputVolumePercentage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var availableOutputDevicesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuSectionHeader("Available devices")

            VStack(spacing: 6) {
                if outputDeviceEntries.isEmpty {
                    MenuStaticRow(
                        title: "No output devices found",
                        systemImage: "questionmark.circle",
                        textColor: .secondary,
                        iconColor: .secondary
                    )
                } else {
                    ForEach(outputDeviceEntries) { item in
                        SelectableMenuRow(
                            title: item.name,
                            systemImage: icon(for: item.name, defaultSymbol: "speaker.wave.2.fill"),
                            isSelected: selectedOutputDevice == item.id,
                            isDisabled: isDeviceSelectionLocked
                        ) {
                            performWithDeviceSelectionLock {
                                let wasSelected = selectedOutputDevice == item.id
                                selectedOutputDevice = item.id

                                if wasSelected {
                                    onOutputDeviceSelected(item.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func performWithDeviceSelectionLock(_ action: () -> Void) {
        guard !isDeviceSelectionLocked else { return }
        isDeviceSelectionLocked = true
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + deviceSelectionCooldown) {
            isDeviceSelectionLocked = false
        }
    }

    private func deviceEntries(from devices: [AudioDeviceID: String]) -> [DeviceEntry] {
        devices
            .map { DeviceEntry(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func icon(for deviceName: String, defaultSymbol: String) -> String {
        let lowercased = deviceName.lowercased()

        if lowercased.contains("macbook") {
            return "laptopcomputer"
        }

        if lowercased.contains("display") || lowercased.contains("monitor") {
            return "display"
        }

        return defaultSymbol
    }
}

private struct MenuSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold, design: .default))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 3)
    }
}

private struct MenuCard<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct CollapsibleMenuSection<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    @State private var isToggleCoolingDown = false
    @ViewBuilder private let content: Content

    init(title: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }
    
    private let toggleCooldown: TimeInterval = 0.7
    private let transitionConfig = CustomTransition(
        insertionMove: .easeOut(duration: 0.3),
        insertionOpacity: .linear(duration: 0.05).delay(0.2),
        removalMove: .easeIn(duration: 0.3),
        removalOpacity: .linear(duration: 0.05)
    )

    var body: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    guard !isToggleCoolingDown else { return }
                    isToggleCoolingDown = true
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + toggleCooldown) {
                        isToggleCoolingDown = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(.easeInOut(duration: 0.18), value: isExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isToggleCoolingDown)
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text("Wait 2.5 seconds between interactions."))
                .accessibilityAddTraits(.isHeader)

                if isExpanded {
                    Divider()
                        .padding(.vertical, 4)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(
                                    .easeInOut(duration: 0.14).delay(0.04)
                                ),
                                removal: .opacity.animation(.easeInOut(duration: 0.05))
                            )
                        )

                    content.transition(transitionConfig.anyTransition(edge: .top))
                }
            }
        }
    }
}

private struct MenuVolumeSlider: View {
    @Binding var value: CGFloat
    var accessibilityLabel: LocalizedStringKey

    init(value: Binding<CGFloat>, accessibilityLabel: LocalizedStringKey = "Microphone volume after unmute") {
        self._value = value
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        Slider(
            value: Binding<Double>(
                get: { Double(min(max(value, 0), 1)) },
                set: { newValue in value = CGFloat(min(max(0, newValue), 1)) }
            ),
            in: 0...1,
            step: 0.01
        )
        .controlSize(.regular)
        .tint(.accentColor)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct SelectableMenuRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .buttonStyle(MenuRowButtonStyle(isActive: isSelected, isHovered: isHovered))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.12), value: isDisabled)
    }
}

private struct MenuStaticRow: View {
    let title: String
    let systemImage: String
    var textColor: Color = .primary
    var iconColor: Color = .secondary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    var isActive: Bool
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if isHovered {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }

                    if isActive {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    }

                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MenuCommand<Label: View>: View {
    private let action: () -> Void
    private let label: () -> Label
    @State private var isHovered = false

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) where Label == Text {
        self.action = action
        self.label = { Text(title) }
    }

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label()
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .buttonStyle(MenuRowButtonStyle(isActive: false, isHovered: isHovered))
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

struct CustomTransition {
    let insertionMove: Animation
    let insertionOpacity: Animation
    let removalMove: Animation
    let removalOpacity: Animation

    func anyTransition(edge: Edge = .top) -> AnyTransition {
        let insertion = AnyTransition.move(edge: edge)
            .animation(insertionMove)
            .combined(with:
                .opacity.animation(insertionOpacity)
            )

        let removal = AnyTransition.move(edge: edge)
            .animation(removalMove)
            .combined(with:
                .opacity.animation(removalOpacity)
            )

        return .asymmetric(insertion: insertion, removal: removal)
    }
}
