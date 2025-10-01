import SwiftUI

struct ApplicationVolumeRow: View {
    @ObservedObject private var viewModel: ApplicationVolumeRowViewModel
    @State private var sliderValue: Double
    @State private var isEditingSlider = false

    init(viewModel: ApplicationVolumeRowViewModel) {
        self.viewModel = viewModel
        _sliderValue = State(initialValue: viewModel.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            sliderSection
            peakMeter
        }
        .onReceive(viewModel.$application) { application in
            if !isEditingSlider {
                sliderValue = application.volume
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(viewModel.bundleID)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: toggleMute) {
                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .help(viewModel.isMuted ? "Unmute" : "Mute")
        }
    }

    private var sliderSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Slider(value: Binding(get: {
                sliderValue
            }, set: { newValue in
                sliderValue = newValue
            }), in: 0.0...1.25, onEditingChanged: { editing in
                isEditingSlider = editing
                if !editing {
                    commitSliderValue()
                }
            })
            .help("Adjust \(viewModel.displayName)'s volume")

            Text(volumePercentage(for: sliderValue))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 46, alignment: .trailing)
                .monospacedDigit()
        }
        .onChange(of: sliderValue, initial: false) { _, newValue in
            guard isEditingSlider else { return }
            viewModel.setVolume(newValue)
        }
    }

    private var peakMeter: some View {
        HStack(spacing: 6) {
            Text("Peak")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let peak = max(Double(viewModel.peakLevel.left), Double(viewModel.peakLevel.right))
                let normalized = max(0.0, min(1.0, peak))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.green, .yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, width * CGFloat(normalized)))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: some View {
        Group {
            if let icon = viewModel.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private func toggleMute() {
        viewModel.setMuted(!viewModel.isMuted)
    }

    private func volumePercentage(for value: Double) -> String {
        let clamped = min(max(value, 0), 1.25)
        let percent = Int((clamped * 100).rounded())
        return "\(percent)%"
    }

    private func commitSliderValue() {
        viewModel.setVolume(sliderValue)
    }
}