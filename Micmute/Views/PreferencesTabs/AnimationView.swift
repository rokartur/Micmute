//
//  AnimationView.swift
//  Micmute
//
//  Created by Artur Rok on 02/06/2024.
//

import SwiftUI

enum AnimationType: String {
    case none, fade, scale
}

struct AnimationView: View {
    @AppStorage("animationType") var animationType: AnimationType = .scale
    @AppStorage("animationDuration") var animationDuration: Double = 1.3

    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    var body: some View {
        VStack(spacing: 16) {
            Picker("Type", selection: $animationType) {
                Text("No animation").tag(AnimationType.none)
                Text("Fade").tag(AnimationType.fade)
                Text("Scale").tag(AnimationType.scale)
            }
            .pickerStyle(MenuPickerStyle())
            .padding([.leading], 22)
            
            HStack {
                Text("Duration")
                HStack {
                    TextField("", value: Binding(
                        get: { self.animationDuration },
                        set: { newValue in
                            if newValue >= 1 && newValue <= 5 {
                                self.animationDuration = newValue
                            }
                        }
                    ), formatter: formatter)
                    .frame(width: 48)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.center)
                    Slider(value: $animationDuration, in: 1...5)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 312)
    }
}
