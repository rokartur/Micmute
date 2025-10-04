import SwiftUI
import CoreAudio

enum AppInfo {
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    static let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
    static let repo = URL(string: "https://github.com/rokartur/betteraudio")!
    static let author = URL(string: "https://github.com/rokartur")!
    static let whatsNew = URL(string: "https://github.com/rokartur/betteraudio/releases")!
}

enum AppStorageEntry: String {
    case selectedDeviceID
    case isMuted
    case inputGain
    case iconSize
    case menuGrayscaleIcon
    case unmuteGain
    case displayOption
    case placement
    case padding
    case isNotificationEnabled
    case animationType
    case animationDuration
    case notificationPinBehavior
    case menuBarBehavior
    case launchAtLogin
    case pushToTalk
    case menuBehaviorOnClick
    case menuInputSectionExpanded
    case menuOutputSectionExpanded
    case selectedOutputDeviceID
    case syncSoundEffectsWithOutput
    case perAppShowOnlyActive
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

enum NotificationPinBehavior: String, CaseIterable {
    case disabled
    case untilUnmute
    case always
}

extension NotificationPinBehavior {
    func shouldAutoHide(isMuted: Bool) -> Bool {
        switch self {
        case .disabled:
            return true
        case .untilUnmute:
            return !isMuted
        case .always:
            return false
        }
    }
}

enum MenuBarBehavior: String {
    case mute, menu
}

struct DeviceEntry: Identifiable, Equatable, Hashable {
    let id: AudioDeviceID
    let name: String
}

extension Notification.Name {
    static let notificationConfigurationDidChange = Notification.Name("NotificationConfigurationDidChange")
}
