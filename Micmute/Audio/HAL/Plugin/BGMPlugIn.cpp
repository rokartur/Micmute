#include "BGMPlugIn.h"
#include "BGMShared.h"

#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <syslog.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {
struct ProcessState {
    pid_t pid = 0;
    float volume = 1.0f;
    bool muted = false;
    std::string bundleID;
};

constexpr Float64 kDefaultSampleRate = 48'000.0;
constexpr UInt32 kDefaultBufferSize = 512;

pthread_mutex_t gMutex = PTHREAD_MUTEX_INITIALIZER;
UInt32 gRefCount = 0;
AudioServerPlugInHostRef gHost = nullptr;
Float64 gNominalSampleRate = kDefaultSampleRate;
UInt32 gBufferFrameSize = kDefaultBufferSize;
std::vector<ProcessState> gProcesses;

ProcessState* findProcess(pid_t pid) {
    for (auto& process : gProcesses) {
        if (process.pid == pid) {
            return &process;
        }
    }
    return nullptr;
}

ProcessState& upsertProcess(pid_t pid) {
    if (auto* existing = findProcess(pid)) {
        return *existing;
    }
    gProcesses.push_back(ProcessState{pid});
    return gProcesses.back();
}

void removeProcess(pid_t pid) {
    gProcesses.erase(std::remove_if(gProcesses.begin(), gProcesses.end(), [pid](const ProcessState& state) {
        return state.pid == pid;
    }), gProcesses.end());
}

std::string resolveBundleID(pid_t pid) {
    char pathBuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(pid, pathBuf, sizeof(pathBuf)) <= 0) {
        return {};
    }

    std::string fullPath(pathBuf);
    auto appPos = fullPath.rfind(".app/");
    std::string bundlePath;
    if (appPos != std::string::npos) {
        auto slashPos = fullPath.rfind('/', appPos);
        if (slashPos != std::string::npos) {
            bundlePath = fullPath.substr(0, appPos + 4);
        }
    }
    if (bundlePath.empty()) {
        return {};
    }

    CFStringRef cfPath = CFStringCreateWithCString(nullptr, bundlePath.c_str(), kCFStringEncodingUTF8);
    if (!cfPath) {
        return {};
    }
    CFURLRef url = CFURLCreateWithFileSystemPath(nullptr, cfPath, kCFURLPOSIXPathStyle, true);
    CFRelease(cfPath);
    if (!url) {
        return {};
    }
    CFBundleRef bundle = CFBundleCreate(nullptr, url);
    CFRelease(url);
    if (!bundle) {
        return {};
    }
    CFStringRef ident = CFBundleGetIdentifier(bundle);
    std::string result;
    if (ident) {
        char idBuf[128] = {0};
        if (CFStringGetCString(ident, idBuf, sizeof(idBuf), kCFStringEncodingUTF8)) {
            result = idBuf;
        }
    }
    CFRelease(bundle);
    return result;
}

void notifyProcessesChanged() {
    if (!gHost) {
        return;
    }
    AudioObjectPropertyAddress addresses[3];
    UInt32 count = 0;
    addresses[count++] = {kBGMPropertyProcessList, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    addresses[count++] = {kBGMPropertyProcessVolume, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    addresses[count++] = {kBGMPropertyProcessMute, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    gHost->PropertiesChanged(gHost, kObjectID_Device, count, addresses);
}

Boolean hasCustomProperty(AudioObjectID objectID, const AudioObjectPropertyAddress* address) {
    if (objectID != kObjectID_Device || address->mScope != kAudioObjectPropertyScopeGlobal) {
        return false;
    }
    switch (address->mSelector) {
        case kBGMPropertyProcessList:
        case kBGMPropertyProcessVolume:
        case kBGMPropertyProcessMute:
        case kBGMPropertyProcessPeak:
        case kBGMPropertyProcessRMS:
        case kBGMPropertyProcessRMSdB:
        case kBGMPropertyGlobalPeak:
        case kBGMPropertyGlobalRMS:
        case kBGMPropertyGlobalRMSdB:
            return true;
        default:
            return false;
    }
}

} // namespace

extern "C" void* BGMPlugIn_Create(CFAllocatorRef, CFUUIDRef requestedTypeUUID) {
    if (CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        static AudioServerPlugInDriverInterface gInterface;
        static bool initialised = false;
        if (!initialised) {
            gInterface.QueryInterface = [](void*, REFIID uuid, LPVOID* outInterface) -> HRESULT {
                CFUUIDRef requestedUUID = CFUUIDCreateFromUUIDBytes(nullptr, uuid);
                HRESULT result = E_NOINTERFACE;
                if (requestedUUID) {
                    if (CFEqual(requestedUUID, IUnknownUUID) || CFEqual(requestedUUID, kAudioServerPlugInDriverInterfaceUUID)) {
                        *outInterface = &gInterface;
                        pthread_mutex_lock(&gMutex);
                        ++gRefCount;
                        pthread_mutex_unlock(&gMutex);
                        result = S_OK;
                    }
                    CFRelease(requestedUUID);
                }
                return result;
            };

            gInterface.AddRef = [](void*) -> ULONG {
                pthread_mutex_lock(&gMutex);
                ++gRefCount;
                ULONG value = gRefCount;
                pthread_mutex_unlock(&gMutex);
                return value;
            };

            gInterface.Release = [](void*) -> ULONG {
                pthread_mutex_lock(&gMutex);
                if (gRefCount > 0) {
                    --gRefCount;
                }
                ULONG value = gRefCount;
                pthread_mutex_unlock(&gMutex);
                return value;
            };

            gInterface.Initialize = [](AudioServerPlugInDriverRef, AudioServerPlugInHostRef host) -> OSStatus {
                pthread_mutex_lock(&gMutex);
                gHost = host;
                pthread_mutex_unlock(&gMutex);
                syslog(LOG_INFO, "Micmute HAL: driver initialized");
                return noErr;
            };

            gInterface.CreateDevice = [](AudioServerPlugInDriverRef, CFDictionaryRef, const AudioServerPlugInClientInfo*, AudioObjectID* outDevice) -> OSStatus {
                if (!outDevice) {
                    return kAudioHardwareBadObjectError;
                }
                *outDevice = kObjectID_Device;
                return noErr;
            };

            gInterface.DestroyDevice = [](AudioServerPlugInDriverRef, AudioObjectID) -> OSStatus {
                return noErr;
            };

            gInterface.AddDeviceClient = [](AudioServerPlugInDriverRef, AudioObjectID objectID, const AudioServerPlugInClientInfo* clientInfo) -> OSStatus {
                if (objectID != kObjectID_Device || !clientInfo) {
                    return noErr;
                }
                pthread_mutex_lock(&gMutex);
                ProcessState& process = upsertProcess(clientInfo->mProcessID);
                if (process.bundleID.empty()) {
                    std::string bundle = resolveBundleID(clientInfo->mProcessID);
                    if (!bundle.empty()) {
                        process.bundleID = bundle;
                    } else {
                        process.bundleID = "pid_" + std::to_string(clientInfo->mProcessID);
                    }
                }
                pthread_mutex_unlock(&gMutex);
                notifyProcessesChanged();
                return noErr;
            };

            gInterface.RemoveDeviceClient = [](AudioServerPlugInDriverRef, AudioObjectID objectID, const AudioServerPlugInClientInfo* clientInfo) -> OSStatus {
                if (objectID != kObjectID_Device || !clientInfo) {
                    return noErr;
                }
                pthread_mutex_lock(&gMutex);
                removeProcess(clientInfo->mProcessID);
                pthread_mutex_unlock(&gMutex);
                notifyProcessesChanged();
                return noErr;
            };

            gInterface.PerformDeviceConfigurationChange = [](AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*) -> OSStatus {
                return noErr;
            };

            gInterface.AbortDeviceConfigurationChange = [](AudioServerPlugInDriverRef, AudioObjectID, UInt64, void*) -> OSStatus {
                return noErr;
            };

            gInterface.HasProperty = [](AudioServerPlugInDriverRef, AudioObjectID objectID, pid_t, const AudioObjectPropertyAddress* address) -> Boolean {
                if (!address) {
                    return false;
                }
                if (objectID == kObjectID_PlugIn) {
                    switch (address->mSelector) {
                        case kAudioObjectPropertyBaseClass:
                        case kAudioObjectPropertyClass:
                        case kAudioObjectPropertyManufacturer:
                        case kAudioObjectPropertyName:
                            return true;
                        default:
                            return false;
                    }
                }
                if (objectID == kObjectID_Device) {
                    switch (address->mSelector) {
                        case kAudioObjectPropertyBaseClass:
                        case kAudioObjectPropertyClass:
                        case kAudioObjectPropertyName:
                        case kAudioObjectPropertyManufacturer:
                        case kAudioDevicePropertyDeviceUID:
                        case kAudioDevicePropertyModelUID:
                        case kAudioDevicePropertyNominalSampleRate:
                        case kAudioDevicePropertyAvailableNominalSampleRates:
                        case kAudioDevicePropertyBufferFrameSize:
                        case kAudioDevicePropertyBufferFrameSizeRange:
                        case kAudioDevicePropertyStreams:
                            return true;
                        default:
                            return hasCustomProperty(objectID, address);
                    }
                }
                return false;
            };

            gInterface.IsPropertySettable = [](AudioServerPlugInDriverRef, AudioObjectID objectID, pid_t, const AudioObjectPropertyAddress* address, Boolean* outSettable) -> OSStatus {
                if (!address || !outSettable) {
                    return kAudioHardwareBadObjectError;
                }
                Boolean settable = false;
                if (objectID == kObjectID_Device) {
                    switch (address->mSelector) {
                        case kAudioDevicePropertyNominalSampleRate:
                        case kAudioDevicePropertyBufferFrameSize:
                        case kBGMPropertyProcessVolume:
                        case kBGMPropertyProcessMute:
                            settable = true;
                            break;
                        default:
                            break;
                    }
                }
                *outSettable = settable;
                return noErr;
            };

            gInterface.GetPropertyDataSize = [](AudioServerPlugInDriverRef, AudioObjectID objectID, pid_t, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32* outDataSize) -> OSStatus {
                if (!address || !outDataSize) {
                    return kAudioHardwareBadObjectError;
                }
                UInt32 size = 0;
                if (objectID == kObjectID_PlugIn) {
                    switch (address->mSelector) {
                        case kAudioObjectPropertyBaseClass:
                        case kAudioObjectPropertyClass:
                            size = sizeof(AudioClassID);
                            break;
                        case kAudioObjectPropertyManufacturer:
                        case kAudioObjectPropertyName:
                            size = sizeof(CFStringRef);
                            break;
                        default:
                            return kAudioHardwareUnknownPropertyError;
                    }
                } else if (objectID == kObjectID_Device) {
                    switch (address->mSelector) {
                        case kAudioObjectPropertyBaseClass:
                        case kAudioObjectPropertyClass:
                            size = sizeof(AudioClassID);
                            break;
                        case kAudioObjectPropertyName:
                        case kAudioObjectPropertyManufacturer:
                        case kAudioDevicePropertyDeviceUID:
                        case kAudioDevicePropertyModelUID:
                            size = sizeof(CFStringRef);
                            break;
                        case kAudioDevicePropertyNominalSampleRate:
                            size = sizeof(Float64);
                            break;
                        case kAudioDevicePropertyAvailableNominalSampleRates:
                            size = sizeof(AudioValueRange);
                            break;
                        case kAudioDevicePropertyBufferFrameSize:
                            size = sizeof(UInt32);
                            break;
                        case kAudioDevicePropertyBufferFrameSizeRange:
                            size = sizeof(AudioValueRange);
                            break;
                        case kAudioDevicePropertyStreams:
                            size = 0;
                            break;
                        case kBGMPropertyProcessList: {
                            pthread_mutex_lock(&gMutex);
                            size = static_cast<UInt32>(gProcesses.size() * sizeof(BGMProcessEntry));
                            pthread_mutex_unlock(&gMutex);
                            break;
                        }
                        case kBGMPropertyProcessVolume:
                        case kBGMPropertyProcessMute:
                        case kBGMPropertyProcessPeak:
                        case kBGMPropertyProcessRMS:
                        case kBGMPropertyProcessRMSdB:
                        case kBGMPropertyGlobalPeak:
                        case kBGMPropertyGlobalRMS:
                        case kBGMPropertyGlobalRMSdB:
                            size = sizeof(Float32);
                            break;
                        default:
                            return kAudioHardwareUnknownPropertyError;
                    }
                } else {
                    return kAudioHardwareBadObjectError;
                }
                *outDataSize = size;
                return noErr;
            };

            gInterface.GetPropertyData = [](AudioServerPlugInDriverRef, AudioObjectID objectID, pid_t, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData) -> OSStatus {
                if (!address || !outDataSize || (!outData && inDataSize > 0)) {
                    return kAudioHardwareBadObjectError;
                }
                if (objectID == kObjectID_PlugIn) {
                    switch (address->mSelector) {
                        case kAudioObjectPropertyBaseClass:
                        case kAudioObjectPropertyClass: {
                            auto* classID = static_cast<AudioClassID*>(outData);
                            *classID = kAudioPlugInClassID;
                            *outDataSize = sizeof(AudioClassID);
                            return noErr;
                        }
                        case kAudioObjectPropertyManufacturer:
                        case kAudioObjectPropertyName: {
                            CFStringRef value = CFSTR("Micmute");
                            if (outDataSize && *outDataSize == sizeof(CFStringRef)) {
                                *static_cast<CFStringRef*>(outData) = value;
                                *outDataSize = sizeof(CFStringRef);
                                return noErr;
                            }
                            return kAudioHardwareBadPropertySizeError;
                        }
                        default:
                            return kAudioHardwareUnknownPropertyError;
                    }
                }

                if (objectID != kObjectID_Device) {
                    return kAudioHardwareBadObjectError;
                }

                switch (address->mSelector) {
                    case kAudioObjectPropertyBaseClass:
                    case kAudioObjectPropertyClass: {
                        auto* classID = static_cast<AudioClassID*>(outData);
                        *classID = static_cast<AudioClassID>(address->mSelector == kAudioObjectPropertyBaseClass ? kAudioObjectClassID : kAudioDeviceClassID);
                        *outDataSize = sizeof(AudioClassID);
                        return noErr;
                    }
                    case kAudioObjectPropertyName:
                    case kAudioObjectPropertyManufacturer:
                    case kAudioDevicePropertyDeviceUID:
                    case kAudioDevicePropertyModelUID: {
                        CFStringRef value = nullptr;
                        if (address->mSelector == kAudioObjectPropertyName) {
                            value = CFSTR("Micmute Per-App Device");
                        } else if (address->mSelector == kAudioObjectPropertyManufacturer) {
                            value = CFSTR("Micmute");
                        } else if (address->mSelector == kAudioDevicePropertyDeviceUID) {
                            value = CFSTR("com.rokartur.Micmute.PerAppVolumeDevice:device");
                        } else {
                            value = CFSTR("com.rokartur.Micmute.PerAppVolumeDevice:model");
                        }
                        if (outDataSize && *outDataSize == sizeof(CFStringRef)) {
                            *static_cast<CFStringRef*>(outData) = value;
                            *outDataSize = sizeof(CFStringRef);
                            return noErr;
                        }
                        return kAudioHardwareBadPropertySizeError;
                    }
                    case kAudioDevicePropertyNominalSampleRate: {
                        *static_cast<Float64*>(outData) = gNominalSampleRate;
                        *outDataSize = sizeof(Float64);
                        return noErr;
                    }
                    case kAudioDevicePropertyAvailableNominalSampleRates: {
                        AudioValueRange* range = static_cast<AudioValueRange*>(outData);
                        range->mMinimum = kDefaultSampleRate;
                        range->mMaximum = kDefaultSampleRate;
                        *outDataSize = sizeof(AudioValueRange);
                        return noErr;
                    }
                    case kAudioDevicePropertyBufferFrameSize: {
                        *static_cast<UInt32*>(outData) = gBufferFrameSize;
                        *outDataSize = sizeof(UInt32);
                        return noErr;
                    }
                    case kAudioDevicePropertyBufferFrameSizeRange: {
                        AudioValueRange* range = static_cast<AudioValueRange*>(outData);
                        range->mMinimum = 128;
                        range->mMaximum = 4096;
                        *outDataSize = sizeof(AudioValueRange);
                        return noErr;
                    }
                    case kAudioDevicePropertyStreams: {
                        *outDataSize = 0;
                        return noErr;
                    }
                    case kBGMPropertyProcessList: {
                        pthread_mutex_lock(&gMutex);
                        std::vector<BGMProcessEntry> entries;
                        entries.reserve(gProcesses.size());
                        for (const auto& process : gProcesses) {
                            BGMProcessEntry entry{};
                            entry.pid = process.pid;
                            entry.volume = process.volume;
                            entry.muted = process.muted ? 1U : 0U;
                            strncpy(entry.bundleID, process.bundleID.c_str(), sizeof(entry.bundleID) - 1);
                            entries.push_back(entry);
                        }
                        const UInt32 bytesToCopy = static_cast<UInt32>(entries.size() * sizeof(BGMProcessEntry));
                        if (bytesToCopy > inDataSize) {
                            pthread_mutex_unlock(&gMutex);
                            return kAudioHardwareBadPropertySizeError;
                        }
                        if (bytesToCopy > 0) {
                            std::memcpy(outData, entries.data(), bytesToCopy);
                        }
                        *outDataSize = bytesToCopy;
                        pthread_mutex_unlock(&gMutex);
                        return noErr;
                    }
                    case kBGMPropertyProcessVolume:
                    case kBGMPropertyProcessMute: {
                        if (qualifierDataSize != sizeof(pid_t) || !qualifierData) {
                            return kAudioHardwareBadPropertySizeError;
                        }
                        pid_t pid = *static_cast<const pid_t*>(qualifierData);
                        pthread_mutex_lock(&gMutex);
                        ProcessState* process = findProcess(pid);
                        Float32 value = (address->mSelector == kBGMPropertyProcessMute) ? 0.0f : 1.0f;
                        if (process) {
                            value = (address->mSelector == kBGMPropertyProcessMute) ? (process->muted ? 1.0f : 0.0f)
                                                                                     : process->volume;
                        }
                        pthread_mutex_unlock(&gMutex);
                        *static_cast<Float32*>(outData) = value;
                        *outDataSize = sizeof(Float32);
                        return noErr;
                    }
                    case kBGMPropertyProcessPeak:
                    case kBGMPropertyProcessRMS:
                    case kBGMPropertyProcessRMSdB:
                    case kBGMPropertyGlobalPeak:
                    case kBGMPropertyGlobalRMS:
                    case kBGMPropertyGlobalRMSdB: {
                        *static_cast<Float32*>(outData) = 0.0f;
                        *outDataSize = sizeof(Float32);
                        return noErr;
                    }
                    default:
                        return kAudioHardwareUnknownPropertyError;
                }
            };

            gInterface.SetPropertyData = [](AudioServerPlugInDriverRef, AudioObjectID objectID, pid_t, const AudioObjectPropertyAddress* address, UInt32 qualifierDataSize, const void* qualifierData, UInt32 inDataSize, const void* inData) -> OSStatus {
                if (!address) {
                    return kAudioHardwareBadObjectError;
                }
                if (objectID != kObjectID_Device) {
                    return kAudioHardwareBadObjectError;
                }
                switch (address->mSelector) {
                    case kAudioDevicePropertyNominalSampleRate: {
                        if (inDataSize != sizeof(Float64) || !inData) {
                            return kAudioHardwareBadPropertySizeError;
                        }
                        pthread_mutex_lock(&gMutex);
                        gNominalSampleRate = *static_cast<const Float64*>(inData);
                        pthread_mutex_unlock(&gMutex);
                        return noErr;
                    }
                    case kAudioDevicePropertyBufferFrameSize: {
                        if (inDataSize != sizeof(UInt32) || !inData) {
                            return kAudioHardwareBadPropertySizeError;
                        }
                        pthread_mutex_lock(&gMutex);
                        gBufferFrameSize = *static_cast<const UInt32*>(inData);
                        pthread_mutex_unlock(&gMutex);
                        return noErr;
                    }
                    case kBGMPropertyProcessVolume:
                    case kBGMPropertyProcessMute: {
                        if (qualifierDataSize != sizeof(pid_t) || !qualifierData || inDataSize != sizeof(Float32) || !inData) {
                            return kAudioHardwareBadPropertySizeError;
                        }
                        pid_t pid = *static_cast<const pid_t*>(qualifierData);
                        Float32 value = *static_cast<const Float32*>(inData);
                        pthread_mutex_lock(&gMutex);
                        ProcessState& process = upsertProcess(pid);
                        if (address->mSelector == kBGMPropertyProcessVolume) {
                            process.volume = std::clamp(value, 0.0f, 2.0f);
                        } else {
                            process.muted = value >= 0.5f;
                        }
                        if (process.bundleID.empty()) {
                            std::string bundle = resolveBundleID(pid);
                            if (!bundle.empty()) {
                                process.bundleID = bundle;
                            } else {
                                process.bundleID = "pid_" + std::to_string(pid);
                            }
                        }
                        pthread_mutex_unlock(&gMutex);
                        notifyProcessesChanged();
                        return noErr;
                    }
                    default:
                        return kAudioHardwareUnknownPropertyError;
                }
            };

            gInterface.StartIO = [](AudioServerPlugInDriverRef, AudioObjectID, UInt32) -> OSStatus {
                return noErr;
            };

            gInterface.StopIO = [](AudioServerPlugInDriverRef, AudioObjectID, UInt32) -> OSStatus {
                return noErr;
            };

            gInterface.GetZeroTimeStamp = [](AudioServerPlugInDriverRef, AudioObjectID, UInt32, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) -> OSStatus {
                if (outSampleTime) {
                    *outSampleTime = 0.0;
                }
                if (outHostTime) {
                    *outHostTime = mach_absolute_time();
                }
                if (outSeed) {
                    *outSeed = 1;
                }
                return noErr;
            };

            gInterface.WillDoIOOperation = [](AudioServerPlugInDriverRef, AudioObjectID, UInt32, UInt32, Boolean* outWillDo, Boolean* outWillDoInPlace) -> OSStatus {
                if (outWillDo) {
                    *outWillDo = false;
                }
                if (outWillDoInPlace) {
                    *outWillDoInPlace = false;
                }
                return noErr;
            };

            gInterface.BeginIOOperation = nullptr;
            gInterface.DoIOOperation = nullptr;
            gInterface.EndIOOperation = nullptr;

            initialised = true;
        }
        return &gInterface;
    }
    return nullptr;
}
