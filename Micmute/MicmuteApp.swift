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

@main
struct MicmuteApp: App {
    @AppStorage("isMute") var isMute: Bool = false
    @AppStorage("openAtLogin") var openAtLogin: Bool = true
    let hotKey = HotKey(key: .m, modifiers: [.control, .option, .command])
    
    var body: some Scene {
        MenuBarExtra("Micmute", systemImage: isMute ? "mic.slash" : "mic") {
            Button("Toggle mute") {
                isMute.toggle()
                setDefaultInputVolumeDevice(isMute: isMute)
                
                hotKey.keyDownHandler = {
                    isMute.toggle()
                    setDefaultInputVolumeDevice(isMute: isMute)
                }
            }
            .keyboardShortcut("M", modifiers: [.control, .option, .command])
            
            Divider()
            
            HStack {
                Button(action: {
                    openAtLogin.toggle()
                    setLaunchAtLogin(enabled: openAtLogin)
                }) {
                    HStack {
                        Image(systemName: openAtLogin ? "checkmark.circle" : "")
                        Text("Open at Login")
                    }
                }
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        setLaunchAtLogin(enabled: openAtLogin)
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
        
        // Get the default input device ID
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
