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
        static let repo = URL(string: "https://github.com/rokartur/Micmute")!
        static let author = URL(string: "https://github.com/rokartur")!
        static let whatsNew = URL(string: "https://github.com/rokartur/Micmute/releases")!
    }
}
