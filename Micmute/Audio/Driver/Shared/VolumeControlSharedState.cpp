#include "VolumeControlSharedState.hpp"

#include <cerrno>
#include <chrono>
#include <climits>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <filesystem>

namespace micmute::driver {

namespace {
constexpr std::uint32_t kSharedMemoryMode = 0664;

std::uint64_t CurrentMonotonicTimeNanos() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(now).count());
}

VolumeControlAppEntry* FindEntry(VolumeControlSharedState& state, std::uint64_t hash, const std::string& bundleID) {
    for (std::size_t index = 0; index < kMaxTrackedApplications; ++index) {
        auto& entry = state.entries[index];
        if (entry.bundleIDHash == hash && std::strncmp(entry.bundleID, bundleID.c_str(), kMaxBundleIdentifierLength) == 0) {
            return &entry;
        }
    }
    return nullptr;
}

VolumeControlAppEntry* AllocateEntry(VolumeControlSharedState& state, std::uint64_t hash, const std::string& bundleID) {
    auto& header = state.header;
    for (std::size_t index = 0; index < kMaxTrackedApplications; ++index) {
        auto& entry = state.entries[index];
        if (entry.bundleIDHash == 0 || entry.bundleID[0] == '\0') {
            header.entryCount.fetch_add(1, std::memory_order_relaxed);
            return &entry;
        }
    }

    // Replace the least recently updated entry.
    VolumeControlAppEntry* oldest = &state.entries[0];
    for (std::size_t index = 1; index < kMaxTrackedApplications; ++index) {
        auto& entry = state.entries[index];
        if (entry.lastUpdateMonotonicNanoseconds < oldest->lastUpdateMonotonicNanoseconds) {
            oldest = &entry;
        }
    }
    return oldest;
}

void WriteEntry(VolumeControlAppEntry& entry, std::uint64_t hash, const std::string& bundleID, float gain, bool mute) {
    entry.bundleIDHash = hash;
    std::strncpy(entry.bundleID, bundleID.c_str(), kMaxBundleIdentifierLength - 1);
    entry.bundleID[kMaxBundleIdentifierLength - 1] = '\0';
    entry.gain = gain;
    entry.flags = mute ? 1U : 0U;
    entry.lastUpdateMonotonicNanoseconds = CurrentMonotonicTimeNanos();
}
} // namespace

std::size_t SharedMemorySize() {
    return sizeof(VolumeControlSharedState);
}

std::string SharedMemoryPathForUID(uid_t uid) {
    // Use a single global shared memory file instead of per-user files
    // This allows coreaudiod (running as root) to share state with user applications
    (void)uid; // unused parameter
    
    std::string path(kSharedMemoryDirectory);
    if (!path.empty() && path.back() != '/') {
        path.push_back('/');
    }
    path.append(kSharedMemoryFilenameTemplate);
    return path;
}

std::uint64_t HashBundleIdentifier(const char* bundleID) {
    if (bundleID == nullptr) {
        return 0;
    }

    // FNV-1a 64-bit hash
    constexpr std::uint64_t kPrime = 1099511628211ULL;
    constexpr std::uint64_t kOffset = 1469598103934665603ULL;

    std::uint64_t hash = kOffset;
    for (const unsigned char* ptr = reinterpret_cast<const unsigned char*>(bundleID); *ptr; ++ptr) {
        hash ^= static_cast<std::uint64_t>(*ptr);
        hash *= kPrime;
    }
    return hash;
}

std::uint64_t HashBundleIdentifier(const std::string& bundleID) {
    return HashBundleIdentifier(bundleID.c_str());
}

bool UpdateApplicationVolume(VolumeControlSharedState& state, const std::string& bundleID, float gain, bool mute) {
    if (bundleID.empty()) {
        return false;
    }

    const std::uint64_t hash = HashBundleIdentifier(bundleID);
    VolumeControlAppEntry* entry = FindEntry(state, hash, bundleID);
    if (entry == nullptr) {
        entry = AllocateEntry(state, hash, bundleID);
    }
    if (entry == nullptr) {
        return false;
    }

    WriteEntry(*entry, hash, bundleID, gain, mute);

    auto& header = state.header;
    header.lastWriterPID.store(static_cast<std::uint64_t>(getpid()), std::memory_order_relaxed);
    header.lastWriterUID.store(static_cast<std::uint64_t>(getuid()), std::memory_order_relaxed);
    header.generation.fetch_add(1, std::memory_order_release);
    return true;
}

bool RemoveApplicationVolume(VolumeControlSharedState& state, const std::string& bundleID) {
    if (bundleID.empty()) {
        return false;
    }

    const std::uint64_t hash = HashBundleIdentifier(bundleID);
    VolumeControlAppEntry* entry = FindEntry(state, hash, bundleID);
    if (entry == nullptr) {
        return false;
    }

    entry->bundleIDHash = 0;
    entry->bundleID[0] = '\0';
    entry->gain = 1.0f;
    entry->flags = 0;
    entry->lastUpdateMonotonicNanoseconds = 0;
    state.header.entryCount.fetch_sub(1, std::memory_order_relaxed);
    state.header.generation.fetch_add(1, std::memory_order_release);
    return true;
}

std::optional<ApplicationVolumeInfo> FindApplicationVolume(const VolumeControlSharedState& state, const std::string& bundleID) {
    const std::uint64_t hash = HashBundleIdentifier(bundleID);
    for (const auto& entry : state.entries) {
        if (entry.bundleIDHash == hash && std::strncmp(entry.bundleID, bundleID.c_str(), kMaxBundleIdentifierLength) == 0) {
            return ApplicationVolumeInfo{
                entry.bundleID,
                entry.gain,
                (entry.flags & 0x1U) != 0U,
                entry.lastUpdateMonotonicNanoseconds,
            };
        }
    }
    return std::nullopt;
}

std::vector<ApplicationVolumeInfo> SnapshotApplicationVolumes(const VolumeControlSharedState& state) {
    std::vector<ApplicationVolumeInfo> snapshot;
    snapshot.reserve(kMaxTrackedApplications);
    for (const auto& entry : state.entries) {
        if (entry.bundleIDHash == 0 || entry.bundleID[0] == '\0') {
            continue;
        }
        snapshot.push_back(ApplicationVolumeInfo{
            entry.bundleID,
            entry.gain,
            (entry.flags & 0x1U) != 0U,
            entry.lastUpdateMonotonicNanoseconds,
        });
    }
    return snapshot;
}

SharedMemoryAccessor::SharedMemoryAccessor() = default;

SharedMemoryAccessor::SharedMemoryAccessor(SharedMemoryAccessor&& other) noexcept {
    *this = std::move(other);
}

SharedMemoryAccessor& SharedMemoryAccessor::operator=(SharedMemoryAccessor&& other) noexcept {
    if (this == &other) {
        return *this;
    }

    unmap();
    m_fileDescriptor = other.m_fileDescriptor;
    m_state = other.m_state;
    m_mappedUID = other.m_mappedUID;

    other.m_fileDescriptor = -1;
    other.m_state = nullptr;
    other.m_mappedUID = std::numeric_limits<std::uint32_t>::max();
    return *this;
}

SharedMemoryAccessor::~SharedMemoryAccessor() {
    unmap();
}

bool SharedMemoryAccessor::mapForUID(uid_t uid, bool createIfMissing, std::string* errorMessage) {
    if (m_state != nullptr && m_mappedUID == static_cast<std::uint32_t>(uid)) {
        return true;
    }

    unmap();
    if (!openFile(uid, createIfMissing, errorMessage)) {
        return false;
    }

    if (!mapFile(errorMessage)) {
        closeFile();
        return false;
    }

    m_mappedUID = static_cast<std::uint32_t>(uid);

    auto* header = &m_state->header;
    std::uint32_t expected = 0;
    if (header->version.compare_exchange_strong(expected, kSharedStateVersion)) {
        header->entryCount.store(0, std::memory_order_relaxed);
        header->generation.store(1, std::memory_order_relaxed);
        header->lastWriterPID.store(static_cast<std::uint64_t>(getpid()), std::memory_order_relaxed);
        header->lastWriterUID.store(static_cast<std::uint64_t>(getuid()), std::memory_order_relaxed);
    }
    return true;
}

void SharedMemoryAccessor::unmap() {
    if (m_state != nullptr) {
        munmap(static_cast<void*>(m_state), SharedMemorySize());
        m_state = nullptr;
    }
    closeFile();
    m_mappedUID = std::numeric_limits<std::uint32_t>::max();
}

bool SharedMemoryAccessor::ensureDirectoryExists(std::string* errorMessage) {
    std::error_code ec;
    std::filesystem::path directory(kSharedMemoryDirectory);
    
    // Check if directory already exists
    if (std::filesystem::exists(directory, ec)) {
        // Verify we can access it
        if (access(directory.c_str(), W_OK | X_OK) == 0) {
            return true;
        }
        // Directory exists but no write access - likely needs installation
        if (errorMessage) {
            *errorMessage = "Shared memory directory exists but no write access: " + directory.string() + 
                          ". Run driver installation to set proper permissions.";
        }
        return false;
    }

    // Try to create directory (will fail if we don't have permissions)
    if (!std::filesystem::create_directories(directory, ec)) {
        if (errorMessage) {
            *errorMessage = "Failed to create shared memory directory: " + directory.string() + 
                          " (" + ec.message() + "). Run driver installation to create with proper permissions.";
        }
        return false;
    }

    // Set permissions if we created it
    chmod(directory.c_str(), 0775);
    return true;
}

bool SharedMemoryAccessor::openFile(uid_t uid, bool createIfMissing, std::string* errorMessage) {
    if (createIfMissing && !ensureDirectoryExists(errorMessage)) {
        return false;
    }

    const std::string path = SharedMemoryPathForUID(uid);
    int flags = createIfMissing ? (O_RDWR | O_CREAT) : O_RDWR;
    m_fileDescriptor = ::open(path.c_str(), flags, kSharedMemoryMode);
    if (m_fileDescriptor < 0) {
        if (errorMessage) {
            *errorMessage = "Failed to open shared memory file " + path + ": " + std::strerror(errno);
        }
        return false;
    }

    if (createIfMissing) {
        if (ftruncate(m_fileDescriptor, static_cast<off_t>(SharedMemorySize())) != 0) {
            if (errorMessage) {
                *errorMessage = "Failed to size shared memory file: " + std::string(std::strerror(errno));
            }
            closeFile();
            return false;
        }
    }

    return true;
}

bool SharedMemoryAccessor::mapFile(std::string* errorMessage) {
    void* mapping = mmap(nullptr, SharedMemorySize(), PROT_READ | PROT_WRITE, MAP_SHARED, m_fileDescriptor, 0);
    if (mapping == MAP_FAILED) {
        if (errorMessage) {
            *errorMessage = "Failed to map shared memory: " + std::string(std::strerror(errno));
        }
        return false;
    }

    m_state = static_cast<VolumeControlSharedState*>(mapping);
    return true;
}

void SharedMemoryAccessor::closeFile() {
    if (m_fileDescriptor >= 0) {
        ::close(m_fileDescriptor);
        m_fileDescriptor = -1;
    }
}

} // namespace micmute::driver
