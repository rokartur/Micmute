#ifndef BGMPlugIn_h
#define BGMPlugIn_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <pthread.h>

// Simplified skeleton – does not yet implement per-app mixing.
#define kBGMPlugInBundleID "com.rokartur.Micmute.PerAppVolumeDevice"
#define kBGMDeviceName "Micmute Per-App Device"
#define kBGMDeviceUID "BGMDevice"
// Additional metadata
#define kBGMDeviceManufacturer "Micmute"
#define kBGMDeviceModelUID "MicmutePerAppModel"

enum {
    kObjectID_PlugIn = kAudioObjectPlugInObject,
    kObjectID_Device = 2,
    kObjectID_Stream_Output = 3
};

// Default audio characteristics
static const Float64 kBGMDefaultSampleRate = 48000.0;
static const UInt32  kBGMDefaultFrameSize  = 512;     // initial buffer size
static const UInt32  kBGMMinFrameSize      = 128;
static const UInt32  kBGMMaxFrameSize      = 4096;
static const UInt32  kBGMChannelCount      = 2;       // stereo

#ifdef __cplusplus
extern "C" {
#endif
void* BGMPlugIn_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);
#ifdef __cplusplus
}
#endif

#endif /* BGMPlugIn_h */
