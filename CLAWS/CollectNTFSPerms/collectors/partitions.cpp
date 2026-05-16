#include "../collectors/partitions.h"
#include "../database/statement.h"
#include "../database/transaction.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstdint>  // Added for int64_t
#include <windows.h>
#include <winioctl.h>
#include <iomanip>
#include <sstream>

struct PartitionInfo {
    int diskId;
    int partitionIndex;
    int64_t startOffset;
    int64_t lengthBytes;
    std::string partitionType;
    std::string gptGuid;
    int mbrType;
    int volumeId;  // Changed from std::string to int to match database schema
};

// Forward declaration of helper function
std::vector<PartitionInfo> GetDiskPartitions(HANDLE hDisk, int diskId);

// COMP-001: Helper function to decode MBR partition type to human-readable name
const char* GetMbrPartitionTypeName(BYTE type) {
    switch (type) {
        case 0x00: return "Empty";
        case 0x01: return "FAT12";
        case 0x04: return "FAT16 (<32MB)";
        case 0x05: return "Extended";
        case 0x06: return "FAT16";
        case 0x07: return "NTFS/exFAT";
        case 0x0B: return "FAT32 (CHS)";
        case 0x0C: return "FAT32 (LBA)";
        case 0x0E: return "FAT16 (LBA)";
        case 0x0F: return "Extended (LBA)";
        case 0x11: return "Hidden FAT12";
        case 0x14: return "Hidden FAT16 (<32MB)";
        case 0x16: return "Hidden FAT16";
        case 0x17: return "Hidden NTFS/exFAT";
        case 0x1B: return "Hidden FAT32 (CHS)";
        case 0x1C: return "Hidden FAT32 (LBA)";
        case 0x1E: return "Hidden FAT16 (LBA)";
        case 0x27: return "Windows RE";
        case 0x42: return "Dynamic Disk";
        case 0x82: return "Linux Swap";
        case 0x83: return "Linux";
        case 0x84: return "Hibernation";
        case 0x85: return "Linux Extended";
        case 0x86: return "NTFS Volume Set";
        case 0x87: return "NTFS Volume Set";
        case 0x8E: return "Linux LVM";
        case 0xA0: return "Hibernation";
        case 0xA5: return "FreeBSD";
        case 0xA6: return "OpenBSD";
        case 0xA8: return "macOS UFS";
        case 0xA9: return "NetBSD";
        case 0xAB: return "macOS Boot";
        case 0xAF: return "macOS HFS/HFS+";
        case 0xEE: return "GPT Protective";
        case 0xEF: return "EFI System";
        default: return "Unknown";
    }
}

bool CollectPartitions(sqlite3* db, const std::string& inventoryId, int* partitionCount) {
    // Local variable to track count if caller doesn't need it
    int localPartitionCount = 0;
    int& countRef = partitionCount ? *partitionCount : localPartitionCount;
    countRef = 0;  // Initialize the counter
    
    // Verify table exists with more detailed error handling
    const char* checkTableSql = "SELECT name FROM sqlite_master WHERE type='table' AND name='app__Partitions';";
    Statement checkStmt(db, checkTableSql);
    if (checkStmt.Step() != SQLITE_ROW) {
        std::cerr << "ERROR: app__Partitions table does not exist!" << std::endl;
        return false;
    }
    
    // Prepare the insert statement
    const char* sql = R"(
        INSERT INTO app__Partitions (
            InventoryID, PartitionID, DiskID, PartitionIndex,
            StartOffset, LengthBytes, PartitionType, GPT_GUID,
            MBR_Type, VolID
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    )";
    
    Statement stmt(db, sql);
    
    // Start transaction
    std::cout << "\nStarting transaction for partition collection" << std::endl;
    Transaction transaction(db);
    
    try {
        // Delete existing partitions for this inventory to avoid conflicts
        const char* deleteSql = "DELETE FROM app__Partitions WHERE InventoryID = ?";
        Statement deleteStmt(db, deleteSql);
        deleteStmt.Bind(1, inventoryId);
        int result = deleteStmt.Step();
        if (result != SQLITE_DONE) {
            std::cerr << "Failed to delete existing partitions: " << sqlite3_errmsg(db) << " (code: " << result << ")" << std::endl;
        }
        
        // Get next partition ID
        const char* maxIdSql = "SELECT COALESCE(MAX(PartitionID), 0) + 1 FROM app__Partitions WHERE InventoryID = ?";
        Statement maxIdStmt(db, maxIdSql);
        maxIdStmt.Bind(1, inventoryId);
        int nextPartitionId = 1; // Default
        if (maxIdStmt.Step() == SQLITE_ROW) {
            nextPartitionId = maxIdStmt.ColumnInt(0);
        }
        
        // Query all disks from the database
        const char* diskSql = "SELECT DiskID FROM app__Disks WHERE InventoryID = ?";
        Statement diskStmt(db, diskSql);
        diskStmt.Bind(1, inventoryId);
        
        int diskCount = 0;

        std::cout << "Querying disks for inventory ID: " << inventoryId << std::endl;
        
        // Count disks first to verify we have data
        const char* countSql = "SELECT COUNT(*) FROM app__Disks WHERE InventoryID = ?";
        Statement countStmt(db, countSql);
        countStmt.Bind(1, inventoryId);
        int diskDbCount = 0;
        if (countStmt.Step() == SQLITE_ROW) {
            int count = countStmt.ColumnInt(0);
        }

        // Process each disk
        while (diskStmt.Step() == SQLITE_ROW) {
            int diskId = diskStmt.ColumnInt(0);
            diskCount++;
            
            // Construct the disk path
            std::string diskPath = "\\\\.\\PhysicalDrive" + std::to_string(diskId);
            
            // Open the disk
            HANDLE hDisk = CreateFileA(
                diskPath.c_str(),
                GENERIC_READ,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                NULL,
                OPEN_EXISTING,
                0,
                NULL
            );
            
            if (hDisk == INVALID_HANDLE_VALUE) {
                DWORD error = GetLastError();
                std::cerr << "Failed to open disk " << diskPath << ": Error " << error << std::endl;
                continue;
            }
            
            // Get partitions for this disk
            std::vector<PartitionInfo> partitions = GetDiskPartitions(hDisk, diskId);
            CloseHandle(hDisk);
            
            // Process each partition
            for (const auto& partition : partitions) {
                // For each partition, look up the correct VolumeID
                const char* volumeSql = R"(
                    SELECT VolumeID
                    FROM app__VolumeExtents
                    WHERE InventoryID = ?
                    AND StartingOffset = ?
                    AND DiskID = ?
                )";
                Statement volumeStmt(db, volumeSql);

                // Try to get volume information
                volumeStmt.Bind(1, inventoryId);
                volumeStmt.Bind(2, partition.startOffset);
                volumeStmt.Bind(3, partition.diskId);

                int volumeId = 0; // Default if no matching volume
                bool hasMatchingVolume = false;
                if (volumeStmt.Step() == SQLITE_ROW) {
                    volumeId = volumeStmt.ColumnInt(0);
                    hasMatchingVolume = (volumeId > 0);
                }

                // Bind values with error checking
                try {
                    stmt.Reset();
                    stmt.Bind(1, inventoryId);
                    stmt.Bind(2, nextPartitionId);
                    stmt.Bind(3, partition.diskId);
                    stmt.Bind(4, partition.partitionIndex);
                    stmt.Bind(5, partition.startOffset);
                    stmt.Bind(6, partition.lengthBytes);
                    stmt.Bind(7, partition.partitionType);
                    stmt.Bind(8, partition.gptGuid);
                    stmt.Bind(9, partition.mbrType);

                    // FIX: Use NULL instead of 0 for VolID when no matching volume found
                    // This prevents FK validation errors (FK_app_Partitions_Volumes)
                    if (hasMatchingVolume) {
                        stmt.Bind(10, volumeId);
                    } else {
                        stmt.BindNull(10);
                    }
                    
                    result = stmt.Step();
                    if (result != SQLITE_DONE) {
                        std::cerr << "Failed to insert partition: " << sqlite3_errmsg(db) << " (code: " << result << ")" << std::endl;
                    } else {
                        countRef++;
                        nextPartitionId++;
                    }
                } catch (const std::exception& e) {
                    std::cerr << "Exception during binding: " << e.what() << std::endl;
                }
            }
        }
        
        // Commit transaction
        transaction.Commit();
        std::cout << "\nProcessed " << diskCount << " disks and inserted " << countRef << " partitions" << std::endl;
        return countRef > 0;
    } catch (const std::exception& e) {
        std::cerr << "Exception in CollectPartitions: " << e.what() << std::endl;
        return false;
    }
}

// Helper function to get partition information from a disk
std::vector<PartitionInfo> GetDiskPartitions(HANDLE hDisk, int diskId) {
    std::vector<PartitionInfo> partitions;
    std::cout << "\nGetting partitions for disk " << diskId << std::endl;
    
    // Get drive layout information
    DWORD bytesReturned = 0;
    
    // First try with a small buffer for a single partition
    DRIVE_LAYOUT_INFORMATION_EX layoutInfo = {0};

    if (!DeviceIoControl(
        hDisk,
        IOCTL_DISK_GET_DRIVE_LAYOUT_EX,
        NULL,
        0,
        &layoutInfo,
        sizeof(layoutInfo),
        &bytesReturned,
        NULL)) {

        DWORD error = GetLastError();

        if (error == ERROR_INSUFFICIENT_BUFFER || error == ERROR_MORE_DATA) {
            // Expected: Disk has more partitions than fit in initial buffer
            // Windows API pattern: Try with small buffer, then allocate larger buffer if needed
            std::cout << "Disk has multiple partitions\n";
            std::cout << "Initial buffer insufficient, allocating larger buffer..." << std::endl;

            // Calculate buffer size for all partitions
            // Note: bytesReturned is often 0 with ERROR_INSUFFICIENT_BUFFER, so we assume max 128 partitions
            DWORD bufferSize = sizeof(DRIVE_LAYOUT_INFORMATION_EX) +
                              (128 * sizeof(PARTITION_INFORMATION_EX)); // Assume max 128 partitions
            
            std::vector<BYTE> buffer(bufferSize);
            PDRIVE_LAYOUT_INFORMATION_EX pLayoutInfo = 
                reinterpret_cast<PDRIVE_LAYOUT_INFORMATION_EX>(&buffer[0]);
            
            if (DeviceIoControl(
                hDisk,
                IOCTL_DISK_GET_DRIVE_LAYOUT_EX,
                NULL,
                0,
                pLayoutInfo,
                bufferSize,
                &bytesReturned,
                NULL)) {
                
                std::cout << "Got disk layout, partition count: " << pLayoutInfo->PartitionCount << std::endl;
                
                // Process partitions
                for (DWORD i = 0; i < pLayoutInfo->PartitionCount; i++) {
                    PARTITION_INFORMATION_EX& partInfo = pLayoutInfo->PartitionEntry[i];
                    
                    // Skip empty partitions
                    if (partInfo.PartitionLength.QuadPart == 0) {
                        std::cout << "Skipping empty partition at index " << i << std::endl;
                        continue;
                    }
                    
                    PartitionInfo partition;
                    partition.diskId = diskId;
                    partition.partitionIndex = static_cast<int>(i);
                    partition.startOffset = static_cast<int64_t>(partInfo.StartingOffset.QuadPart);
                    partition.lengthBytes = static_cast<int64_t>(partInfo.PartitionLength.QuadPart);
                    partition.volumeId = 0;  // Will be set later
                    
                    std::cout << "Partition " << i << ": Start=" << partition.startOffset 
                              << ", Length=" << partition.lengthBytes << std::endl;
                    
                    // Get partition type information based on partition style
                    if (pLayoutInfo->PartitionStyle == PARTITION_STYLE_MBR) {
                        partition.partitionType = "MBR";

                        // Store MBR type as integer
                        BYTE mbrTypeCode = partInfo.Mbr.PartitionType;
                        partition.mbrType = static_cast<int>(mbrTypeCode);

                        // COMP-001: Format MBR type with decoded name for console output
                        std::stringstream ss;
                        ss << "0x" << std::hex << std::setw(2) << std::setfill('0')
                           << static_cast<int>(mbrTypeCode);
                        const char* typeName = GetMbrPartitionTypeName(mbrTypeCode);

                        std::cout << "  MBR Type: " << ss.str() << " (" << typeName << ")" << std::endl;
                        
                    } else if (pLayoutInfo->PartitionStyle == PARTITION_STYLE_GPT) {
                        partition.partitionType = "GPT";
                        
                        // Convert GUID to string
                        GUID guid = partInfo.Gpt.PartitionType;
                        char guidStr[64];
                        sprintf_s(guidStr, 
                                 "{%08lX-%04hX-%04hX-%02hhX%02hhX-%02hhX%02hhX%02hhX%02hhX%02hhX%02hhX}",
                                 guid.Data1, guid.Data2, guid.Data3,
                                 guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3],
                                 guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
                        
                        partition.gptGuid = guidStr;
                        partition.mbrType = 0;  // Not applicable for GPT
                        
                        std::cout << "  GPT GUID: " << partition.gptGuid << std::endl;
                        
                    } else {
                        std::cout << "  Unknown partition style: " << pLayoutInfo->PartitionStyle << std::endl;
                        partition.partitionType = "Unknown";
                        partition.mbrType = 0;
                        partition.gptGuid = "";
                    }
                    
                    partitions.push_back(partition);
                }
            } else {
                DWORD error = GetLastError();
                std::cerr << "Failed to get disk layout with larger buffer. Error: " << error << std::endl;
            }
        } else {
            std::cerr << "Failed to get disk layout. Error: " << error << std::endl;
        }
    } else {
        // Unlikely to get here as the initial buffer is usually too small
        std::cout << "Got disk layout on first try, partition count: " << layoutInfo.PartitionCount << std::endl;
        
        // Process partitions (similar code as above)
        for (DWORD i = 0; i < layoutInfo.PartitionCount; i++) {
            PARTITION_INFORMATION_EX& partInfo = layoutInfo.PartitionEntry[i];
            
            // Skip empty partitions
            if (partInfo.PartitionLength.QuadPart == 0) {
                continue;
            }
            
            PartitionInfo partition;
            partition.diskId = diskId;
            partition.partitionIndex = static_cast<int>(i);
            partition.startOffset = static_cast<int64_t>(partInfo.StartingOffset.QuadPart);
            partition.lengthBytes = static_cast<int64_t>(partInfo.PartitionLength.QuadPart);
            partition.volumeId = 0;  // Will be set later
            
            // Get partition type information based on partition style
            if (layoutInfo.PartitionStyle == PARTITION_STYLE_MBR) {
                partition.partitionType = "MBR";
                partition.mbrType = static_cast<int>(partInfo.Mbr.PartitionType);
                partition.gptGuid = "";
            } else if (layoutInfo.PartitionStyle == PARTITION_STYLE_GPT) {
                partition.partitionType = "GPT";
                
                // Convert GUID to string
                GUID guid = partInfo.Gpt.PartitionType;
                char guidStr[64];
                sprintf_s(guidStr, 
                         "{%08lX-%04hX-%04hX-%02hhX%02hhX-%02hhX%02hhX%02hhX%02hhX%02hhX%02hhX}",
                         guid.Data1, guid.Data2, guid.Data3,
                         guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3],
                         guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
                
                partition.gptGuid = guidStr;
                partition.mbrType = 0;  // Not applicable for GPT
            } else {
                partition.partitionType = "Unknown";
                partition.mbrType = 0;
                partition.gptGuid = "";
            }
            
            partitions.push_back(partition);
        }
    }
    
    return partitions;
}

// Removed the stray if/else block that was at file scope





