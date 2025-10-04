import SwiftUI

func getMicMuteImage() -> NSImage {
    let config = NSImage.SymbolConfiguration(paletteColors: [NSColor.systemRed])
    let image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    image.isTemplate = true
    let ratio = image.size.height / image.size.width
    image.size.height = 16
    image.size.width = 16 / ratio
    return image
}

func getMicUnmuteImage() -> NSImage {
    let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)!
    image.isTemplate = true
    let ratio = image.size.height / image.size.width
    image.size.height = 20
    image.size.width = 20 / ratio
    return image
}
