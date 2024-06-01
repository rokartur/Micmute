//
//  getMicImage.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI

func getMicMuteImage() -> NSImage {
    let isDarkMode = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let imageName = isDarkMode ? "mic.mute.dark" : "mic.mute.light"
    let image = NSImage(named: imageName)!
    let ratio = image.size.height / image.size.width
    image.size.height = 16
    image.size.width = 16 / ratio
    return image
}

func getMicUnmuteImage() -> NSImage {
    let isDarkMode = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let imageName = isDarkMode ? "mic.unmute.dark" : "mic.unmute.light"
    let image = NSImage(named: imageName)!
    let ratio = image.size.height / image.size.width
    image.size.height = 16
    image.size.width = 16 / ratio
    return image
}
