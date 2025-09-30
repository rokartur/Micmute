//
//  KeyboardShortcutSettingsView.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI

extension View {
     public func addBorder<S>(_ content: S, width: CGFloat = 1, cornerRadius: CGFloat) -> some View where S : ShapeStyle {
         let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
         return clipShape(roundedRect)
              .overlay(roundedRect.strokeBorder(content, lineWidth: width))
     }
 }

struct CustomSectionView<Content: View>: View {
    let title: String?
    let subtitle: String?
    let content: Content
    
    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                (title != nil) ? Text(title!).font(.headline) : nil
                (subtitle != nil) ? Text(subtitle!).font(.subheadline).foregroundStyle(.secondary) : nil
            }
            
            VStack(spacing: 8) {
                content
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
            .addBorder(Color(NSColor.separatorColor), width: 1, cornerRadius: 6)
        }.cornerRadius(6)
    }
}
