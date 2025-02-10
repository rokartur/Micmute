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
    @ObservedObject var contentViewModel = ContentViewModel()

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

    var body: some View {
        CustomSectionView {
            HStack(alignment: .top) {
                VStack {
                    HStack(alignment: .center) {
                        Text("Show")
                        Spacer()
                        Toggle("", isOn: contentViewModel.$isNotificationEnabled).controlSize(.mini)
                    }.toggleStyle(.switch)
                    
                    HStack(alignment: .center) {
                        Text("Animation")
                        Spacer()
                        Picker("", selection: contentViewModel.$animationType) {
                            Text("No animation").tag(AnimationType.none)
                            Text("Fade").tag(AnimationType.fade)
                            Text("Scale").tag(AnimationType.scale)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    HStack(alignment: .center) {
                        Text("Duration")
                        Spacer()
                        HStack {
                            TextField("", value: Binding(
                                get: { self.contentViewModel.animationDuration },
                                set: { newValue in
                                    if newValue >= 1 && newValue <= 5 {
                                        self.contentViewModel.animationDuration = newValue
                                    }
                                }
                            ), formatter: formatter)
                            .frame(width: 48)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .multilineTextAlignment(.center)
                        }
                    }
                    
                    HStack(alignment: .center) {
                        Text("Display")
                        Spacer()
                        Picker("", selection: contentViewModel.$displayOption) {
                            Text("Only Large Icon").tag(DisplayOption.largeIcon)
                            Text("Only Small Icon").tag(DisplayOption.smallIcon)
                            Text("Only Text").tag(DisplayOption.text)
                            Text("Large Both").tag(DisplayOption.largeBoth)
                            Text("Row Small Both").tag(DisplayOption.rowSmallBoth)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    HStack(alignment: .center) {
                        Text("Placement")
                        Spacer()
                        Picker("", selection: contentViewModel.$placement) {
                            Text("Center Bottom").tag(Placement.centerBottom)
                            Text("Center Top").tag(Placement.centerTop)
                            Text("Left Top").tag(Placement.leftTop)
                            Text("Right Top").tag(Placement.rightTop)
                            Text("Left Bottom").tag(Placement.leftBottom)
                            Text("Right Bottom").tag(Placement.rightBottom)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    HStack(alignment: .center) {
                        Text("Padding")
                        Spacer()
                        Picker("", selection: contentViewModel.$padding) {
                            Text("Small").tag(Padding.small)
                            Text("Medium").tag(Padding.medium)
                            Text("Large").tag(Padding.large)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                Spacer()
                
                VStack {
                    NotificationViewModel(isMuted: contentViewModel.isMuted)
                        .frame(
                            width: (contentViewModel.displayOption == .smallIcon) ? smallPreview : largePreview,
                            height: (contentViewModel.displayOption == .rowSmallBoth || contentViewModel.displayOption == .text || contentViewModel.displayOption == .smallIcon) ? smallPreview : largePreview
                        )
                        .roundedBorder(color: .gray, width: 1, cornerRadius: contentViewModel.displayOption == .smallIcon ? smallCornerRadius : largeCornerRadius)
                }
                .frame(width: largePreview, alignment: .center)
            }
        }
        .padding([.horizontal, .bottom])
    }
}
