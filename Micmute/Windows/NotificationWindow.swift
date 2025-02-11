//
//  CustomNotificationView.swift
//  Micmute
//
//  Created by Artur Rok on 01/06/2024.
//

import SwiftUI
import Cocoa

class NotificationWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

struct NotificationViewModel: View {
    var isMuted: Bool
    @AppStorage(AppStorageEntry.displayOption.rawValue) var displayOption: DisplayOption = .largeBoth

    let largeIcon = Appearance.largeIcon
    let smallIcon = Appearance.smallIcon
    let smallPreview = Appearance.smallPreview
    let largePreview = Appearance.largePreview
    
    var body: some View {
        VStack(spacing: 8) {
            if displayOption == .largeBoth || displayOption == .largeIcon {
                if isMuted {
                    Image(systemName: "mic.slash.fill")
                        .symbolRenderingMode(.palette)
                        .font(.system(size: largeIcon))
                        .foregroundStyle(.gray, .red)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: largeIcon))
                }
            }
            if displayOption == .largeBoth || displayOption == .text {
                Text(isMuted ? "Muted" : "Unmuted")
                    .font(.title3)
            }
            if displayOption == .smallIcon {
                if isMuted {
                    Image(systemName: "mic.slash.fill")
                        .symbolRenderingMode(.palette)
                        .font(.system(size: smallIcon))
                        .foregroundStyle(.gray, .red)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: smallIcon))
                }
            }
            if displayOption == .rowSmallBoth {
                HStack(spacing: 12) {
                    if isMuted {
                        Image(systemName: "mic.slash.fill")
                            .symbolRenderingMode(.palette)
                            .font(.system(size: 32))
                            .foregroundStyle(.gray, .red)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                    }
                    Text(isMuted ? "Muted" : "Unmuted")
                        .font(.title3)
                        .frame(minWidth: 68)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .frame(
            width: (displayOption == .smallIcon) ? smallPreview : largePreview,
            height: (displayOption == .rowSmallBoth || displayOption == .text || displayOption == .smallIcon) ? smallPreview : largePreview
        )
    }
}

class NotificationWindowController: NSWindowController {
    var isMuted: Bool
    let isDarkMode = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    var animationType: AnimationType
    var animationDuration: Double
    var displayOption: DisplayOption
    var placement: Placement
    var padding: Double

    let smallPreview = Appearance.smallPreview
    let smallCornerRadius = Appearance.smallCornerRadius
    let largePreview = Appearance.largePreview
    let largeCornerRadius = Appearance.largeCornerRadius
    
    init(isMuted: Bool, animationType: AnimationType, animationDuration: Double, displayOption: DisplayOption, placement: Placement, padding: Double) {
        self.isMuted = isMuted
        self.animationType = animationType
        self.animationDuration = animationDuration
        self.displayOption = displayOption
        self.placement = placement
        self.padding = padding

        let windowWidthSize = self.displayOption == .smallIcon ? smallPreview : largePreview
        let windowHeightSize = self.displayOption == .rowSmallBoth || self.displayOption == .text || self.displayOption == .smallIcon ? smallPreview : largePreview

        let notificationWindow = NotificationWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: min((windowWidthSize), windowWidthSize),
                height: min((windowHeightSize), windowHeightSize)
            ),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        notificationWindow.setFrameAutosaveName("Notification Window")
        notificationWindow.hasShadow = false
        notificationWindow.isOpaque = false
        notificationWindow.backgroundColor = NSColor.clear
        notificationWindow.level = .floating
        notificationWindow.isMovableByWindowBackground = false
        
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .underWindowBackground
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .followsWindowActiveState
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = self.displayOption == .smallIcon ? smallCornerRadius : largeCornerRadius
        visualEffectView.layer?.masksToBounds = true
        notificationWindow.contentView = visualEffectView
        
        let hostingView = NSHostingView(rootView: NotificationViewModel(isMuted: isMuted))
        hostingView.frame = visualEffectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(hostingView)
        super.init(window: notificationWindow)

        if let screen = NSScreen.screens.first {
            let screenWidth = screen.visibleFrame.width
            let screenHeight = screen.visibleFrame.height
            let windowWidth = notificationWindow.frame.width
            let windowHeight = notificationWindow.frame.height
            var xPos: CGFloat = 0
            var yPos: CGFloat = 0
            
            switch placement {
                case .centerBottom:
                    xPos = (screenWidth - windowWidth) / 2
                    yPos = padding
                case .centerTop:
                    xPos = (screenWidth - windowWidth) / 2
                    yPos = (screenHeight - windowHeight) - padding
                case .leftTop:
                    xPos = padding
                    yPos = (screenHeight - windowHeight) - padding
                case .rightTop:
                    xPos = (screenWidth - windowWidth) - padding
                    yPos = (screenHeight - windowHeight) - padding
                case .leftBottom:
                    xPos = padding
                    yPos = padding
                case .rightBottom:
                    xPos = (screenWidth - windowWidth) - padding
                    yPos = padding
            }

            let windowRect = NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight)
            notificationWindow.setFrame(windowRect, display: true)
        }

        if self.animationType == .fade {
            notificationWindow.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                notificationWindow.animator().alphaValue = 1
            }
        } else if self.animationType == .scale {
            let originalFrame = notificationWindow.frame
            notificationWindow.setFrame(NSRect(x: originalFrame.midX, y: originalFrame.midY, width: 0, height: 0), display: true)
            notificationWindow.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                notificationWindow.animator().setFrame(originalFrame, display: true)
                notificationWindow.animator().alphaValue = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            if self.animationType == .none {
                notificationWindow.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    if self.animationType == .fade {
                        notificationWindow.animator().alphaValue = 0
                    } else if self.animationType == .scale {
                        notificationWindow.animator().setFrame(NSRect(x: notificationWindow.frame.midX, y: notificationWindow.frame.midY, width: 0, height: 0), display: true)
                        notificationWindow.animator().alphaValue = 0
                    }
                } completionHandler: {
                    notificationWindow.orderOut(nil)
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
