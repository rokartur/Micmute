//
//  MicmuteApp.swift
//  Micmute
//
//  Created by rokartur on 23/12/23.
//

import SwiftUI
import ServiceManagement
import CoreAudio
import HotKey
import MenuBarExtraAccess

@main
struct MicmuteApp: App {
    @AppStorage("isMute") var isMute: Bool = false
    @AppStorage("openAtLogin") var openAtLogin: Bool = true
    var hotKey = HotKey(key: .m, modifiers: [.control, .option, .command])
    
    var body: some Scene {
        MenuBarExtra {
            Button("Toggle mute") {
                toggleMute()
                hotKey.keyDownHandler = toggleMute
            }
            .keyboardShortcut("M", modifiers: [.control, .option, .command])
            
            Divider()
            
            Button(action: {
                openAtLogin.toggle()
                setLaunchAtLogin(enabled: openAtLogin)
            }) {
                HStack {
                    Image(systemName: openAtLogin ? "checkmark.circle" : "circle")
                    Text("Open at Login")
                }
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            HStack {
                let micMute: NSImage = {
                        let ratio = $0.size.height / $0.size.width
                        $0.size.height = 18
                        $0.size.width = 18 / ratio
                        return $0
                    }(NSImage(named: "mic.mute")!)
                
                let micUnmute: NSImage = {
                        let ratio = $0.size.height / $0.size.width
                        $0.size.height = 18
                        $0.size.width = 18 / ratio
                        return $0
                    }(NSImage(named: "mic.unmute")!)
                
                Image(nsImage: isMute ? micMute : micUnmute)
            }
        }
    }
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        setLaunchAtLogin(enabled: openAtLogin)
        hotKey.keyDownHandler = toggleMute
    }
    
    private func toggleMute() {
        isMute.toggle()
        setDefaultInputVolumeDevice(isMute: isMute)
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService().register()
            } else {
                try SMAppService().unregister()
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    private func setDefaultInputVolumeDevice(isMute: Bool) {
        var defaultInputDeviceID = kAudioObjectUnknown
        var defaultInputDeviceIDSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &defaultInputDeviceIDSize,
            &defaultInputDeviceID
        )

        var mute: UInt32 = isMute ? 1 : 0
        let muteSize = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            defaultInputDeviceID,
            &address,
            0,
            nil,
            muteSize,
            &mute
        )
    }

}
