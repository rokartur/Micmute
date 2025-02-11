//
//  Constants.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI
import CoreAudio

enum AppInfo {
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    static let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
    static let repo = URL(string: "https://github.com/rokartur/micmute")!
    static let author = URL(string: "https://github.com/rokartur")!
    static let whatsNew = URL(string: "https://github.com/rokartur/micmute/releases")!
}

enum AppStorageEntry: String {
    case selectedDeviceID, isMuted, inputGain, iconSize, menuGrayscaleIcon, unmuteGain, displayOption, placement, padding, isNotificationEnabled, animationType, animationDuration, menuBarBehavior, launchAtLogin, pushToTalk, menuBehaviorOnClick
}

enum Appearance {
    static let smallPreview: Double = 78
    static let smallCornerRadius: Double = 16
    static let largePreview: Double = 212
    static let largeCornerRadius: Double = 20
    static let largeIcon: Double = 108
    static let smallIcon: Double = 48
}

enum Padding {
    static let small: Double = 35
    static let medium: Double = 70
    static let large: Double = 140
    
}

enum DisplayOption: String {
    case largeIcon, smallIcon, text, largeBoth, rowSmallBoth
}

enum Placement: String {
    case centerBottom, centerTop, leftTop, rightTop, leftBottom, rightBottom
}

enum AnimationType: String {
    case none, fade, scale
}

enum MenuBarBehavior: String {
    case mute, menu
}

struct DeviceEntry: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
}
