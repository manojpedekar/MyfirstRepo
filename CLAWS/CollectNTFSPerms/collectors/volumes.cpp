#include "../collectors/volumes.h"
#include "../utils/raii_wrappers.h"
#include <iostream>
#include <memory>
#include <set>
#include <algorithm>
#include <windows.h>
#include <winioctl.h>
#include "../utils/utils.h"
#include "../database/statement.h"
#include "../database/transaction.h"
#include "../utils/stringutils.h"

namespace VolumeCollector {

using Common::DeviceHandle;

std::vector<VolumeInfo> CollectVolumeInfo() {
    std::vector<VolumeInfo> volumes;
    int volumeId = 1;
    
    std::cout << "\nStarting volume information collection..." << std::endl;
    
    // Get all volume GUIDs
    wchar_t volumeGuidPath[MAX_PATH] = {0};
    HANDLE hFindVolume = FindFirstVolumeW(volumeGuidPath, MAX_PATH);
    
    if (hFindVolume == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::cerr << "Failed to enumerate volumes. Error: " << error << std::endl;
        throw std::runtime_error("Failed to enumerate volumes");
    }
    
    do {
        std::wcout << L"\nFound volume: " << volumeGuidPath << std::endl;
        
        VolumeInfo volume;
        volume.volumeId = volumeId++;
        volume.uniqueId = volumeGuidPath;
        
        // Get mount points for this volume
        volume.mountPoints = GetVolumeMountPoints(volumeGuidPath);
        std::cout << "  Volume has " << volume.mountPoints.size() << " mount points" << std::endl;
        
        // FIX NEW-007: Ensure the path has a trailing backslash with bounds checking
        size_t len = wcslen(volumeGuidPath);
        if (len > 0 && volumeGuidPath[len - 1] != L'\\') {
            // Check buffer bounds before writing
            if (len + 1 < MAX_PATH) {
                volumeGuidPath[len] = L'\\';
                volumeGuidPath[len + 1] = L'\0';
            } else {
                // Buffer too small - log error and skip this volume
                std::cerr << "Volume GUID path too long, skipping" << std::endl;
                continue;
            }
        }

        // FIX FC-019: Remove duplicate volume ID assignment (was being incremented twice)
        // VolumeInfo volume was already created above at line 37-39
        // Duplicate assignment removed: volume.volumeId = volumeId++; (caused gaps: 1,3,5...)
        // Duplicate assignment removed: volume.uniqueId = volumeGuidPath;

        // Open the volume
        HANDLE hVolume = CreateFileW(
            volumeGuidPath,
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_EXISTING,
            0,
            nullptr
        );
        
        if (hVolume != INVALID_HANDLE_VALUE) {
            DeviceHandle volumeHandle(hVolume);
            
            // Get volume information
            wchar_t fsName[MAX_PATH] = {0};
            wchar_t volumeName[MAX_PATH] = {0};
            DWORD fsFlags = 0;
            DWORD maxComponentLen = 0;
            
            if (GetVolumeInformationW(
                volumeGuidPath,
                volumeName,
                MAX_PATH,
                nullptr,
                &maxComponentLen,
                &fsFlags,
                fsName,
                MAX_PATH
            )) {
                volume.label = volumeName;
                volume.fileSystem = fsName;
                volume.isReadOnly = (fsFlags & FILE_READ_ONLY_VOLUME) != 0;
                volume.isCompressed = (fsFlags & FILE_VOLUME_IS_COMPRESSED) != 0;
            }
            
            // Get volume size information
            ULARGE_INTEGER freeBytesAvailable;
            ULARGE_INTEGER totalBytes;
            ULARGE_INTEGER totalFreeBytes;
            
            if (GetDiskFreeSpaceExW(
                volumeGuidPath,
                &freeBytesAvailable,
                &totalBytes,
                &totalFreeBytes
            )) {
                volume.size = totalBytes.QuadPart;
                volume.freeSpace = totalFreeBytes.QuadPart;
            }
            
            // Get allocation unit size
            DWORD sectorsPerCluster;
            DWORD bytesPerSector;
            DWORD numberOfFreeClusters;
            DWORD totalNumberOfClusters;
            
            if (GetDiskFreeSpaceW(
                volumeGuidPath,
                &sectorsPerCluster,
                &bytesPerSector,
                &numberOfFreeClusters,
                &totalNumberOfClusters
            )) {
                volume.allocationUnitSize = static_cast<int64_t>(sectorsPerCluster) * bytesPerSector;
            }
            
            // Get drive type
            volume.driveType = GetDriveTypeW(volumeGuidPath);
            
            // Check if volume is system volume
            wchar_t systemPath[MAX_PATH] = {0};
            GetSystemDirectoryW(systemPath, MAX_PATH);
            systemPath[2] = L'\0';  // Truncate to drive letter
            
            // Get mount points for this volume
            volume.mountPoints = GetVolumeMountPoints(volumeGuidPath);
            
            // Check if any mount point is the system drive
            for (const auto& mountPoint : volume.mountPoints) {
                if (mountPoint.size() >= 2 && mountPoint[0] == systemPath[0] && mountPoint[1] == L':') {
                    volume.isSystem = true;
                    break;
                }
            }
            
            // FIX FC-021: Shadow copy detection requires VSS COM interfaces, not FSCTL_GET_VOLUME_BITMAP
            // FSCTL_GET_VOLUME_BITMAP returns cluster usage, not shadow copy information
            // TODO: Implement proper VSS detection using IVssBackupComponents COM interface
            // For now, set to false to avoid incorrect data
            volume.shadowCopyEnabled = false;

            // FIX FC-022: Use GetVolumeInformation for encryption support detection
            // Previous code used wrong FSCTLs (FSCTL_IS_VOLUME_MOUNTED, FSCTL_GET_NTFS_VOLUME_DATA)
            // which don't return encryption information

            // Get first mount point for GetVolumeInformation call
            std::wstring rootPath;
            if (!volume.mountPoints.empty()) {
                rootPath = volume.mountPoints[0];
                if (rootPath.back() != L'\\') {
                    rootPath += L'\\';
                }

                DWORD fileSystemFlags = 0;
                if (GetVolumeInformationW(
                    rootPath.c_str(),
                    nullptr, 0,  // Volume name
                    nullptr,     // Volume serial number
                    nullptr,     // Max component length
                    &fileSystemFlags,
                    nullptr, 0   // File system name
                )) {
                    // Check if file system supports encryption
                    volume.encryptionSupported = (fileSystemFlags & FILE_SUPPORTS_ENCRYPTION) != 0;

                    // Note: This only checks if NTFS encryption is supported
                    // BitLocker detection requires WMI: SELECT * FROM Win32_EncryptableVolume
                    // TODO: Add BitLocker detection using WMI for complete encryption status
                    // For now, set to false to avoid incorrect data
                    volume.isEncrypted = false;
                } else {
                    volume.encryptionSupported = false;
                    volume.isEncrypted = false;
                }
            } else {
                volume.encryptionSupported = false;
                volume.isEncrypted = false;
            }
            
            // Get disk ID for this volume (will be updated later with extent information)
            volume.diskId = -1;
            
            // Set volume status
            volume.status = L"Online";
        } else {
            // Volume couldn't be opened
            volume.status = L"Offline";
        }
        
        volumes.push_back(volume);
        
    } while (FindNextVolumeW(hFindVolume, volumeGuidPath, MAX_PATH));
    
    FindVolumeClose(hFindVolume);
    
    std::cout << "Collected information for " << volumes.size() << " volumes" << std::endl;
    return volumes;
}

std::wstring GetVolumeLabel(const std::wstring& rootPath) {
    wchar_t label[MAX_PATH + 1] = L"";
    if (!GetVolumeInformationW(
        rootPath.c_str(),
        label,
        ARRAYSIZE(label),
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        0
    )) {
        return L"";
    }
    return label;
}

std::wstring GetVolumeFileSystem(const std::wstring& rootPath) {
    wchar_t fileSystem[MAX_PATH + 1] = L"";
    if (!GetVolumeInformationW(
        rootPath.c_str(),
        nullptr,
        0,
        nullptr,
        nullptr,
        nullptr,
        fileSystem,
        ARRAYSIZE(fileSystem)
    )) {
        return L"";
    }
    return fileSystem;
}

int64_t GetVolumeSize(const std::wstring& rootPath) {
    ULARGE_INTEGER totalBytes;
    if (!GetDiskFreeSpaceExW(
        rootPath.c_str(),
        nullptr,
        &totalBytes,
        nullptr
    )) {
        return 0;
    }
    return static_cast<int64_t>(totalBytes.QuadPart);
}

int64_t GetVolumeFreeSpace(const std::wstring& rootPath) {
    ULARGE_INTEGER freeBytes;
    if (!GetDiskFreeSpaceExW(
        rootPath.c_str(),
        &freeBytes,
        nullptr,
        nullptr
    )) {
        return 0;
    }
    return static_cast<int64_t>(freeBytes.QuadPart);
}

bool IsVolumeSystem(const std::wstring& rootPath) {
    wchar_t systemDir[MAX_PATH];
    if (GetSystemDirectoryW(systemDir, ARRAYSIZE(systemDir)) == 0) {
        return false;
    }
    
    // Check if the system directory is on this volume
    return (rootPath[0] == systemDir[0]);
}

bool IsVolumeReadOnly(const std::wstring& rootPath) {
    DWORD flags;
    if (!GetVolumeInformationW(
        rootPath.c_str(),
        nullptr,
        0,
        nullptr,
        nullptr,
        &flags,
        nullptr,
        0
    )) {
        return false;
    }
    return (flags & FILE_READ_ONLY_VOLUME) != 0;
}

std::wstring GetVolumeUniqueId(const std::wstring& volumePath) {
    // Remove trailing backslash if present
    std::wstring path = volumePath;
    if (path.back() == L'\\') {
        path.pop_back();
    }
    return path;
}

int64_t GetVolumeAllocationUnitSize(const std::wstring& rootPath) {
    DWORD sectorsPerCluster, bytesPerSector;
    if (!GetDiskFreeSpaceW(
        rootPath.c_str(),
        &sectorsPerCluster,
        &bytesPerSector,
        nullptr,
        nullptr
    )) {
        return 0;
    }
    return static_cast<int64_t>(sectorsPerCluster) * bytesPerSector;
}

int GetVolumeDriveType(const std::wstring& rootPath) {
    return GetDriveTypeW(rootPath.c_str());
}

std::vector<std::wstring> GetVolumeMountPoints(const std::wstring& volumeName) {
    std::vector<std::wstring> mountPoints;
    std::wcout << L"Getting mount points for volume: " << volumeName << std::endl;
    
    wchar_t mountPath[MAX_PATH] = L"";
    DWORD returnLength = 0;

    // First call to get required buffer size
    if (!GetVolumePathNamesForVolumeNameW(
        volumeName.c_str(),
        mountPath,
        ARRAYSIZE(mountPath),
        &returnLength
    )) {
        DWORD error = GetLastError();
        std::cerr << "First call to GetVolumePathNamesForVolumeNameW failed. Error: " << error << std::endl;
        if (error != ERROR_MORE_DATA) {
            return mountPoints;
        }
    }

    // Allocate buffer of required size
    std::vector<wchar_t> buffer(returnLength);
    std::cout << "Allocated buffer of size " << returnLength << " for mount points" << std::endl;
    
    // Get the actual mount points
    if (!GetVolumePathNamesForVolumeNameW(
        volumeName.c_str(),
        buffer.data(),
        static_cast<DWORD>(buffer.size()),
        &returnLength
    )) {
        DWORD error = GetLastError();
        std::cerr << "Second call to GetVolumePathNamesForVolumeNameW failed. Error: " << error << std::endl;
        return mountPoints;
    }

    // FIX NEW-009: Parse the multi-string buffer with bounds checking
    for (DWORD i = 0; i < buffer.size();) {
        if (buffer[i] == L'\0') {
            break;
        }

        // Calculate remaining buffer size
        DWORD remaining = static_cast<DWORD>(buffer.size()) - i;
        // Find null terminator within remaining buffer
        DWORD len = 0;
        while (len < remaining && buffer[i + len] != L'\0') {
            len++;
        }

        // If no null terminator found, buffer is malformed
        if (len >= remaining) {
            std::cerr << "Malformed mount point buffer (missing null terminator)" << std::endl;
            break;
        }

        std::wstring mountPoint(&buffer[i], len);
        if (!mountPoint.empty()) {
            std::wcout << L"  Found mount point: " << mountPoint << std::endl;
            mountPoints.push_back(mountPoint);
        }

        // Move to the next string (skip past null terminator)
        i += len + 1;
    }

    std::cout << "Total mount points found: " << mountPoints.size() << std::endl;
    return mountPoints;
}

int GetDiskIdForVolume(const std::wstring& volumePath) {
    // Make sure the volume path has the correct format for CreateFileW
    std::wstring formattedPath = volumePath;
    if (formattedPath.back() != L'\\') {
        formattedPath += L'\\';  // Ensure trailing backslash is present
    }
    
    std::cout << "Opening volume: " << WideToNarrow(formattedPath) << std::endl;
    
    // Open the volume
    HANDLE hVolume = CreateFileW(
        formattedPath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );
    
    if (hVolume == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::cerr << "Failed to open volume " << WideToNarrow(formattedPath) 
                  << ". Error: " << error << std::endl;
        
        // Try an alternative approach for mounted volumes
        auto mountPoints = GetVolumeMountPoints(volumePath);
        if (!mountPoints.empty()) {
            std::wstring mountPoint = mountPoints[0];
            if (mountPoint.size() >= 2 && mountPoint[1] == L':') {
                return GetDiskIdFromDriveLetter(mountPoint);
            }
        }
        return -1;
    }
    
    // Use smart handle to ensure proper cleanup
    struct HandleCloser {
        void operator()(HANDLE h) { if (h != INVALID_HANDLE_VALUE) CloseHandle(h); }
    };
    std::unique_ptr<void, HandleCloser> volumeHandle(hVolume);
    
    // First call with a small buffer to get the required size
    DWORD bytesReturned = 0;
    VOLUME_DISK_EXTENTS initialExtents = {};
    
    if (!DeviceIoControl(
        hVolume,
        IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
        nullptr,
        0,
        &initialExtents,
        sizeof(initialExtents),
        &bytesReturned,
        nullptr
    )) {
        DWORD error = GetLastError();
        
        // If we need more data, allocate a larger buffer
        if (error == ERROR_MORE_DATA) {
            // Calculate required buffer size based on the number of extents
            // bytesReturned should contain the required size
            std::cout << "Volume has multiple extents, allocating larger buffer" << std::endl;
            
            // Allocate buffer large enough for the extents
            DWORD size = sizeof(VOLUME_DISK_EXTENTS) + 
                         (32 * sizeof(DISK_EXTENT)); // Space for up to 32 extents
            
            std::vector<BYTE> buffer(size);
            VOLUME_DISK_EXTENTS* pExtents = reinterpret_cast<VOLUME_DISK_EXTENTS*>(buffer.data());
            
            if (DeviceIoControl(
                hVolume,
                IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
                nullptr,
                0,
                pExtents,
                size,
                &bytesReturned,
                nullptr
            )) {
                // Check if the volume spans multiple disks
                if (pExtents->NumberOfDiskExtents > 1) {
                    // Log that this volume spans multiple disks
                    std::cout << "Volume " << WideToNarrow(formattedPath) 
                              << " spans " << pExtents->NumberOfDiskExtents << " disks" << std::endl;
                    
                    // Log the extents information
                    LogVolumeExtents(formattedPath, pExtents);
                    
                    // For the main volume record, use a special value to indicate a spanned volume
                    return -100;
                }
                else if (pExtents->NumberOfDiskExtents == 1) {
                    std::cout << "Volume " << WideToNarrow(formattedPath) 
                              << " is on physical disk " << pExtents->Extents[0].DiskNumber << std::endl;
                    return static_cast<int>(pExtents->Extents[0].DiskNumber);
                }
            } else {
                error = GetLastError();
                std::cerr << "Failed to get disk extents for volume " << WideToNarrow(formattedPath) 
                          << ". Error: " << error << std::endl;
            }
        } else {
            std::cerr << "Failed to get disk extents for volume " << WideToNarrow(formattedPath) 
                      << ". Error: " << error << std::endl;
        }
        
        // Try alternative method if DeviceIoControl fails
        auto mountPoints = GetVolumeMountPoints(volumePath);
        if (!mountPoints.empty()) {
            std::wstring mountPoint = mountPoints[0];
            if (mountPoint.size() >= 2 && mountPoint[1] == L':') {
                return GetDiskIdFromDriveLetter(mountPoint);
            }
        }
        
        return -1;
    }
    
    // If we got here, the initial call succeeded (rare for volumes with multiple extents)
    if (initialExtents.NumberOfDiskExtents > 1) {
        // Log that this volume spans multiple disks
        std::cout << "Volume " << WideToNarrow(formattedPath) 
                  << " spans " << initialExtents.NumberOfDiskExtents << " disks" << std::endl;
        
        // Log the extents information
        LogVolumeExtents(formattedPath, &initialExtents);
        
        // For the main volume record, use a special value to indicate a spanned volume
        return -100;
    }
    else if (initialExtents.NumberOfDiskExtents == 1) {
        std::cout << "Volume " << WideToNarrow(formattedPath) 
                  << " is on physical disk " << initialExtents.Extents[0].DiskNumber << std::endl;
        return static_cast<int>(initialExtents.Extents[0].DiskNumber);
    }
    
    return -1;
}

int GetDiskIdFromDriveLetter(const std::wstring& driveLetter) {
    // Ensure the drive letter ends with a backslash
    std::wstring formattedDriveLetter = driveLetter;
    if (formattedDriveLetter.back() != L'\\') {
        formattedDriveLetter += L'\\';
    }

    // Open the drive
    HANDLE hDrive = CreateFileW(
        formattedDriveLetter.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );

    if (hDrive == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to open drive: " << WideToNarrow(formattedDriveLetter) 
                  << ". Error: " << GetLastError() << std::endl;
        return -1;
    }

    // Use RAII wrapper for handle cleanup
    DeviceHandle driveHandle(hDrive);

    // Retrieve the disk number using IOCTL_STORAGE_GET_DEVICE_NUMBER
    STORAGE_DEVICE_NUMBER deviceNumber = {};
    DWORD bytesReturned = 0;

    if (!DeviceIoControl(
        hDrive,
        IOCTL_STORAGE_GET_DEVICE_NUMBER,
        nullptr,
        0,
        &deviceNumber,
        sizeof(deviceNumber),
        &bytesReturned,
        nullptr
    )) {
        std::cerr << "Failed to get device number for drive: " 
                  << WideToNarrow(formattedDriveLetter) 
                  << ". Error: " << GetLastError() << std::endl;
        return -1;
    }

    return static_cast<int>(deviceNumber.DeviceNumber);
}

// Helper function to log volume extents information
void LogVolumeExtents(const std::wstring& volumePath, VOLUME_DISK_EXTENTS* pExtents) {
    if (!pExtents) {
        std::cerr << "Error: Null pointer passed to LogVolumeExtents" << std::endl;
        return;
    }
    
    // Convert wide string to narrow for console output
    std::string narrowPath;
    try {
        int requiredSize = WideCharToMultiByte(CP_UTF8, 0, volumePath.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (requiredSize > 0) {
            narrowPath.resize(requiredSize);
            WideCharToMultiByte(CP_UTF8, 0, volumePath.c_str(), -1, &narrowPath[0], requiredSize, nullptr, nullptr);
            // Remove null terminator if present
            if (!narrowPath.empty() && narrowPath.back() == '\0') {
                narrowPath.pop_back();
            }
        }
    } catch (...) {
        narrowPath = "[conversion error]";
    }
    
    // Log the volume extents information
    std::cout << "Volume " << narrowPath << " has " 
              << pExtents->NumberOfDiskExtents << " extents:" << std::endl;
    
    for (DWORD i = 0; i < pExtents->NumberOfDiskExtents; i++) {
        std::cout << "  Extent " << i << ": Disk " << pExtents->Extents[i].DiskNumber
                  << ", Offset " << pExtents->Extents[i].StartingOffset.QuadPart
                  << ", Length " << pExtents->Extents[i].ExtentLength.QuadPart << std::endl;
    }
}

// Function to store volume extents in the database
void StoreVolumeExtentsVoid(sqlite3* db, const std::string& inventoryId, int volumeId, VOLUME_DISK_EXTENTS* pExtents) {
    // Prepare the insert statement for volume extents
    const char* extentSql = R"(
        INSERT INTO app__VolumeExtents (
            InventoryID, VolumeID, DiskID, ExtentIndex, StartingOffset, ExtentLength
        ) VALUES (?, ?, ?, ?, ?, ?)
    )";
    
    Statement extentStmt(db, extentSql);
    
    for (DWORD i = 0; i < pExtents->NumberOfDiskExtents; i++) {
        extentStmt.Reset();
        extentStmt.Bind(1, inventoryId);
        extentStmt.Bind(2, volumeId);
        extentStmt.Bind(3, static_cast<int>(pExtents->Extents[i].DiskNumber));
        extentStmt.Bind(4, static_cast<int>(i));
        extentStmt.Bind(5, static_cast<int64_t>(pExtents->Extents[i].StartingOffset.QuadPart));
        extentStmt.Bind(6, static_cast<int64_t>(pExtents->Extents[i].ExtentLength.QuadPart));
        
        if (extentStmt.Step() != SQLITE_DONE) {
            throw VolumeCollectionException("Failed to insert volume extent data: " + 
                std::string(sqlite3_errmsg(db)));
        }
    }
}

// Function to verify the VolumeExtents table exists and is properly structured
bool VerifyVolumeExtentsTable(sqlite3* db) {
    const char* checkTableSql = "SELECT name FROM sqlite_master WHERE type='table' AND name='app__VolumeExtents';";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, checkTableSql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to prepare statement to check VolumeExtents table: " 
                  << sqlite3_errmsg(db) << std::endl;
        return false;
    }
    
    bool tableExists = false;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        tableExists = true;
    }
    
    sqlite3_finalize(stmt);
    
    if (!tableExists) {
        std::cerr << "app__VolumeExtents table does not exist!" << std::endl;
        
        // Create the table if it doesn't exist
        const char* createTableSql = R"(
            CREATE TABLE IF NOT EXISTS app__VolumeExtents (
                InventoryID TEXT NOT NULL,
                VolumeID INTEGER NOT NULL,
                DiskID INTEGER NOT NULL,
                ExtentIndex INTEGER NOT NULL,
                StartingOffset BIGINT NOT NULL,
                ExtentLength BIGINT NOT NULL,
                PRIMARY KEY (InventoryID, VolumeID, ExtentIndex)
            );
        )";
        
        char* errMsg = nullptr;
        rc = sqlite3_exec(db, createTableSql, nullptr, nullptr, &errMsg);
        
        if (rc != SQLITE_OK) {
            std::cerr << "Failed to create VolumeExtents table: " << errMsg << std::endl;
            sqlite3_free(errMsg);
            return false;
        }
        
        std::cout << "Created app__VolumeExtents table" << std::endl;
        return true;
    }
    
    return true;
}

// Function to test direct insertion into the VolumeExtents table
bool TestInsertVolumeExtent(sqlite3* db, const std::string& inventoryId) {
    const char* sql = R"(
        INSERT INTO app__VolumeExtents (
            InventoryID, VolumeID, DiskID, ExtentIndex, StartingOffset, ExtentLength
        ) VALUES (?, ?, ?, ?, ?, ?)
    )";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        std::cerr << "Failed to prepare statement for test insert: " 
                  << sqlite3_errmsg(db) << std::endl;
        return false;
    }
    
    // Bind test values
    sqlite3_bind_text(stmt, 1, inventoryId.c_str(), -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, 999);  // Test volume ID
    sqlite3_bind_int(stmt, 3, 888);  // Test disk ID
    sqlite3_bind_int(stmt, 4, 0);    // Test extent index
    sqlite3_bind_int64(stmt, 5, 12345);  // Test starting offset
    sqlite3_bind_int64(stmt, 6, 67890);  // Test extent length
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        std::cerr << "Test insert failed: " << sqlite3_errmsg(db) << std::endl;
        return false;
    }
    
    std::cout << "Test insert into app__VolumeExtents succeeded" << std::endl;
    return true;
}

// Helper function to retrieve and store volume extents
bool RetrieveAndStoreVolumeExtents(sqlite3* db, const std::string& inventoryId, int volumeId, const std::wstring& volumePath) {
    std::cout << "Retrieving extents for volume " << volumeId << " at path: " << WideToNarrow(volumePath) << std::endl;
    
    // Ensure the path has a trailing backslash
    std::wstring formattedPath = volumePath;
    if (formattedPath.back() != L'\\') {
        formattedPath += L'\\';
    }
    
    // Open the volume
    HANDLE hVolume = CreateFileW(
        formattedPath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );
    
    if (hVolume == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::cerr << "Failed to open volume for extent retrieval: " << WideToNarrow(formattedPath) 
                  << ". Error: " << error << std::endl;
        return false;
    }
    
    // Use smart handle for cleanup
    struct HandleCloser {
        void operator()(HANDLE h) { if (h != INVALID_HANDLE_VALUE) CloseHandle(h); }
    };
    std::unique_ptr<void, HandleCloser> volumeHandle(hVolume);
    
    // First call with a small buffer to get the required size
    DWORD bytesReturned = 0;
    VOLUME_DISK_EXTENTS initialExtents = {};
    
    BOOL result = DeviceIoControl(
        hVolume,
        IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
        nullptr,
        0,
        &initialExtents,
        sizeof(initialExtents),
        &bytesReturned,
        nullptr
    );
    
    DWORD error = GetLastError();
    
    // Prepare the insert statement
    const char* extentSql = R"(
        INSERT INTO app__VolumeExtents (
            InventoryID, VolumeID, DiskID, ExtentIndex, StartingOffset, ExtentLength
        ) VALUES (?, ?, ?, ?, ?, ?)
    )";
    
    Statement extentStmt(db, extentSql);
    
    if (!result && error == ERROR_MORE_DATA) {
        // Calculate required buffer size based on bytesReturned
        std::cout << "Volume has multiple extents, allocating larger buffer" << std::endl;
        
        // Allocate a buffer large enough for all extents
        // We'll allocate space for up to 64 extents to be safe
        DWORD size = sizeof(VOLUME_DISK_EXTENTS) + (64 * sizeof(DISK_EXTENT));
        std::vector<BYTE> buffer(size);
        VOLUME_DISK_EXTENTS* pExtents = reinterpret_cast<VOLUME_DISK_EXTENTS*>(buffer.data());
        
        if (DeviceIoControl(
            hVolume,
            IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
            nullptr,
            0,
            pExtents,
            size,
            &bytesReturned,
            nullptr
        )) {
            std::cout << "Retrieved " << pExtents->NumberOfDiskExtents 
                      << " extents for volume " << volumeId << std::endl;
            
            // Store each extent in the database
            for (DWORD i = 0; i < pExtents->NumberOfDiskExtents; i++) {
                extentStmt.Reset();
                extentStmt.Bind(1, inventoryId);
                extentStmt.Bind(2, volumeId);
                extentStmt.Bind(3, static_cast<int>(pExtents->Extents[i].DiskNumber));
                extentStmt.Bind(4, static_cast<int>(i));
                extentStmt.Bind(5, static_cast<int64_t>(pExtents->Extents[i].StartingOffset.QuadPart));
                extentStmt.Bind(6, static_cast<int64_t>(pExtents->Extents[i].ExtentLength.QuadPart));
                
                int result = extentStmt.Step();
                if (result != SQLITE_DONE) {
                    std::cerr << "Failed to insert extent " << i << " for volume " << volumeId 
                              << ". Error: " << sqlite3_errmsg(db) << " (code " << result << ")" << std::endl;
                } else {
                    std::cout << "  Stored extent " << i << " for volume " << volumeId 
                              << " (Disk: " << pExtents->Extents[i].DiskNumber
                              << ", Offset: " << pExtents->Extents[i].StartingOffset.QuadPart
                              << ", Length: " << pExtents->Extents[i].ExtentLength.QuadPart
                              << ")" << std::endl;
                }
            }
            return true;
        } else {
            error = GetLastError();
            std::cerr << "Failed to get disk extents for volume " << WideToNarrow(volumePath)
                      << ". Error: " << error << std::endl;
            return false;
        }
    } else if (result) {
        // Initial call succeeded (rare for volumes with multiple extents)
        std::cout << "Retrieved " << initialExtents.NumberOfDiskExtents 
                  << " extents for volume " << volumeId << std::endl;
        
        // Store each extent in the database
        for (DWORD i = 0; i < initialExtents.NumberOfDiskExtents; i++) {
            extentStmt.Reset();
            extentStmt.Bind(1, inventoryId);
            extentStmt.Bind(2, volumeId);
            extentStmt.Bind(3, static_cast<int>(initialExtents.Extents[i].DiskNumber));
            extentStmt.Bind(4, static_cast<int>(i));
            extentStmt.Bind(5, static_cast<int64_t>(initialExtents.Extents[i].StartingOffset.QuadPart));
            extentStmt.Bind(6, static_cast<int64_t>(initialExtents.Extents[i].ExtentLength.QuadPart));
            
            int result = extentStmt.Step();
            if (result != SQLITE_DONE) {
                std::cerr << "Failed to insert extent " << i << " for volume " << volumeId 
                          << ". Error: " << sqlite3_errmsg(db) << " (code " << result << ")" << std::endl;
            } else {
                std::cout << "  Stored extent " << i << " for volume " << volumeId 
                          << " (Disk: " << initialExtents.Extents[i].DiskNumber
                          << ", Offset: " << initialExtents.Extents[i].StartingOffset.QuadPart
                          << ", Length: " << initialExtents.Extents[i].ExtentLength.QuadPart
                          << ")" << std::endl;
            }
        }
        return true;
    } else {
        std::cerr << "Failed to get disk extents for volume " << WideToNarrow(volumePath) 
                  << ". Error: " << error << std::endl;
        return false;
    }
}

// Create a helper function to reduce duplication
bool StoreVolumeExtents(sqlite3* db, int inventoryId, int volumeId, VOLUME_DISK_EXTENTS* pExtents) {
    bool success = true;
    
    // Prepare the insert statement
    const char* extentSql = R"(
        INSERT INTO app__VolumeExtents (
            InventoryID, VolumeID, DiskID, ExtentIndex, StartingOffset, ExtentLength
        ) VALUES (?, ?, ?, ?, ?, ?)
    )";
    
    ::Statement extentStmt(db, extentSql);
    
    for (DWORD i = 0; i < pExtents->NumberOfDiskExtents; i++) {
        extentStmt.Reset();
        extentStmt.Bind(1, std::to_string(inventoryId));
        extentStmt.Bind(2, volumeId);
        extentStmt.Bind(3, static_cast<int>(pExtents->Extents[i].DiskNumber));
        extentStmt.Bind(4, static_cast<int>(i));
        extentStmt.Bind(5, static_cast<int64_t>(pExtents->Extents[i].StartingOffset.QuadPart));
        extentStmt.Bind(6, static_cast<int64_t>(pExtents->Extents[i].ExtentLength.QuadPart));
        
        int result = extentStmt.Step();
        if (result != SQLITE_DONE) {
            std::cerr << "Failed to insert extent " << i << " for volume " << volumeId 
                      << ". Error: " << sqlite3_errmsg(db) << " (code " << result << ")" << std::endl;
            success = false;
        } else {
            std::cout << "  Stored extent " << i << " for volume " << volumeId 
                      << " (Disk: " << pExtents->Extents[i].DiskNumber
                      << ", Offset: " << pExtents->Extents[i].StartingOffset.QuadPart
                      << ", Length: " << pExtents->Extents[i].ExtentLength.QuadPart
                      << ")" << std::endl;
        }
    }
    
    return success;
}

// Use transactions for the extent insertion process
bool CollectVolumeExtents(sqlite3* db, const std::string& inventoryId, int volumeId, const std::wstring& volumePath) {
    // Ensure volume path has proper format for direct access
    std::wstring formattedPath = volumePath;
    if (!volumePath.empty() && volumePath.back() == L'\\') {
        formattedPath = volumePath.substr(0, volumePath.length() - 1);
    }
    
    // Try to open the volume
    HANDLE hVolume = CreateFileW(
        formattedPath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );
    
    if (hVolume == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::cerr << "Failed to open volume " << WideToNarrow(formattedPath) 
                  << ". Error: " << error << std::endl;
        
        // Try an alternative approach for mounted volumes
        auto mountPoints = GetVolumeMountPoints(volumePath);
        if (!mountPoints.empty()) {
            for (const auto& mountPoint : mountPoints) {
                std::wcout << L"Trying to access volume using mount point: " << mountPoint << std::endl;
                if (RetrieveAndStoreVolumeExtentsUsingDriveLetter(db, inventoryId, volumeId, mountPoint)) {
                    return true;
                }
            }
        }
        return false;
    }
    
    // Use RAII to ensure handle is closed
    DeviceHandle volumeHandle(hVolume);
    
    // First try with a small buffer
    DWORD bufferSize = sizeof(VOLUME_DISK_EXTENTS) + (16 * sizeof(DISK_EXTENT));
    std::vector<BYTE> buffer(bufferSize);
    VOLUME_DISK_EXTENTS* pExtents = reinterpret_cast<VOLUME_DISK_EXTENTS*>(buffer.data());
    DWORD bytesReturned = 0;
    
    BOOL result = DeviceIoControl(
        hVolume,
        IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
        nullptr,
        0,
        pExtents,
        bufferSize,
        &bytesReturned,
        nullptr
    );
    
    if (!result) {
        DWORD error = GetLastError();
        
        // If buffer too small, try with progressively larger buffers
        if (error == ERROR_MORE_DATA || error == ERROR_INSUFFICIENT_BUFFER) {
            // Try with increasingly larger buffers
            for (int multiplier : {32, 64, 128, 256, 512}) {
                bufferSize = sizeof(VOLUME_DISK_EXTENTS) + (multiplier * sizeof(DISK_EXTENT));
                buffer.resize(bufferSize);
                pExtents = reinterpret_cast<VOLUME_DISK_EXTENTS*>(buffer.data());
                
                std::cout << "Retrying with larger buffer for " << multiplier << " extents" << std::endl;
                
                result = DeviceIoControl(
                    hVolume,
                    IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
                    nullptr,
                    0,
                    pExtents,
                    bufferSize,
                    &bytesReturned,
                    nullptr
                );
                
                if (result) {
                    std::cout << "Successfully retrieved " << pExtents->NumberOfDiskExtents 
                              << " extents with buffer for " << multiplier << " extents" << std::endl;
                    return StoreVolumeExtents(db, inventoryId, volumeId, pExtents);
                }
                
                error = GetLastError();
                if (error != ERROR_MORE_DATA && error != ERROR_INSUFFICIENT_BUFFER) {
                    break;  // Different error, no point in trying larger buffers
                }
            }
        }
        
        std::cerr << "Failed to get disk extents for volume " << WideToNarrow(formattedPath) 
                  << ". Error: " << error << std::endl;
        return false;
    }
    
    // If we got here, the initial call succeeded
    return StoreVolumeExtents(db, inventoryId, volumeId, pExtents);
}

bool StoreVolumeExtents(sqlite3* db, const std::string& inventoryId, int volumeId, VOLUME_DISK_EXTENTS* pExtents) {
    if (!pExtents) {
        std::cerr << "Error: Null pointer passed to StoreVolumeExtents" << std::endl;
        return false;
    }
    
    try {
        // Prepare the SQL statement
        const char* sql = R"(
            INSERT INTO app__VolumeExtents (
                InventoryID, VolumeID, DiskID, ExtentIndex, StartingOffset, ExtentLength
            ) VALUES (?, ?, ?, ?, ?, ?)
        )";

        Statement stmt(db, sql);

        // Iterate through the extents and insert them into the database
        for (DWORD i = 0; i < pExtents->NumberOfDiskExtents; ++i) {
            const DISK_EXTENT& extent = pExtents->Extents[i];

            stmt.Reset();
            stmt.Bind(1, inventoryId);
            stmt.Bind(2, volumeId);
            stmt.Bind(3, static_cast<int>(extent.DiskNumber));
            stmt.Bind(4, static_cast<int>(i));
            stmt.Bind(5, static_cast<int64_t>(extent.StartingOffset.QuadPart));
            stmt.Bind(6, static_cast<int64_t>(extent.ExtentLength.QuadPart));

            if (stmt.Step() != SQLITE_DONE) {
                std::cerr << "Failed to insert extent " << i << " for volume " << volumeId 
                          << ". Error: " << sqlite3_errmsg(db) << std::endl;
                return false;
            }
            
            std::cout << "  Stored extent " << i << " for volume " << volumeId 
                      << " (Disk: " << extent.DiskNumber
                      << ", Offset: " << extent.StartingOffset.QuadPart
                      << ", Length: " << extent.ExtentLength.QuadPart
                      << ")" << std::endl;
        }

        return true;
    } catch (const std::exception& e) {
        std::cerr << "Error in StoreVolumeExtents: " << e.what() << std::endl;
        return false;
    }
}

bool RetrieveAndStoreVolumeExtentsUsingDriveLetter(sqlite3* db, const std::string& inventoryId, 
                                                  int volumeId, const std::wstring& driveLetter) {
    if (driveLetter.empty() || driveLetter.size() < 2 || driveLetter[1] != L':') {
        std::cerr << "Invalid drive letter format for volume " << volumeId << std::endl;
        return false;
    }

    // Format the drive path with trailing backslash
    std::wstring drivePath = driveLetter;
    if (drivePath.back() != L'\\') {
        drivePath += L'\\';
    }

    std::cout << "Trying to access volume using drive letter: " << WideToNarrow(drivePath) << std::endl;

    // Open the volume using the drive letter
    HANDLE hVolume = CreateFileW(
        drivePath.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );

    // Use smart handle for cleanup
    struct HandleCloser {
        void operator()(HANDLE h) { if (h != INVALID_HANDLE_VALUE) CloseHandle(h); }
    };
    std::unique_ptr<void, HandleCloser> volumeHandle(hVolume);

    // Get the disk extents for this volume
    // Fix: Call CollectVolumeExtents with the correct number of arguments
    return CollectVolumeExtents(db, inventoryId, volumeId, drivePath);
}

bool StoreVolumeMountPoints(sqlite3* db, const std::string& inventoryId, int volumeId, const std::vector<std::wstring>& mountPoints) {
    std::cout << "StoreVolumeMountPoints: Volume " << volumeId << " has " << mountPoints.size() << " mount points" << std::endl;
    
    if (mountPoints.empty()) {
        std::cout << "  No mount points to store for volume " << volumeId << std::endl;
        return true;  // Nothing to store
    }
    
    // Debug: Print all mount points
    for (const auto& mountPoint : mountPoints) {
        std::wcout << L"  Mount point: " << mountPoint << std::endl;
    }
    
    // Prepare the insert statement
    const char* sql = R"(
        INSERT INTO app__VolumeMounts (
            InventoryID, VolumeID, MountPoint
        ) VALUES (?, ?, ?)
    )";
    
    Statement stmt(db, sql);
    
    // Insert each mount point
    for (const auto& mountPoint : mountPoints) {
        stmt.Reset();
        stmt.Bind(1, inventoryId);
        stmt.Bind(2, volumeId);
        std::string narrowMountPoint = WideToNarrow(mountPoint);
        stmt.Bind(3, narrowMountPoint);
        
        std::cout << "  Inserting mount point: " << narrowMountPoint << " for volume " << volumeId << std::endl;
        
        if (stmt.Step() != SQLITE_DONE) {
            std::cerr << "  Failed to insert mount point. SQLite error: " << sqlite3_errmsg(db) << std::endl;
            return false;
        }
    }
    
    std::cout << "  Successfully stored all mount points for volume " << volumeId << std::endl;
    return true;
}

int VolumeCollector::CollectAndStoreVolumeInfo(sqlite3* db, const std::string& inventoryId) {
    std::cout << "Starting volume information collection for inventory ID: " << inventoryId << std::endl;
    
    try {
        // Start a transaction for better performance
        std::cout << "Starting transaction for volume collection" << std::endl;
        Transaction transaction(db);
        
        // Collect volume information
        std::cout << "Collecting volume information..." << std::endl;
        std::vector<VolumeInfo> volumes = CollectVolumeInfo();
        std::cout << "Found " << volumes.size() << " volumes" << std::endl;
        
        // Prepare the insert statement
        const char* sql = R"(
            INSERT INTO app__Volumes (
                InventoryID, VolumeID, DiskID, Label, FileSystem, Size, FreeSpace,
                IsSystem, IsReadOnly, Status, UniqueID, AllocationUnitSize, DriveType,
                IsEncrypted, IsCompressed, ShadowCopyEnabled, ShadowCopyStorageMax
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        )";
        
        Statement stmt(db, sql);
        
        // Insert each volume
        for (const auto& volume : volumes) {
            std::cout << "\nProcessing volume " << volume.volumeId << ": " << std::endl;
            if (!volume.label.empty()) {
                std::cout << "  Label: " << WideToNarrow(volume.label) << std::endl;
            }
            std::cout << "  File System: " << WideToNarrow(volume.fileSystem) << std::endl;
            std::cout << "  Size: " << volume.size << " bytes" << std::endl;
            
            // Convert wide strings to UTF-8 for storage
            std::string label = WideToNarrow(volume.label);
            std::string fileSystem = WideToNarrow(volume.fileSystem);
            std::string status = WideToNarrow(volume.status);
            std::string uniqueId = WideToNarrow(volume.uniqueId);
            
            // Bind parameters
            stmt.Bind(1, inventoryId);
            stmt.Bind(2, volume.volumeId);

            // DiskID: Convert -1 or -100 (spanned volume) to NULL
            // -1 = couldn't determine disk ID
            // -100 = spanned volume (spans multiple disks, handled via VolumeExtents)
            if (volume.diskId == -1 || volume.diskId == -100 || volume.diskId < 0) {
                stmt.BindNull(3);
            } else {
                stmt.Bind(3, volume.diskId);
            }

            stmt.Bind(4, label);
            stmt.Bind(5, fileSystem);
            stmt.Bind(6, volume.size);
            stmt.Bind(7, volume.freeSpace);
            stmt.Bind(8, volume.isSystem ? 1 : 0);
            stmt.Bind(9, volume.isReadOnly ? 1 : 0);
            stmt.Bind(10, status);
            stmt.Bind(11, uniqueId);
            stmt.Bind(12, volume.allocationUnitSize);
            stmt.Bind(13, volume.driveType);
            stmt.Bind(14, volume.isEncrypted ? 1 : 0);
            stmt.Bind(15, volume.isCompressed ? 1 : 0);
            stmt.Bind(16, volume.shadowCopyEnabled ? 1 : 0);
            stmt.Bind(17, volume.shadowCopyStorageMax);
            
            // Execute the statement
            int rc = stmt.Step();
            if (rc != SQLITE_DONE) {
                std::string error = sqlite3_errmsg(db);
                std::cerr << "Failed to insert volume " << volume.volumeId << ": " << error << std::endl;
                // Continue with next volume
            }
            std::cout << "  Successfully inserted volume " << volume.volumeId << std::endl;
            
            // Reset the statement for the next iteration
            stmt.Reset();
            
            // Store volume mount points
            if (!volume.mountPoints.empty()) {
                std::cout << "  Volume has " << volume.mountPoints.size() << " mount points" << std::endl;
                if (!StoreVolumeMountPoints(db, inventoryId, volume.volumeId, volume.mountPoints)) {
                    std::cerr << "Failed to store mount points for volume " << volume.volumeId << std::endl;
                }
            }
            
            // Collect and store volume extents
            if (volume.diskId == -100) {
                // This is a spanned volume, collect extents for each mount point
                for (const auto& mountPoint : volume.mountPoints) {
                    if (mountPoint.size() >= 2 && mountPoint[1] == L':') {
                        std::cout << "  Collecting extents for spanned volume using mount point: " 
                                  << WideToNarrow(mountPoint) << std::endl;
                        if (!RetrieveAndStoreVolumeExtentsUsingDriveLetter(db, inventoryId, volume.volumeId, mountPoint)) {
                            std::cerr << "Failed to collect extents for volume " << volume.volumeId 
                                      << " using mount point " << WideToNarrow(mountPoint) << std::endl;
                        }
                        break;  // One successful mount point is enough
                    }
                }
            }
            else if (!volume.uniqueId.empty()) {
                // Regular volume, collect extents directly
                if (!CollectVolumeExtents(db, inventoryId, volume.volumeId, volume.uniqueId)) {
                    std::cerr << "Failed to collect extents for volume " << volume.volumeId << std::endl;
                    
                    // Try using mount points as fallback
                    for (const auto& mountPoint : volume.mountPoints) {
                        if (mountPoint.size() >= 2 && mountPoint[1] == L':') {
                            std::cout << "  Trying to collect extents using mount point: " 
                                      << WideToNarrow(mountPoint) << std::endl;
                            if (RetrieveAndStoreVolumeExtentsUsingDriveLetter(db, inventoryId, volume.volumeId, mountPoint)) {
                                break;  // One successful mount point is enough
                            }
                        }
                    }
                }
            }
        }
        
        // Commit the transaction
        std::cout << "Committing transaction..." << std::endl;
        transaction.Commit();
        std::cout << "Transaction committed successfully" << std::endl;
        
        // Return the number of volumes processed
        return static_cast<int>(volumes.size());
    }
    catch (const std::exception& e) {
        std::cerr << "Exception during volume collection: " << e.what() << std::endl;
        // Transaction will automatically roll back in its destructor
        throw VolumeCollectionException(std::string("Failed to collect and store volume info: ") + e.what());
    }
}

} // namespace VolumeCollector
