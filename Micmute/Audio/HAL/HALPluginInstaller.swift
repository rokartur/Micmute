import Foundation
import AppKit

/// Provides user-facing guidance for installing the experimental HAL plugin variant.
/// We intentionally do not attempt privileged writes programmatically yet.
@MainActor
enum HALPluginInstaller {
    static let pluginBundleName = "PerAppVolumeDevice.driver"
    static let systemPath = "/Library/Audio/Plug-Ins/HAL/" + pluginBundleName

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: systemPath) }

    static func showInstallationInstructions() {
        let alert = NSAlert()
        alert.messageText = "Install HAL Plugin (Experimental)"
        alert.informativeText = "To try the HAL-based per-app audio backend copy \(pluginBundleName) to /Library/Audio/Plug-Ins/HAL (admin required) and restart CoreAudio.\n\nCommands (copy & paste):\n\nsudo cp -R \(pluginBundleName) /Library/Audio/Plug-Ins/HAL/\nsudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/\(pluginBundleName)\nsudo killall coreaudiod\n\nThen reopen Micmute."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
