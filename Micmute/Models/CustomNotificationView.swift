//
//  CustomNotificationView.swift
//  Micmute
//
//  Created by Artur Rok on 01/06/2024.
//

import SwiftUI
import Cocoa

class MuteNotificationWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

class MuteNotificationWindowController: NSWindowController {
    var isMute: Bool
    var animationType: String
    var animationDuration: Double
    let isDarkMode = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    init(isMute: Bool, animationType: String, animationDuration: Double) {
        self.isMute = isMute
        self.animationType = animationType
        self.animationDuration = animationDuration

        let muteNotificationWindow = MuteNotificationWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        muteNotificationWindow.setFrameAutosaveName("Mute Notification Window")
        muteNotificationWindow.hasShadow = false
        muteNotificationWindow.isOpaque = false
        muteNotificationWindow.backgroundColor = NSColor.clear
        muteNotificationWindow.level = .floating
        muteNotificationWindow.isMovableByWindowBackground = false
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .followsWindowActiveState
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 20
        visualEffectView.layer?.masksToBounds = true
        muteNotificationWindow.contentView = visualEffectView
        let contentView = VStack(spacing: 8) {
            if isMute {
                Image(systemName: "mic.slash.fill")
                    .symbolRenderingMode(.palette)
                    .font(.system(size: 108))
                    .foregroundStyle(.gray, .red)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 108))
            }
            Text(isMute ? "Microphone is muted" : "Microphone is unmuted")
                .font(.title3)
        }
        .padding()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = visualEffectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(hostingView)
        super.init(window: muteNotificationWindow)

        if let screen = NSScreen.screens.first {
            let screenWidth = screen.visibleFrame.width
            let screenHeight = screen.visibleFrame.height
            let windowWidth = muteNotificationWindow.frame.width
            let windowHeight = muteNotificationWindow.frame.height
            let xPos = (screenWidth - windowWidth) / 2
            let yPos = screenHeight * 0.1
            let windowRect = NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight)
            muteNotificationWindow.setFrame(windowRect, display: true)
        }

        if self.animationType == "Fade" {
            muteNotificationWindow.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                muteNotificationWindow.animator().alphaValue = 1
            }
        } else if self.animationType == "Scale" {
            let originalFrame = muteNotificationWindow.frame
            muteNotificationWindow.setFrame(NSRect(x: originalFrame.midX, y: originalFrame.midY, width: 0, height: 0), display: true)
            muteNotificationWindow.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                muteNotificationWindow.animator().setFrame(originalFrame, display: true)
                muteNotificationWindow.animator().alphaValue = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            if self.animationType == "None" {
                muteNotificationWindow.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    if self.animationType == "Fade" {
                        muteNotificationWindow.animator().alphaValue = 0
                    } else if self.animationType == "Scale" {
                        muteNotificationWindow.animator().setFrame(NSRect(x: muteNotificationWindow.frame.midX, y: muteNotificationWindow.frame.midY, width: 0, height: 0), display: true)
                        muteNotificationWindow.animator().alphaValue = 0
                    }
                } completionHandler: {
                    muteNotificationWindow.orderOut(nil)
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
