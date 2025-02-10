//
//  AppearanceView.swift
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

enum DisplayOption: String {
    case largeIcon, smallIcon, text, largeBoth, rowSmallBoth
}

enum Placement: String {
    case centerBottom, centerTop, leftTop, rightTop, leftBottom, rightBottom
}

struct AppearanceView: View {
    @AppStorage("isMuted") var isMuted: Bool = false
    @AppStorage("displayOption") var displayOption: DisplayOption = .largeBoth
    @AppStorage("placement") var placement: Placement = .centerBottom
    @AppStorage("padding") var padding: Double = 70.0
    @AppStorage("iconSize") var iconSize: Int = 70

    let smallPreview = Constants.Appearance.smallPreview
    let smallCornerRadius = Constants.Appearance.smallCornerRadius
    let largePreview = Constants.Appearance.largePreview
    let largeCornerRadius = Constants.Appearance.largeCornerRadius
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Picker("Display", selection: $displayOption) {
                Text("Only Large Icon").tag(DisplayOption.largeIcon)
                Text("Only Small Icon").tag(DisplayOption.smallIcon)
                Text("Only Text").tag(DisplayOption.text)
                Text("Large Both").tag(DisplayOption.largeBoth)
                Text("Row Small Both").tag(DisplayOption.rowSmallBoth)
            }
            .pickerStyle(RadioGroupPickerStyle())
            .padding([.leading], -94)

            Picker("Placement", selection: $placement) {
                Text("Center Bottom").tag(Placement.centerBottom)
                Text("Center Top").tag(Placement.centerTop)
                Text("Left Top").tag(Placement.leftTop)
                Text("Right Top").tag(Placement.rightTop)
                Text("Left Bottom").tag(Placement.leftBottom)
                Text("Right Bottom").tag(Placement.rightBottom)
            }

            Picker("Padding", selection: $padding) {
                Text("Small").tag(35.0)
                Text("Medium").tag(70.0)
                Text("Large").tag(140.0)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding([.leading], 14)

            NotificationView(isMuted: isMuted)
                .frame(
                    width: (displayOption == .smallIcon) ? smallPreview : largePreview,
                    height: (displayOption == .rowSmallBoth || displayOption == .text || displayOption == .smallIcon) ? smallPreview : largePreview
                )
                .roundedBorder(color: .gray, width: 1, cornerRadius: displayOption == .smallIcon ? smallCornerRadius : largeCornerRadius)
        }
        .padding(24)
        .frame(maxWidth: 324)
    }
}

//#Preview {
//    AppearanceView(isMute: true, displayOption: DisplayOption.largeBoth, placement: Placement.centerBottom, padding: 70.0)
//}
