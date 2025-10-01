#include "VirtualAudioDriverBridge.h"

#include "VirtualAudioDriver.h"

namespace {
CFStringRef CreateCFString(const std::string& value) {
    return CFStringCreateWithCString(kCFAllocatorDefault, value.c_str(), kCFStringEncodingUTF8);
}
}

OSStatus VirtualAudioDriverInitialize(void) {
    return VirtualAudioDriver::shared().initialize();
}

OSStatus VirtualAudioDriverShutdown(void) {
    return VirtualAudioDriver::shared().shutdown();
}

OSStatus VirtualAudioDriverSetApplicationVolume(CFStringRef bundleID, Float32 volume) {
    return VirtualAudioDriver::shared().setApplicationVolume(bundleID, volume);
}

OSStatus VirtualAudioDriverGetApplicationVolume(CFStringRef bundleID, Float32* outVolume) {
    return VirtualAudioDriver::shared().getApplicationVolume(bundleID, outVolume);
}

OSStatus VirtualAudioDriverMuteApplication(CFStringRef bundleID, Boolean mute) {
    return VirtualAudioDriver::shared().muteApplication(bundleID, mute);
}

Boolean VirtualAudioDriverIsApplicationMuted(CFStringRef bundleID) {
    return VirtualAudioDriver::shared().isApplicationMuted(bundleID);
}

CFArrayRef VirtualAudioDriverCopyActiveApplications(void) {
    const auto bundleIDs = VirtualAudioDriver::shared().snapshotBundleIDs();
    CFMutableArrayRef array = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

    for (const auto& identifier : bundleIDs) {
        CFStringRef cfIdentifier = CreateCFString(identifier);
        if (cfIdentifier != nullptr) {
            CFArrayAppendValue(array, cfIdentifier);
            CFRelease(cfIdentifier);
        }
    }

    return array;
}
