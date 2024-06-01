//
//  ToggleMicrophone.swift
//  Micmute
//
//  Created by Artur Rok on 31/05/2024.
//

import ServiceManagement
import CoreAudio

func setDefaultInputVolumeDevice(isMute: Bool) {
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
