#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <windows.h>
#include <stdexcept>
#include "../../sqlite/sqlite3.h"

namespace VolumeCollector {

// Exception class for volume collection errors
class VolumeCollectionException : public std::runtime_error {
public:
    explicit VolumeCollectionException(const std::string& message) 
        : std::runtime_error(message) {}
};

// Structure to hold volume information
struct VolumeInfo {
    int volumeId = 0;
    int diskId = -1;
    std::wstring label;
    std::wstring fileSystem;
    int64_t size = 0;
    int64_t freeSpace = 0;
    bool isSystem = false;
    bool isReadOnly = false;
    std::wstring status;
    std::wstring uniqueId;
    int64_t allocationUnitSize = 0;
    int driveType = 0;
    std::vector<std::wstring> mountPoints;
    // New fields
    bool isEncrypted = false;
    bool isCompressed = false;
    bool shadowCopyEnabled = false;
    int64_t shadowCopyStorageMax = 0;
    bool encryptionSupported = false;  // FIX FC-022: File system supports encryption (NTFS EFS)
};

// Function to collect volume information and insert into database
// Changed return type from void to int to return the number of volumes processed
int CollectAndStoreVolumeInfo(sqlite3* db, const std::string& inventoryId);

// Helper functions
std::vector<VolumeInfo> CollectVolumeInfo();
std::vector<std::wstring> GetVolumeMountPoints(const std::wstring& volumeName);
bool CollectVolumeExtents(sqlite3* db, const std::string& inventoryId, int volumeId, const std::wstring& volumePath);
bool RetrieveAndStoreVolumeExtentsUsingDriveLetter(sqlite3* db, const std::string& inventoryId, int volumeId, const std::wstring& driveLetter);
bool StoreVolumeExtents(sqlite3* db, const std::string& inventoryId, int volumeId, VOLUME_DISK_EXTENTS* pExtents);
bool StoreVolumeMountPoints(sqlite3* db, const std::string& inventoryId, int volumeId, const std::vector<std::wstring>& mountPoints);
int GetDiskIdFromDriveLetter(const std::wstring& driveLetter);

// Add declaration for the missing LogVolumeExtents function
void LogVolumeExtents(const std::wstring& volumePath, VOLUME_DISK_EXTENTS* pExtents);

// Helper function to convert wide string to narrow string
inline std::string WideToNarrow(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(), nullptr, 0, nullptr, nullptr);
    std::string strTo(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wide.data(), (int)wide.size(), &strTo[0], size_needed, nullptr, nullptr);
    return strTo;
}

} // namespace VolumeCollector
