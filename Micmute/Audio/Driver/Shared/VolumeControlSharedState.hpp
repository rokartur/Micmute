#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <sys/types.h>
#include <vector>

namespace micmute::driver {

constexpr std::uint32_t kSharedStateVersion = 1;
constexpr std::size_t kMaxTrackedApplications = 128;
constexpr std::size_t kMaxBundleIdentifierLength = 192;

constexpr const char* kSharedMemoryDirectory = "/Library/Application Support/Micmute";
constexpr const char* kSharedMemoryFilenameTemplate = "micmute-volume-global.shm";

struct alignas(16) VolumeControlAppEntry {
    std::uint64_t bundleIDHash = 0;
    char bundleID[kMaxBundleIdentifierLength] = {0};
    float gain = 1.0f;
    std::uint32_t flags = 0; // bit 0 -> mute flag
    std::uint64_t lastUpdateMonotonicNanoseconds = 0;
};

struct alignas(64) VolumeControlSharedHeader {
    std::atomic<std::uint32_t> version{0};
    std::atomic<std::uint32_t> entryCount{0};
    std::atomic<std::uint64_t> generation{0};
    std::atomic<std::uint64_t> lastWriterPID{0};
    std::atomic<std::uint64_t> lastWriterUID{0};
    std::uint8_t reserved[64] = {0};
};

struct alignas(64) VolumeControlSharedState {
    VolumeControlSharedHeader header;
    VolumeControlAppEntry entries[kMaxTrackedApplications];
};

std::size_t SharedMemorySize();

std::string SharedMemoryPathForUID(uid_t uid);

std::uint64_t HashBundleIdentifier(const char* bundleID);
std::uint64_t HashBundleIdentifier(const std::string& bundleID);

struct ApplicationVolumeInfo {
    std::string bundleID;
    float gain = 1.0f;
    bool mute = false;
    std::uint64_t lastUpdateMonotonicNanoseconds = 0;
};

bool UpdateApplicationVolume(VolumeControlSharedState& state, const std::string& bundleID, float gain, bool mute);
bool RemoveApplicationVolume(VolumeControlSharedState& state, const std::string& bundleID);
std::optional<ApplicationVolumeInfo> FindApplicationVolume(const VolumeControlSharedState& state, const std::string& bundleID);
std::vector<ApplicationVolumeInfo> SnapshotApplicationVolumes(const VolumeControlSharedState& state);

class SharedMemoryAccessor {
public:
    SharedMemoryAccessor();
    SharedMemoryAccessor(const SharedMemoryAccessor&) = delete;
    SharedMemoryAccessor& operator=(const SharedMemoryAccessor&) = delete;
    SharedMemoryAccessor(SharedMemoryAccessor&&) noexcept;
    SharedMemoryAccessor& operator=(SharedMemoryAccessor&&) noexcept;
    ~SharedMemoryAccessor();

    bool mapForUID(uid_t uid, bool createIfMissing, std::string* errorMessage = nullptr);
    void unmap();

    VolumeControlSharedState* state() { return m_state; }
    const VolumeControlSharedState* state() const { return m_state; }

    bool isValid() const { return m_state != nullptr; }

private:
    bool ensureDirectoryExists(std::string* errorMessage);
    bool openFile(uid_t uid, bool createIfMissing, std::string* errorMessage);
    bool mapFile(std::string* errorMessage);
    void closeFile();

    int m_fileDescriptor = -1;
    VolumeControlSharedState* m_state = nullptr;
    std::uint32_t m_mappedUID = std::numeric_limits<std::uint32_t>::max();
};

} // namespace micmute::driver
