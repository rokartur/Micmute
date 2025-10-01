#include "VirtualAudioDriver.h"

#include <AudioToolbox/AudioServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <cstring>
#include <os/log.h>
#include <unistd.h>

using micmute::driver::ApplicationVolumeInfo;
using micmute::driver::FindApplicationVolume;
using micmute::driver::SnapshotApplicationVolumes;
using micmute::driver::UpdateApplicationVolume;

namespace {
std::string CFStringToStdString(CFStringRef cfString) {
    if (cfString == nullptr) {
        return std::string();
    }

    const CFIndex length = CFStringGetLength(cfString);
    const CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
    std::string result(static_cast<size_t>(maxSize), '\0');

    if (CFStringGetCString(cfString, result.data(), maxSize, kCFStringEncodingUTF8)) {
        result.resize(std::char_traits<char>::length(result.c_str()));
        return result;
    }

    return std::string();
}
}

VirtualAudioDriver& VirtualAudioDriver::shared() {
    static VirtualAudioDriver instance;
    return instance;
}

VirtualAudioDriver::VirtualAudioDriver()
    : m_uid(getuid()) {}

OSStatus VirtualAudioDriver::initialize() {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::string error;
    if (!ensureSharedMemoryLocked(&error)) {
        os_log_error(OS_LOG_DEFAULT, "Failed to map shared memory: %{public}s", error.c_str());
        return kAudioHardwareIllegalOperationError;
    }
    return noErr;
}

OSStatus VirtualAudioDriver::shutdown() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_sharedMemory.isValid()) {
        m_sharedMemory.unmap();
    }
    return noErr;
}

OSStatus VirtualAudioDriver::setApplicationVolume(CFStringRef bundleID, Float32 volume) {
    if (bundleID == nullptr) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(m_mutex);
    std::string bundle = CFStringToStdString(bundleID);
    if (bundle.empty()) {
        return kAudioHardwareBadObjectError;
    }

    const float clamped = std::clamp(volume, 0.0f, 4.0f);
    auto current = entryForBundleID(bundle);
    const bool mute = current ? current->mute : false;
    if (!updateEntry(bundle, clamped, mute)) {
        return kAudioHardwareIllegalOperationError;
    }
    return noErr;
}

OSStatus VirtualAudioDriver::getApplicationVolume(CFStringRef bundleID, Float32* outVolume) const {
    if (bundleID == nullptr || outVolume == nullptr) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(m_mutex);
    auto bundle = CFStringToStdString(bundleID);
    if (bundle.empty()) {
        return kAudioHardwareBadObjectError;
    }

    auto info = entryForBundleID(bundle);
    if (!info) {
        *outVolume = 1.0f;
        return kAudioHardwareUnknownPropertyError;
    }

    *outVolume = info->gain;
    return noErr;
}

OSStatus VirtualAudioDriver::muteApplication(CFStringRef bundleID, Boolean mute) {
    if (bundleID == nullptr) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(m_mutex);
    std::string bundle = CFStringToStdString(bundleID);
    if (bundle.empty()) {
        return kAudioHardwareBadObjectError;
    }

    auto current = entryForBundleID(bundle);
    const float gain = current ? current->gain : 1.0f;
    if (!updateEntry(bundle, gain, mute)) {
        return kAudioHardwareIllegalOperationError;
    }
    return noErr;
}

Boolean VirtualAudioDriver::isApplicationMuted(CFStringRef bundleID) const {
    if (bundleID == nullptr) {
        return false;
    }

    std::lock_guard<std::mutex> lock(m_mutex);
    auto bundle = CFStringToStdString(bundleID);
    if (bundle.empty()) {
        return false;
    }

    auto info = entryForBundleID(bundle);
    return info ? info->mute : false;
}

std::vector<std::string> VirtualAudioDriver::snapshotBundleIDs() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<std::string> identifiers;
    auto* state = sharedState();
    if (state == nullptr) {
        return identifiers;
    }

    const auto snapshot = SnapshotApplicationVolumes(*state);
    identifiers.reserve(snapshot.size());
    for (const auto& info : snapshot) {
        identifiers.push_back(info.bundleID);
    }
    return identifiers;
}

void VirtualAudioDriver::resetState() {
    std::lock_guard<std::mutex> lock(m_mutex);
    auto* state = sharedState();
    if (state == nullptr) {
        return;
    }

    std::memset(state, 0, micmute::driver::SharedMemorySize());
    state->header.version.store(micmute::driver::kSharedStateVersion, std::memory_order_relaxed);
    state->header.entryCount.store(0, std::memory_order_relaxed);
    state->header.generation.store(1, std::memory_order_relaxed);
    state->header.lastWriterPID.store(static_cast<std::uint64_t>(getpid()), std::memory_order_relaxed);
    state->header.lastWriterUID.store(static_cast<std::uint64_t>(getuid()), std::memory_order_relaxed);
}

bool VirtualAudioDriver::ensureSharedMemoryLocked(std::string* errorMessage) const {
    if (m_sharedMemory.isValid()) {
        return true;
    }

    std::string localError;
    if (!m_sharedMemory.mapForUID(m_uid, true, &localError)) {
        if (errorMessage != nullptr) {
            *errorMessage = localError;
        }
        return false;
    }
    return true;
}

micmute::driver::VolumeControlSharedState* VirtualAudioDriver::sharedState() const {
    if (!m_sharedMemory.isValid()) {
        std::string error;
        if (!ensureSharedMemoryLocked(&error)) {
            os_log_error(OS_LOG_DEFAULT, "Shared memory unavailable: %{public}s", error.c_str());
            return nullptr;
        }
    }
    return m_sharedMemory.state();
}

bool VirtualAudioDriver::updateEntry(const std::string& bundleID, float gain, bool mute) {
    std::string error;
    if (!ensureSharedMemoryLocked(&error)) {
        os_log_error(OS_LOG_DEFAULT, "Unable to update entry for %{public}s: %{public}s", bundleID.c_str(), error.c_str());
        return false;
    }

    auto* state = m_sharedMemory.state();
    if (state == nullptr) {
        return false;
    }

    return UpdateApplicationVolume(*state, bundleID, gain, mute);
}

std::optional<ApplicationVolumeInfo> VirtualAudioDriver::entryForBundleID(const std::string& bundleID) const {
    std::string error;
    if (!ensureSharedMemoryLocked(&error)) {
        os_log_error(OS_LOG_DEFAULT, "Unable to read entry for %{public}s: %{public}s", bundleID.c_str(), error.c_str());
        return std::nullopt;
    }

    auto* state = m_sharedMemory.state();
    if (state == nullptr) {
        return std::nullopt;
    }

    return FindApplicationVolume(*state, bundleID);
}
