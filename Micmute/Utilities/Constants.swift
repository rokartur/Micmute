//
//  Constants.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import Foundation
import AppKit

enum Constants {
    enum AppInfo {
        static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
        static let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
        static let repo = URL(string: "https://github.com/rokartur/micmute")!
        static let author = URL(string: "https://github.com/rokartur")!
        static let whatsNew = URL(string: "https://github.com/rokartur/micmute/releases")!
    }
    
    enum Appearance {
        static let smallPreview = 78 as CGFloat
        static let smallCornerRadius = 16 as CGFloat
        static let largePreview = 212 as CGFloat
        static let largeCornerRadius = 20 as CGFloat
        static let largeIcon = 108 as CGFloat
        static let smallIcon = 48 as CGFloat
    }
}
