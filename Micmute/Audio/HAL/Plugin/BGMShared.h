#ifndef BGMShared_h
#define BGMShared_h

#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

// Four-char selectors (little endian hex) for custom properties
// 'plst' - list of processes
// 'pvol' - per-process volume
// 'pmut' - per-process mute state
#define kBGMPropertyProcessPeak  0x70706b31u // 'ppk1' per-process peak float (qualifier pid)
#define kBGMPropertyProcessRMS   0x70726d31u // 'prm1' per-process RMS float (qualifier pid)
#define kBGMPropertyProcessRMSdB 0x70726d62u // 'prdb' per-process RMS in dBFS (qualifier pid)
#define kBGMPropertyGlobalPeak   0x67706b31u // 'gpk1' global peak float
#define kBGMPropertyGlobalRMS    0x67726d31u // 'grm1' global RMS float
#define kBGMPropertyGlobalRMSdB  0x67726462u // 'grdb' global RMS dBFS
#define kBGMPropertyProcessList  0x706c7374u
#define kBGMPropertyProcessVolume 0x70766f6cu
#define kBGMPropertyProcessMute  0x706d7574u

// Structure returned for each process when querying list
// Packed to ensure consistent layout across Swift/C++.
#pragma pack(push, 1)
typedef struct BGMProcessEntry {
    pid_t pid;             // process id
    float volume;          // 0.0 - 2.0 (boost allowed)
    uint8_t muted;         // 0/1
    char bundleID[128];    // UTF-8 bundle identifier (null-terminated)
} BGMProcessEntry;
#pragma pack(pop)

#ifdef __cplusplus
}
#endif

#endif /* BGMShared_h */
