//
//  getMicImage.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import SwiftUI

func getMicMuteImage() -> NSImage {
    let image = NSImage(named: "mic.mute")!
    let ratio = image.size.height / image.size.width
    image.size.height = 17
    image.size.width = 17 / ratio
    return image
}

func getMicUnmuteImage() -> NSImage {
    let image = NSImage(named: "mic.unmute")!
    let ratio = image.size.height / image.size.width
    image.size.height = 17
    image.size.width = 17 / ratio
    return image
}
