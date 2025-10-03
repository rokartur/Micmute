#include "VolumeControlSharedState.hpp"

#import <AudioToolbox/AudioServices.h>
#import <CoreAudio/AudioHardware.h>
#import <CoreAudio/AudioServerPlugIn.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <os/log.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <mach/mach_time.h>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>
#include <libproc.h>

using namespace micmute::driver;

namespace {

static const CFStringRef kVolumeControlDriverName = CFSTR("Micmute Volume Control Driver");
static const CFStringRef kVolumeControlDriverManufacturer = CFSTR("Micmute");
static const CFStringRef kVolumeControlDeviceName = CFSTR("Micmute Virtual Output");
static const CFStringRef kVolumeControlDeviceUID = CFSTR("com.rokartur.Micmute.VolumeControlDriver:device");
static const CFStringRef kVolumeControlDeviceModelUID = CFSTR("com.rokartur.Micmute.VolumeControlDriver:model");
static const CFStringRef kVolumeControlStreamName = CFSTR("Micmute Output Stream");

#ifndef kAudioStreamDirection_Output
static const UInt32 kAudioStreamDirection_Output = 1;
#endif

constexpr AudioObjectID kPlugInObjectID = kAudioObjectPlugInObject;
constexpr AudioObjectID kDeviceObjectID = 'miCD';
constexpr AudioObjectID kOutputStreamObjectID = 'miCS';

constexpr UInt32 kDefaultChannelCount = 2;
constexpr Float64 kDefaultSampleRate = 48000.0;
constexpr Float64 kAlternateSampleRate = 44100.0;
constexpr UInt32 kDefaultBufferFrameSize = 256;
constexpr UInt32 kMinimumBufferFrameSize = 128;
constexpr UInt32 kMaximumBufferFrameSize = 2048;
constexpr UInt32 kDefaultLatency = 32;
constexpr UInt32 kDefaultSafetyOffset = 32;
constexpr float kGainEpsilon = 1e-6f;

std::atomic<UInt32> gDriverRefCount{1};
auto gLog = os_log_create("com.rokartur.Micmute.Driver", "VolumeControlDriver");
AudioServerPlugInHostRef gPlugInHost = nullptr;

struct ClientState {
    pid_t pid = -1;
    uid_t uid = 0;
    std::string bundleID;
};

struct DeviceState {
    Float64 sampleRate = kDefaultSampleRate;
    UInt32 bufferFrameSize = kDefaultBufferFrameSize;
    UInt32 latency = kDefaultLatency;
    UInt32 safetyOffset = kDefaultSafetyOffset;
    bool isRunning = false;
    UInt64 anchorHostTime = 0;
    UInt64 sampleCounter = 0;
    UInt64 timestampSeed = 1;
    AudioStreamBasicDescription virtualFormat{};
    AudioStreamBasicDescription physicalFormat{};
    std::unordered_map<pid_t, ClientState> activeClients;
};

struct DriverGlobals {
    std::mutex mutex;
    bool initialized = false;
    bool deviceCreated = false;
    DeviceState device;
    std::unordered_map<uid_t, SharedMemoryAccessor> sharedMemoryByUser;
} gDriverGlobals;

mach_timebase_info_data_t GetMachTimebase() {
    static mach_timebase_info_data_t timebase{0, 0};
    static std::once_flag once;
    std::call_once(once, [] {
        mach_timebase_info(&timebase);
    });
    return timebase;
}

AudioStreamBasicDescription MakeFloatFormat(Float64 sampleRate) {
    AudioStreamBasicDescription description{};
    description.mSampleRate = sampleRate;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    description.mBitsPerChannel = sizeof(Float32) * 8;
    description.mChannelsPerFrame = kDefaultChannelCount;
    description.mBytesPerFrame = sizeof(Float32) * kDefaultChannelCount;
    description.mFramesPerPacket = 1;
    description.mBytesPerPacket = description.mBytesPerFrame * description.mFramesPerPacket;
    description.mReserved = 0;
    return description;
}

UInt64 SamplesToHostTicks(UInt64 sampleCount, Float64 sampleRate) {
    if (sampleRate <= 0.0) {
        return 0;
    }

    const mach_timebase_info_data_t timebase = GetMachTimebase();
    const long double seconds = static_cast<long double>(sampleCount) / static_cast<long double>(sampleRate);
    const long double nanoseconds = seconds * 1'000'000'000.0L;
    const long double hostTicks = nanoseconds * static_cast<long double>(timebase.denom) / static_cast<long double>(timebase.numer);
    return static_cast<UInt64>(hostTicks);
}

Float64 HostTicksToSamples(UInt64 hostDelta, Float64 sampleRate) {
    if (sampleRate <= 0.0) {
        return 0.0;
    }

    const mach_timebase_info_data_t timebase = GetMachTimebase();
    const long double nanoseconds = static_cast<long double>(hostDelta) * static_cast<long double>(timebase.numer) / static_cast<long double>(timebase.denom);
    const long double seconds = nanoseconds / 1'000'000'000.0L;
    return static_cast<Float64>(seconds * sampleRate);
}

std::string CFStringToStdString(CFStringRef value) {
    if (value == nullptr) {
        return {};
    }

    const CFRange range = CFRangeMake(0, CFStringGetLength(value));
    const CFIndex maxSize = CFStringGetMaximumSizeForEncoding(range.length, kCFStringEncodingUTF8) + 1;
    std::string buffer(static_cast<size_t>(maxSize), '\0');
    if (CFStringGetBytes(value, range, kCFStringEncodingUTF8, '?', false, reinterpret_cast<UInt8*>(buffer.data()), maxSize, nullptr)) {
        buffer.resize(std::strlen(buffer.c_str()));
        return buffer;
    }
    return {};
}

bool IsPluginObject(AudioObjectID objectID) {
    return objectID == kPlugInObjectID;
}

bool IsDeviceObject(AudioObjectID objectID) {
    return objectID == kDeviceObjectID;
}

bool IsStreamObject(AudioObjectID objectID) {
    return objectID == kOutputStreamObjectID;
}

bool MatchesAddress(const AudioObjectPropertyAddress& address, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal, AudioObjectPropertyElement element = kAudioObjectPropertyElementMaster) {
    const bool selectorMatches = address.mSelector == selector;
    const bool scopeMatches = (address.mScope == scope) || (address.mScope == kAudioObjectPropertyScopeWildcard);
    const bool elementMatches = (address.mElement == element) || (address.mElement == kAudioObjectPropertyElementWildcard);
    return selectorMatches && scopeMatches && elementMatches;
}

std::optional<uid_t> ResolveUIDForPID(pid_t pid) {
    if (pid <= 0) {
        return std::nullopt;
    }

    struct proc_bsdshortinfo processInfo {
    };
    const int result = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &processInfo, sizeof(processInfo));
    if (result != sizeof(processInfo)) {
        return std::nullopt;
    }
    return static_cast<uid_t>(processInfo.pbsi_uid);
}

std::optional<std::string> ResolveBundleIdentifierForPID(pid_t pid) {
    CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (attributes == nullptr) {
        return std::nullopt;
    }

    CFNumberRef pidNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    if (pidNumber == nullptr) {
        CFRelease(attributes);
        return std::nullopt;
    }

    CFDictionarySetValue(attributes, kSecGuestAttributePid, pidNumber);

    SecCodeRef code = nullptr;
    const OSStatus copyStatus = SecCodeCopyGuestWithAttributes(nullptr, attributes, kSecCSDefaultFlags, &code);
    CFRelease(pidNumber);
    CFRelease(attributes);
    if (copyStatus != errSecSuccess || code == nullptr) {
        return std::nullopt;
    }

    CFDictionaryRef signingInfo = nullptr;
    const OSStatus infoStatus = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &signingInfo);
    CFRelease(code);
    if (infoStatus != errSecSuccess || signingInfo == nullptr) {
        return std::nullopt;
    }

    CFStringRef identifier = static_cast<CFStringRef>(CFDictionaryGetValue(signingInfo, kSecCodeInfoIdentifier));
    std::optional<std::string> bundleID;
    if (identifier != nullptr) {
        bundleID = CFStringToStdString(identifier);
    }
    CFRelease(signingInfo);
    return bundleID;
}

} // namespace

#pragma mark - Forward declarations

HRESULT VolumeControlDriver_QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface);
ULONG VolumeControlDriver_AddRef(void* inDriver);
ULONG VolumeControlDriver_Release(void* inDriver);
OSStatus VolumeControlDriver_Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
OSStatus VolumeControlDriver_CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID);
OSStatus VolumeControlDriver_DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID);
OSStatus VolumeControlDriver_AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
OSStatus VolumeControlDriver_RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
OSStatus VolumeControlDriver_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
OSStatus VolumeControlDriver_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
Boolean VolumeControlDriver_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress);
OSStatus VolumeControlDriver_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable);
OSStatus VolumeControlDriver_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize);
OSStatus VolumeControlDriver_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
OSStatus VolumeControlDriver_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData);
OSStatus VolumeControlDriver_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
OSStatus VolumeControlDriver_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
OSStatus VolumeControlDriver_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
OSStatus VolumeControlDriver_WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace);
OSStatus VolumeControlDriver_BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
OSStatus VolumeControlDriver_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
OSStatus VolumeControlDriver_EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);

AudioServerPlugInDriverInterface gAudioServerPlugInDriverInterface = {
    nullptr,
    VolumeControlDriver_QueryInterface,
    VolumeControlDriver_AddRef,
    VolumeControlDriver_Release,
    VolumeControlDriver_Initialize,
    VolumeControlDriver_CreateDevice,
    VolumeControlDriver_DestroyDevice,
    VolumeControlDriver_AddDeviceClient,
    VolumeControlDriver_RemoveDeviceClient,
    VolumeControlDriver_PerformDeviceConfigurationChange,
    VolumeControlDriver_AbortDeviceConfigurationChange,
    VolumeControlDriver_HasProperty,
    VolumeControlDriver_IsPropertySettable,
    VolumeControlDriver_GetPropertyDataSize,
    VolumeControlDriver_GetPropertyData,
    VolumeControlDriver_SetPropertyData,
    VolumeControlDriver_StartIO,
    VolumeControlDriver_StopIO,
    VolumeControlDriver_GetZeroTimeStamp,
    VolumeControlDriver_WillDoIOOperation,
    VolumeControlDriver_BeginIOOperation,
    VolumeControlDriver_DoIOOperation,
    VolumeControlDriver_EndIOOperation,
};

#pragma mark - Factory Export

extern "C" void* VirtualAudioDriverFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    if (!CFEqual(typeID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }

    return &gAudioServerPlugInDriverInterface;
}

#pragma mark - IUnknown-style plumbing

HRESULT VolumeControlDriver_QueryInterface(void* /*inDriver*/, REFIID inUUID, LPVOID* outInterface) {
    (void)inUUID;
    if (outInterface == nullptr) {
        return E_POINTER;
    }

    *outInterface = &gAudioServerPlugInDriverInterface;
    VolumeControlDriver_AddRef(nullptr);
    return S_OK;
}

ULONG VolumeControlDriver_AddRef(void* /*inDriver*/) {
    return ++gDriverRefCount;
}

ULONG VolumeControlDriver_Release(void* /*inDriver*/) {
    UInt32 newValue = --gDriverRefCount;
    return newValue;
}

#pragma mark - AudioServerPlugInDriverInterface callbacks

OSStatus VolumeControlDriver_Initialize(AudioServerPlugInDriverRef /*inDriver*/, AudioServerPlugInHostRef inHost) {
    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    if (gDriverGlobals.initialized) {
        return noErr;
    }

    gPlugInHost = inHost;
    gDriverGlobals.device.sampleRate = kDefaultSampleRate;
    gDriverGlobals.device.bufferFrameSize = kDefaultBufferFrameSize;
    gDriverGlobals.device.virtualFormat = MakeFloatFormat(gDriverGlobals.device.sampleRate);
    gDriverGlobals.device.physicalFormat = gDriverGlobals.device.virtualFormat;
    gDriverGlobals.device.sampleCounter = 0;
    gDriverGlobals.device.timestampSeed = 1;
    gDriverGlobals.initialized = true;
    os_log_info(gLog, "VolumeControlDriver initialized");
    return noErr;
}

OSStatus VolumeControlDriver_CreateDevice(AudioServerPlugInDriverRef /*inDriver*/, CFDictionaryRef /*inDescription*/, const AudioServerPlugInClientInfo* /*inClientInfo*/, AudioObjectID* outDeviceObjectID) {
    if (outDeviceObjectID == nullptr) {
        return kAudioHardwareIllegalOperationError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    gDriverGlobals.device.activeClients.clear();
    gDriverGlobals.device.sampleCounter = 0;
    gDriverGlobals.device.timestampSeed = 1;
    gDriverGlobals.device.isRunning = false;
    gDriverGlobals.device.anchorHostTime = mach_absolute_time();
    gDriverGlobals.deviceCreated = true;

    *outDeviceObjectID = kDeviceObjectID;
    os_log_info(gLog, "Micmute virtual device created (objectID=%{public}u)", kDeviceObjectID);
    return noErr;
}

OSStatus VolumeControlDriver_DestroyDevice(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID) {
    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    gDriverGlobals.device.activeClients.clear();
    for (auto& entry : gDriverGlobals.sharedMemoryByUser) {
        entry.second.unmap();
    }
    gDriverGlobals.sharedMemoryByUser.clear();
    gDriverGlobals.deviceCreated = false;
    gDriverGlobals.device.isRunning = false;
    os_log_info(gLog, "Micmute virtual device destroyed");
    return noErr;
}

OSStatus VolumeControlDriver_AddDeviceClient(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    if (inClientInfo != nullptr) {
        ClientState state;
        state.pid = inClientInfo->mProcessID;
        if (auto uid = ResolveUIDForPID(inClientInfo->mProcessID)) {
            state.uid = *uid;
        }
        if (auto bundleID = ResolveBundleIdentifierForPID(inClientInfo->mProcessID)) {
            state.bundleID = *bundleID;
        }
        gDriverGlobals.device.activeClients[state.pid] = state;

        auto mapping = gDriverGlobals.sharedMemoryByUser.find(state.uid);
        if (mapping == gDriverGlobals.sharedMemoryByUser.end()) {
            SharedMemoryAccessor accessor;
            std::string error;
            if (!accessor.mapForUID(state.uid, false, &error)) {
                os_log_error(gLog, "Failed to map shared memory for uid %{public}d: %{public}s", state.uid, error.c_str());
            } else {
                gDriverGlobals.sharedMemoryByUser.emplace(state.uid, std::move(accessor));
            }
        }

        os_log_debug(gLog, "Added client pid=%{public}d uid=%{public}d bundle=%{public}s", state.pid, state.uid, state.bundleID.c_str());
    }
    return noErr;
}

OSStatus VolumeControlDriver_RemoveDeviceClient(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    if (inClientInfo != nullptr) {
    const pid_t pid = inClientInfo->mProcessID;
        uid_t uid = 0;
        if (auto it = gDriverGlobals.device.activeClients.find(pid); it != gDriverGlobals.device.activeClients.end()) {
            uid = it->second.uid;
            gDriverGlobals.device.activeClients.erase(it);
        }

        bool otherClientsForUID = false;
        for (const auto& entry : gDriverGlobals.device.activeClients) {
            if (entry.second.uid == uid) {
                otherClientsForUID = true;
                break;
            }
        }

        if (!otherClientsForUID) {
            if (auto accessor = gDriverGlobals.sharedMemoryByUser.find(uid); accessor != gDriverGlobals.sharedMemoryByUser.end()) {
                accessor->second.unmap();
                gDriverGlobals.sharedMemoryByUser.erase(accessor);
            }
        }

        os_log_debug(gLog, "Removed client pid=%{public}d uid=%{public}d", pid, uid);
    }
    return noErr;
}

OSStatus VolumeControlDriver_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt64 /*inChangeAction*/, void* /*inChangeInfo*/) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }
    return noErr;
}

OSStatus VolumeControlDriver_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt64 /*inChangeAction*/, void* /*inChangeInfo*/) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }
    return noErr;
}

Boolean VolumeControlDriver_HasProperty(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inObjectID, pid_t /*inClientPID*/, const AudioObjectPropertyAddress* inAddress) {
    if (inAddress == nullptr) {
        return false;
    }

    if (IsPluginObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            return true;
        default:
            return false;
        }
    }

    if (IsDeviceObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
    case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferFrameSizeRange:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyStreamConfiguration:
        case kAudioDevicePropertyStreams:
        case kAudioDevicePropertyAvailableNominalSampleRates:
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            return true;
        default:
            return false;
        }
    }

    if (IsStreamObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyName:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        default:
            return false;
        }
    }

    return false;
}

OSStatus VolumeControlDriver_IsPropertySettable(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inObjectID, pid_t /*inClientProcessID*/, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable) {
    if (inAddress == nullptr || outIsSettable == nullptr) {
        return kAudioHardwareBadPropertySizeError;
    }

    Boolean result = false;

    if (IsDeviceObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyBufferFrameSize:
            result = true;
            break;
        default:
            result = false;
            break;
        }
    } else if (IsStreamObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            result = true;
            break;
        default:
            result = false;
            break;
        }
    }

    *outIsSettable = result;
    return noErr;
}

OSStatus VolumeControlDriver_GetPropertyDataSize(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inObjectID, pid_t /*inClientPID*/, const AudioObjectPropertyAddress* inAddress, UInt32 /*inQualifierDataSize*/, const void* /*inQualifierData*/, UInt32* outDataSize) {
    if (inAddress == nullptr || outDataSize == nullptr) {
        return kAudioHardwareBadPropertySizeError;
    }

    if (IsPluginObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            return noErr;
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    if (IsDeviceObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            return noErr;
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
            *outDataSize = sizeof(AudioObjectID);
            return noErr;
        case kAudioObjectPropertyControlList:
            *outDataSize = 0;
            return noErr;
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            *outDataSize = sizeof(UInt32);
            return noErr;
        case kAudioDevicePropertyNominalSampleRate:
            *outDataSize = sizeof(Float64);
            return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates:
            *outDataSize = sizeof(AudioValueRange) * 2;
            return noErr;
        case kAudioDevicePropertyBufferFrameSizeRange:
            *outDataSize = sizeof(AudioValueRange);
            return noErr;
        case kAudioDevicePropertyStreamConfiguration:
            *outDataSize = offsetof(AudioBufferList, mBuffers[1]) + sizeof(AudioBuffer);
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    if (IsStreamObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            return noErr;
        case kAudioObjectPropertyName:
            *outDataSize = sizeof(CFStringRef);
            return noErr;
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
            *outDataSize = sizeof(UInt32);
            return noErr;
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *outDataSize = sizeof(AudioStreamBasicDescription);
            return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            *outDataSize = sizeof(AudioStreamRangedDescription) * 2;
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    return kAudioHardwareUnknownPropertyError;
}

OSStatus VolumeControlDriver_GetPropertyData(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inObjectID, pid_t /*inClientProcessID*/, const AudioObjectPropertyAddress* inAddress, UInt32 /*inQualifierDataSize*/, const void* /*inQualifierData*/, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    if (inAddress == nullptr || outDataSize == nullptr) {
        return kAudioHardwareBadPropertySizeError;
    }

    const auto ensureCapacity = [&](UInt32 required) -> OSStatus {
        if (required == 0) {
            *outDataSize = 0;
            return noErr;
        }
        if (outData == nullptr || inDataSize < required) {
            return kAudioHardwareBadPropertySizeError;
        }
        *outDataSize = required;
        return noErr;
    };

    if (IsPluginObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
            if (ensureCapacity(sizeof(AudioClassID)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioClassID*>(outData) = kAudioPlugInClassID;
            return noErr;
        case kAudioObjectPropertyName:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlDriverName));
            return noErr;
        case kAudioObjectPropertyManufacturer:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlDriverManufacturer));
            return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            if (ensureCapacity(sizeof(AudioObjectID)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioObjectID*>(outData) = kDeviceObjectID;
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    DeviceState& device = gDriverGlobals.device;

    if (IsDeviceObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
            if (ensureCapacity(sizeof(AudioClassID)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioClassID*>(outData) = kAudioDeviceClassID;
            return noErr;
        case kAudioObjectPropertyName:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlDeviceName));
            return noErr;
        case kAudioObjectPropertyManufacturer:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlDriverManufacturer));
            return noErr;
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
            if (ensureCapacity(sizeof(AudioObjectID)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioObjectID*>(outData) = kOutputStreamObjectID;
            return noErr;
        case kAudioObjectPropertyControlList:
            *outDataSize = 0;
            return noErr;
        case kAudioDevicePropertyDeviceUID:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlDeviceUID));
            return noErr;
        case kAudioDevicePropertyModelUID:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlDeviceModelUID));
            return noErr;
        case kAudioDevicePropertyTransportType:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = kAudioDeviceTransportTypeVirtual;
            return noErr;
        case kAudioDevicePropertyNominalSampleRate:
            if (ensureCapacity(sizeof(Float64)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<Float64*>(outData) = device.sampleRate;
            return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates:
            if (ensureCapacity(sizeof(AudioValueRange) * 2) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            {
                auto* ranges = reinterpret_cast<AudioValueRange*>(outData);
                ranges[0].mMinimum = kAlternateSampleRate;
                ranges[0].mMaximum = kAlternateSampleRate;
                ranges[1].mMinimum = kDefaultSampleRate;
                ranges[1].mMaximum = kDefaultSampleRate;
            }
            return noErr;
        case kAudioDevicePropertyBufferFrameSize:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = device.bufferFrameSize;
            return noErr;
        case kAudioDevicePropertyBufferFrameSizeRange:
            if (ensureCapacity(sizeof(AudioValueRange)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            reinterpret_cast<AudioValueRange*>(outData)->mMinimum = kMinimumBufferFrameSize;
            reinterpret_cast<AudioValueRange*>(outData)->mMaximum = kMaximumBufferFrameSize;
            return noErr;
        case kAudioDevicePropertyLatency:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = device.latency;
            return noErr;
        case kAudioDevicePropertySafetyOffset:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = device.safetyOffset;
            return noErr;
        case kAudioDevicePropertyStreamConfiguration: {
            const UInt32 required = static_cast<UInt32>(offsetof(AudioBufferList, mBuffers[1]) + sizeof(AudioBuffer));
            if (ensureCapacity(required) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            auto* list = reinterpret_cast<AudioBufferList*>(outData);
            list->mNumberBuffers = 1;
            list->mBuffers[0].mNumberChannels = kDefaultChannelCount;
            list->mBuffers[0].mDataByteSize = static_cast<UInt32>(device.bufferFrameSize * device.virtualFormat.mBytesPerFrame);
            list->mBuffers[0].mData = nullptr;
            return noErr;
        }
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = 1;
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    if (IsStreamObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyClass:
            if (ensureCapacity(sizeof(AudioClassID)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioClassID*>(outData) = kAudioStreamClassID;
            return noErr;
        case kAudioObjectPropertyName:
            if (ensureCapacity(sizeof(CFStringRef)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<CFStringRef*>(outData) = static_cast<CFStringRef>(CFRetain(kVolumeControlStreamName));
            return noErr;
        case kAudioStreamPropertyDirection:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = kAudioStreamDirection_Output;
            return noErr;
        case kAudioStreamPropertyTerminalType:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = kAudioStreamTerminalTypeSpeaker;
            return noErr;
        case kAudioStreamPropertyStartingChannel:
            if (ensureCapacity(sizeof(UInt32)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<UInt32*>(outData) = 1;
            return noErr;
        case kAudioStreamPropertyVirtualFormat:
            if (ensureCapacity(sizeof(AudioStreamBasicDescription)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioStreamBasicDescription*>(outData) = device.virtualFormat;
            return noErr;
        case kAudioStreamPropertyPhysicalFormat:
            if (ensureCapacity(sizeof(AudioStreamBasicDescription)) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            *reinterpret_cast<AudioStreamBasicDescription*>(outData) = device.physicalFormat;
            return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            if (ensureCapacity(sizeof(AudioStreamRangedDescription) * 2) != noErr) {
                return kAudioHardwareBadPropertySizeError;
            }
            {
                auto* formats = reinterpret_cast<AudioStreamRangedDescription*>(outData);
                formats[0].mFormat = MakeFloatFormat(kAlternateSampleRate);
                formats[0].mSampleRateRange.mMinimum = kAlternateSampleRate;
                formats[0].mSampleRateRange.mMaximum = kAlternateSampleRate;
                formats[1].mFormat = MakeFloatFormat(kDefaultSampleRate);
                formats[1].mSampleRateRange.mMinimum = kDefaultSampleRate;
                formats[1].mSampleRateRange.mMaximum = kDefaultSampleRate;
            }
            return noErr;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    return kAudioHardwareUnknownPropertyError;
}

OSStatus VolumeControlDriver_SetPropertyData(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inObjectID, pid_t /*inClientPID*/, const AudioObjectPropertyAddress* inAddress, UInt32 /*inQualifierDataSize*/, const void* /*inQualifierData*/, UInt32 inDataSize, const void* inData) {
    if (inAddress == nullptr || inData == nullptr) {
        return kAudioHardwareIllegalOperationError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    DeviceState& device = gDriverGlobals.device;

    if (IsDeviceObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioDevicePropertyNominalSampleRate: {
            if (inDataSize != sizeof(Float64)) {
                return kAudioHardwareBadPropertySizeError;
            }
            Float64 newRate = *reinterpret_cast<const Float64*>(inData);
            if (newRate <= 0.0) {
                return kAudioHardwareIllegalOperationError;
            }

            device.sampleRate = newRate;
            device.virtualFormat = MakeFloatFormat(newRate);
            device.physicalFormat = device.virtualFormat;
            device.sampleCounter = 0;
            device.timestampSeed++;
            os_log_info(gLog, "Updated sample rate to %f", newRate);
            return noErr;
        }
        case kAudioDevicePropertyBufferFrameSize: {
            if (inDataSize != sizeof(UInt32)) {
                return kAudioHardwareBadPropertySizeError;
            }
            UInt32 newSize = *reinterpret_cast<const UInt32*>(inData);
            newSize = std::clamp(newSize, kMinimumBufferFrameSize, kMaximumBufferFrameSize);
            device.bufferFrameSize = newSize;
            os_log_info(gLog, "Updated buffer frame size to %{public}u", newSize);
            return noErr;
        }
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    if (IsStreamObject(inObjectID)) {
        switch (inAddress->mSelector) {
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
            if (inDataSize != sizeof(AudioStreamBasicDescription)) {
                return kAudioHardwareBadPropertySizeError;
            }
            const auto* newFormat = reinterpret_cast<const AudioStreamBasicDescription*>(inData);
            if (newFormat->mFormatID != kAudioFormatLinearPCM ||
                (newFormat->mFormatFlags & kAudioFormatFlagIsFloat) == 0 ||
                newFormat->mChannelsPerFrame != kDefaultChannelCount) {
                return kAudioHardwareUnsupportedOperationError;
            }

            if (inAddress->mSelector == kAudioStreamPropertyVirtualFormat) {
                device.virtualFormat = *newFormat;
                device.sampleRate = newFormat->mSampleRate;
            } else {
                device.physicalFormat = *newFormat;
            }
            device.sampleCounter = 0;
            device.timestampSeed++;
            os_log_info(gLog, "Updated stream format to sampleRate=%f", newFormat->mSampleRate);
            return noErr;
        }
        default:
            return kAudioHardwareUnknownPropertyError;
        }
    }

    return kAudioHardwareUnknownPropertyError;
}

OSStatus VolumeControlDriver_StartIO(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt32 /*inClientID*/) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    auto& device = gDriverGlobals.device;
    device.isRunning = true;
    device.sampleCounter = 0;
    device.anchorHostTime = mach_absolute_time();
    device.timestampSeed++;
    os_log_debug(gLog, "StartIO invoked");
    return noErr;
}

OSStatus VolumeControlDriver_StopIO(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt32 /*inClientID*/) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    gDriverGlobals.device.isRunning = false;
    os_log_debug(gLog, "StopIO invoked");
    return noErr;
}

OSStatus VolumeControlDriver_GetZeroTimeStamp(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt32 /*inClientID*/, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    auto& device = gDriverGlobals.device;

    UInt64 hostTime = device.anchorHostTime;
    Float64 sampleTime = static_cast<Float64>(device.sampleCounter);

    if (device.isRunning) {
        hostTime = device.anchorHostTime + SamplesToHostTicks(device.sampleCounter, device.sampleRate);
    }

    if (outSampleTime != nullptr) {
        *outSampleTime = sampleTime;
    }
    if (outHostTime != nullptr) {
        *outHostTime = hostTime;
    }
    if (outSeed != nullptr) {
        device.timestampSeed++;
        *outSeed = device.timestampSeed;
    }

    return noErr;
}

OSStatus VolumeControlDriver_WillDoIOOperation(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt32 /*inClientID*/, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    const bool willDo = (inOperationID == kAudioServerPlugInIOOperationWriteMix);
    if (outWillDo != nullptr) {
        *outWillDo = willDo;
    }
    if (outWillDoInPlace != nullptr) {
        *outWillDoInPlace = true;
    }
    return noErr;
}

OSStatus VolumeControlDriver_BeginIOOperation(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt32 /*inClientID*/, UInt32 inOperationID, UInt32 /*inIOBufferFrameSize*/, const AudioServerPlugInIOCycleInfo* /*inIOCycleInfo*/) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    if (inOperationID != kAudioServerPlugInIOOperationWriteMix) {
        return kAudioHardwareUnsupportedOperationError;
    }

    return noErr;
}

OSStatus VolumeControlDriver_DoIOOperation(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 /*inClientID*/, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* /*inIOCycleInfo*/, void* ioMainBuffer, void* /*ioSecondaryBuffer*/) {
    if (!IsDeviceObject(inDeviceObjectID) || !IsStreamObject(inStreamObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    if (inOperationID != kAudioServerPlugInIOOperationWriteMix) {
        return kAudioHardwareUnsupportedOperationError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    DeviceState& device = gDriverGlobals.device;
    const UInt32 channels = device.virtualFormat.mChannelsPerFrame;

    float aggregateGain = 1.0f;
    bool forceMute = false;

    for (const auto& entry : device.activeClients) {
        const ClientState& client = entry.second;
        if (client.bundleID.empty()) {
            continue;
        }

        auto accessorIt = gDriverGlobals.sharedMemoryByUser.find(client.uid);
        if (accessorIt == gDriverGlobals.sharedMemoryByUser.end()) {
            continue;
        }
        auto* state = accessorIt->second.state();
        if (state == nullptr) {
            continue;
        }

        if (auto info = FindApplicationVolume(*state, client.bundleID)) {
            if (info->mute) {
                forceMute = true;
                break;
            }
            const float clampedGain = std::clamp(info->gain, 0.0f, 4.0f);
            aggregateGain = std::min(aggregateGain, clampedGain);
        }
    }

    if (ioMainBuffer != nullptr && inIOBufferFrameSize > 0) {
        Float32* samples = static_cast<Float32*>(ioMainBuffer);
        const size_t totalSamples = static_cast<size_t>(inIOBufferFrameSize) * static_cast<size_t>(channels);

        if (forceMute) {
            std::fill(samples, samples + totalSamples, 0.0f);
        } else if (std::fabs(aggregateGain - 1.0f) > kGainEpsilon) {
            for (size_t index = 0; index < totalSamples; ++index) {
                samples[index] *= aggregateGain;
            }
        }
    }

    if (device.isRunning) {
        device.sampleCounter += inIOBufferFrameSize;
    }

    return noErr;
}

OSStatus VolumeControlDriver_EndIOOperation(AudioServerPlugInDriverRef /*inDriver*/, AudioObjectID inDeviceObjectID, UInt32 /*inClientID*/, UInt32 inOperationID, UInt32 /*inIOBufferFrameSize*/, const AudioServerPlugInIOCycleInfo* /*inIOCycleInfo*/) {
    if (!IsDeviceObject(inDeviceObjectID)) {
        return kAudioHardwareBadObjectError;
    }

    if (inOperationID != kAudioServerPlugInIOOperationWriteMix) {
        return kAudioHardwareUnsupportedOperationError;
    }

    std::lock_guard<std::mutex> lock(gDriverGlobals.mutex);
    if (gDriverGlobals.device.isRunning) {
        const UInt64 hostNow = mach_absolute_time();
        const UInt64 offset = SamplesToHostTicks(gDriverGlobals.device.sampleCounter, gDriverGlobals.device.sampleRate);
        gDriverGlobals.device.anchorHostTime = (hostNow > offset) ? (hostNow - offset) : hostNow;
    }
    return noErr;
}

// Legacy Objective-C++ plugin removed. New HAL plugin lives in Audio/HAL/Plugin/BGMPlugIn.cpp.
