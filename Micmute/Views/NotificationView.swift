//
//  NotificationView.swift
//  Micmute
//
//  Created by Artur Rok on 02/06/2024.
//

import SwiftUI

struct RoundedBorder: ViewModifier {
    let color: Color
    let width: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius).stroke(color, lineWidth: width))
            .cornerRadius(cornerRadius)
    }
}

extension View {
    func roundedBorder(color: Color, width: CGFloat, cornerRadius: CGFloat) -> some View {
        self.modifier(RoundedBorder(color: color, width: width, cornerRadius: cornerRadius))
    }
}

struct NotificationView: View {
    @AppStorage(AppStorageEntry.animationType.rawValue) var animationType: AnimationType = .scale
    @AppStorage(AppStorageEntry.animationDuration.rawValue) var animationDuration: Double = 1.3
    @AppStorage(AppStorageEntry.isNotificationEnabled.rawValue) var isNotificationEnabled: Bool = true
    @AppStorage(AppStorageEntry.isMuted.rawValue) var isMuted: Bool = false
    @AppStorage(AppStorageEntry.displayOption.rawValue) var displayOption: DisplayOption = .largeBoth
    @AppStorage(AppStorageEntry.placement.rawValue) var placement: Placement = .centerBottom
    @AppStorage(AppStorageEntry.padding.rawValue) var padding: Double = 70.0

    let smallPreview = Appearance.smallPreview
    let smallCornerRadius = Appearance.smallCornerRadius
    let largePreview = Appearance.largePreview
    let largeCornerRadius = Appearance.largeCornerRadius
    
    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    @ViewBuilder
    private func trailingControl<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer(minLength: 0)
            content()
        }
    }
    
    @ViewBuilder
    private func halfWidthControl<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            HStack {
                Spacer(minLength: 0)
                content()
                    .frame(width: geometry.size.width * 0.5, alignment: .leading)
            }
        }
        .frame(height: 28)
        .gridCellUnsizedAxes(.vertical)
    }

    var body: some View {
        VStack(spacing: 16) {
            CustomSectionView(title: "Behavior") {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Show notification")
                            .gridColumnAlignment(.leading)
                        trailingControl {
                            Toggle("", isOn: $isNotificationEnabled)
                                .labelsHidden()
                                .controlSize(.mini)
                                .toggleStyle(.switch)
                        }
                        .gridColumnAlignment(.trailing)
                    }
                    
                    GridRow {
                        Text("Animation")
                            .gridColumnAlignment(.leading)
                        halfWidthControl {
                            Picker("", selection: $animationType) {
                                Text("No animation").tag(AnimationType.none)
                                Text("Fade").tag(AnimationType.fade)
                                Text("Scale").tag(AnimationType.scale)
                            }
                            .labelsHidden()
                        }
                        .gridColumnAlignment(.trailing)
                    }
                    
                    GridRow {
                        Text("Duration")
                            .gridColumnAlignment(.leading)
                        trailingControl {
                            TextField("", value: Binding(
                                get: { self.animationDuration },
                                set: { newValue in
                                    if newValue >= 1 && newValue <= 5 {
                                        self.animationDuration = newValue
                                    }
                                }
                            ), formatter: formatter)
                            .frame(width: 60)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .multilineTextAlignment(.center)
                        }
                        .gridColumnAlignment(.trailing)
                    }
                }
            }
            
            CustomSectionView(title: "Appearance") {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Display")
                            .gridColumnAlignment(.leading)
                        halfWidthControl {
                            Picker("", selection: $displayOption) {
                                Text("Only Large Icon").tag(DisplayOption.largeIcon)
                                Text("Only Small Icon").tag(DisplayOption.smallIcon)
                                Text("Only Text").tag(DisplayOption.text)
                                Text("Large Both").tag(DisplayOption.largeBoth)
                                Text("Row Small Both").tag(DisplayOption.rowSmallBoth)
                            }
                            .labelsHidden()
                        }
                        .gridColumnAlignment(.trailing)
                    }
                    
                    GridRow {
                        Text("Placement")
                            .gridColumnAlignment(.leading)
                        halfWidthControl {
                            Picker("", selection: $placement) {
                                Text("Center Bottom").tag(Placement.centerBottom)
                                Text("Center Top").tag(Placement.centerTop)
                                Text("Left Top").tag(Placement.leftTop)
                                Text("Right Top").tag(Placement.rightTop)
                                Text("Left Bottom").tag(Placement.leftBottom)
                                Text("Right Bottom").tag(Placement.rightBottom)
                            }
                            .labelsHidden()
                        }
                        .gridColumnAlignment(.trailing)
                    }
                    
                    GridRow {
                        Text("Padding")
                            .gridColumnAlignment(.leading)
                        halfWidthControl {
                            Picker("", selection: $padding) {
                                Text("Small").tag(Padding.small)
                                Text("Medium").tag(Padding.medium)
                                Text("Large").tag(Padding.large)
                            }
                            .labelsHidden()
                        }
                        .gridColumnAlignment(.trailing)
                    }
                }
            }
            
            CustomSectionView(title: "Preview") {
                HStack {
                    Spacer()
                    NotificationViewModel(isMuted: isMuted)
                        .frame(
                            width: (displayOption == .smallIcon) ? smallPreview : largePreview,
                            height: (displayOption == .rowSmallBoth || displayOption == .text || displayOption == .smallIcon) ? smallPreview : largePreview
                        )
                        .roundedBorder(color: .gray, width: 1, cornerRadius: displayOption == .smallIcon ? smallCornerRadius : largeCornerRadius)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
