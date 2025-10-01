#ifndef VIRTUAL_AUDIO_DRIVER_BRIDGE_H
#define VIRTUAL_AUDIO_DRIVER_BRIDGE_H

#include <CoreAudio/AudioHardware.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

OSStatus VirtualAudioDriverInitialize(void);
OSStatus VirtualAudioDriverShutdown(void);
OSStatus VirtualAudioDriverSetApplicationVolume(CFStringRef bundleID, Float32 volume);
OSStatus VirtualAudioDriverGetApplicationVolume(CFStringRef bundleID, Float32* outVolume);
OSStatus VirtualAudioDriverMuteApplication(CFStringRef bundleID, Boolean mute);
Boolean VirtualAudioDriverIsApplicationMuted(CFStringRef bundleID);
CFArrayRef VirtualAudioDriverCopyActiveApplications(void) CF_RETURNS_RETAINED;

#ifdef __cplusplus
}
#endif

#endif /* VIRTUAL_AUDIO_DRIVER_BRIDGE_H */
