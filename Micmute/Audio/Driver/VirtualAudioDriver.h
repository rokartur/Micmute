#ifndef VIRTUAL_AUDIO_DRIVER_H
#define VIRTUAL_AUDIO_DRIVER_H

#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "Shared/VolumeControlSharedState.hpp"

class VirtualAudioDriver {
public:
    static VirtualAudioDriver& shared();

    OSStatus initialize();
    OSStatus shutdown();

    OSStatus setApplicationVolume(CFStringRef bundleID, Float32 volume);
    OSStatus getApplicationVolume(CFStringRef bundleID, Float32* outVolume) const;
    OSStatus muteApplication(CFStringRef bundleID, Boolean mute);
    Boolean isApplicationMuted(CFStringRef bundleID) const;

    std::vector<std::string> snapshotBundleIDs() const;
    void resetState();

private:
    VirtualAudioDriver();
    ~VirtualAudioDriver() = default;
    VirtualAudioDriver(const VirtualAudioDriver&) = delete;
    VirtualAudioDriver& operator=(const VirtualAudioDriver&) = delete;

    bool ensureSharedMemoryLocked(std::string* errorMessage = nullptr) const;
    micmute::driver::VolumeControlSharedState* sharedState() const;
    bool updateEntry(const std::string& bundleID, float gain, bool mute);
    std::optional<micmute::driver::ApplicationVolumeInfo> entryForBundleID(const std::string& bundleID) const;

    mutable std::mutex m_mutex;
    mutable micmute::driver::SharedMemoryAccessor m_sharedMemory;
    uid_t m_uid;
};

#endif /* VIRTUAL_AUDIO_DRIVER_H */
