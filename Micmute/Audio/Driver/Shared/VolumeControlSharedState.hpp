#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
// Legacy shared state header removed; see Audio/HAL/Plugin/BGMShared.h for active structure.
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
