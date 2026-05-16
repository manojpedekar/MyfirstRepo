#include "../collectors/diskinfo.h"
#include "../utils/constants.h"
#include "../utils/raii_wrappers.h"
#include "../utils/stringutils.h"
#include <winioctl.h>
#include <ntddscsi.h>
#include <ntddstor.h>
#include <iostream>
#include <windows.h>
#include <vector>
#include <cstdint>
#include <memory>
#include <string>
#include <algorithm>

#pragma comment(lib, "setupapi.lib")

namespace DiskInfo {

using Common::DeviceHandle;

// Define DISK_ATTRIBUTE constants if not defined
#ifndef DISK_ATTRIBUTE_OFFLINE
#define DISK_ATTRIBUTE_OFFLINE 0x0000000000000001ULL
#endif

#ifndef DISK_ATTRIBUTE_READ_ONLY
#define DISK_ATTRIBUTE_READ_ONLY 0x0000000000000002ULL
#endif

// Define IOCTL code if not defined
#ifndef IOCTL_DISK_GET_DISK_ATTRIBUTES
#define IOCTL_DISK_GET_DISK_ATTRIBUTES CTL_CODE(IOCTL_DISK_BASE, 0x003c, METHOD_BUFFERED, FILE_ANY_ACCESS)
#endif

// Define the DISK_ATTRIBUTES structure if not defined
#ifndef _DISK_ATTRIBUTES_DEFINED
#define _DISK_ATTRIBUTES_DEFINED
typedef struct _GET_DISK_ATTRIBUTES {
    DWORD Version;
    DWORD64 Attributes;
} GET_DISK_ATTRIBUTES, *PGET_DISK_ATTRIBUTES;
#endif

// Helper function to get disk model
std::wstring GetDiskModel(HANDLE hDevice) {
    STORAGE_PROPERTY_QUERY query = {};
    query.PropertyId = StorageDeviceProperty;
    query.QueryType = PropertyStandardQuery;
    
    // Query only the header to learn required size
    STORAGE_DESCRIPTOR_HEADER header{};
    DWORD bytesReturned = 0;
    if (!DeviceIoControl(
            hDevice,
            IOCTL_STORAGE_QUERY_PROPERTY,
            &query, sizeof(query),
            &header, sizeof(header),
            &bytesReturned, nullptr)) {
        return L"Unknown";
    }

    if (header.Size == 0) {
        return L"Unknown";
    }

    std::vector<BYTE> buffer(header.Size);
    auto* deviceDesc = reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(buffer.data());
    if (!DeviceIoControl(
            hDevice,
            IOCTL_STORAGE_QUERY_PROPERTY,
            &query, sizeof(query),
            buffer.data(), static_cast<DWORD>(buffer.size()),
            &bytesReturned, nullptr)) {
        return L"Unknown";
    }

    if (deviceDesc->ProductIdOffset == 0 ||
        deviceDesc->ProductIdOffset == 0xFFFFFFFF) {
        return L"Unknown";
    }

    const char* modelStr = reinterpret_cast<const char*>(buffer.data() + deviceDesc->ProductIdOffset);
    int modelLen = static_cast<int>(strlen(modelStr));
    std::wstring model(modelLen, L'\0');
    // FIX NEW-011: Check return value from MultiByteToWideChar
    int converted = MultiByteToWideChar(
        CP_ACP, 0, modelStr, modelLen, &model[0], modelLen);
    if (converted <= 0) {
        // Conversion failed - return empty string
        return L"";
    }
    model.resize(converted);
    
    // Trim whitespace
    model.erase(0, model.find_first_not_of(L" \t\r\n"));
    model.erase(model.find_last_not_of(L" \t\r\n") + 1);
    
    return model;
}

// Helper function to get disk interface type
InterfaceType GetDiskInterfaceType(const std::wstring& deviceId) {
    HANDLE hDevice = CreateFileW(
        deviceId.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );

    if (hDevice == INVALID_HANDLE_VALUE) {
        return InterfaceType::Unknown;
    }

    DeviceHandle deviceHandle(hDevice);
    
    STORAGE_PROPERTY_QUERY query = {};
    query.PropertyId = StorageDeviceProperty;
    query.QueryType = PropertyStandardQuery;

    STORAGE_DEVICE_DESCRIPTOR deviceDesc = {};
    DWORD bytesReturned = 0;

    if (!DeviceIoControl(
        hDevice,
        IOCTL_STORAGE_QUERY_PROPERTY,
        &query,
        sizeof(query),
        &deviceDesc,
        sizeof(deviceDesc),
        &bytesReturned,
        nullptr
    )) {
        return InterfaceType::Unknown;
    }

    switch (deviceDesc.BusType) {
        case BusTypeAta:
            return InterfaceType::IDE;   // Classic P-ATA
        #ifdef BusTypeSata
        case BusTypeSata:
            return InterfaceType::SATA;
        #endif
        case BusTypeUsb:
            return InterfaceType::USB;
        case BusTypeNvme:
            return InterfaceType::NVMe;
        case BusTypeScsi:
            return InterfaceType::SCSI;
        case BusTypeAtapi:
            return InterfaceType::IDE;
        case BusTypeSas:
            return InterfaceType::SAS;
        case BusTypeiScsi:
            return InterfaceType::iSCSI;
        case BusTypeRAID:
            return InterfaceType::RAID;
        default:
            return InterfaceType::Unknown;
    }
}

// GetDiskSize - ensure there's only one version
uint64_t GetDiskSize(HANDLE hDevice) {
    GET_LENGTH_INFORMATION lengthInfo = {};
    DWORD bytesReturned = 0;

    if (!DeviceIoControl(
        hDevice,
        IOCTL_DISK_GET_LENGTH_INFO,
        nullptr,
        0,
        &lengthInfo,
        sizeof(lengthInfo),
        &bytesReturned,
        nullptr
    )) {
        return 0;
    }

    return lengthInfo.Length.QuadPart;
}

// GetDiskPartitionStyle - ensure there's only one version
PartitionStyle GetDiskPartitionStyle(HANDLE hDevice) noexcept {
    DWORD bytesReturned = 0;

    // First try to get partition info using IOCTL_DISK_GET_PARTITION_INFO_EX
    PARTITION_INFORMATION_EX partInfo = {};
    if (DeviceIoControl(
            hDevice,
            IOCTL_DISK_GET_PARTITION_INFO_EX,
            nullptr,
            0,
            &partInfo,
            sizeof(partInfo),
            &bytesReturned,
            nullptr))
    {
        switch (partInfo.PartitionStyle)
        {
            case PARTITION_STYLE_MBR:
                return PartitionStyle::MBR;
            case PARTITION_STYLE_GPT:
                return PartitionStyle::GPT;
            default:
                break;  // Try next method if unknown
        }
    }

    // If first method failed or returned unknown, try IOCTL_DISK_GET_DRIVE_LAYOUT_EX
    DRIVE_LAYOUT_INFORMATION_EX layoutInfo = {};
    if (DeviceIoControl(
            hDevice,
            IOCTL_DISK_GET_DRIVE_LAYOUT_EX,
            nullptr,
            0,
            &layoutInfo,
            sizeof(layoutInfo),
            &bytesReturned,
            nullptr))
    {
        switch (layoutInfo.PartitionStyle)
        {
            case PARTITION_STYLE_MBR:
                return PartitionStyle::MBR;
            case PARTITION_STYLE_GPT:
                return PartitionStyle::GPT;
            default:
                break;
        }
    }

    return PartitionStyle::Unknown;
}

// IsBootOrSystemDisk - ensure there's only one version
std::pair<bool, bool> IsBootOrSystemDisk(int diskId) {
    wchar_t bootDrive[MAX_PATH] = {0};
    wchar_t systemDrive[MAX_PATH] = {0};
    
    if (!GetEnvironmentVariableW(L"SystemDrive", systemDrive, MAX_PATH)) {
        return {false, false};
    }
    
    // Get boot drive from system drive (usually the same)
    wcscpy_s(bootDrive, systemDrive);
    
    // Convert drive letter to physical drive number
    wchar_t drivePath[] = L"\\\\.\\X:";
    drivePath[4] = bootDrive[0];
    
    HANDLE hDrive = CreateFileW(
        drivePath,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        0,
        nullptr
    );
    
    if (hDrive == INVALID_HANDLE_VALUE) {
        return {false, false};
    }
    
    DeviceHandle driveHandle(hDrive);
    
    // First call to get required buffer size
    DWORD bytesReturned = 0;
    VOLUME_DISK_EXTENTS initialExtents = {};
    
    if (!DeviceIoControl(
        hDrive,
        IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
        nullptr,
        0,
        &initialExtents,
        sizeof(initialExtents),
        &bytesReturned,
        nullptr
    ) && GetLastError() != ERROR_MORE_DATA) {
        return {false, false};
    }

    // FIX NEW-012: Validate bytesReturned before allocating buffer
    if (bytesReturned == 0 || bytesReturned < sizeof(VOLUME_DISK_EXTENTS)) {
        return {false, false};
    }

    // Allocate buffer of required size
    std::vector<BYTE> buffer(bytesReturned);
    VOLUME_DISK_EXTENTS* diskExtents = reinterpret_cast<VOLUME_DISK_EXTENTS*>(buffer.data());
    
    // Get the actual disk extents
    if (!DeviceIoControl(
        hDrive,
        IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS,
        nullptr,
        0,
        diskExtents,
        static_cast<DWORD>(buffer.size()),
        &bytesReturned,
        nullptr
    )) {
        return {false, false};
    }
    
    bool isBoot = false;
    bool isSystem = false;
    
    // Check all extents for the target disk
    for (DWORD i = 0; i < diskExtents->NumberOfDiskExtents; i++) {
        if (diskExtents->Extents[i].DiskNumber == static_cast<DWORD>(diskId)) {
            isBoot = true;
            isSystem = true;
            break;
        }
    }
    
    return {isBoot, isSystem};
}

// Checks if a disk is read-only
bool IsDiskReadOnly(HANDLE hDevice) {
    DWORD bytesReturned = 0;
    
    if (!DeviceIoControl(
        hDevice,
        IOCTL_DISK_IS_WRITABLE,
        nullptr,
        0,
        nullptr,
        0,
        &bytesReturned,
        nullptr
    )) {
        // If the call fails with ERROR_WRITE_PROTECT, the disk is read-only
        return (GetLastError() == ERROR_WRITE_PROTECT);
    }
    
    // If the call succeeds, the disk is writable
    return false;
}

// Gets the operational status of a disk
DiskStatus GetDiskStatus(HANDLE hDevice) {
    // Check if the disk is accessible
    DWORD bytesReturned = 0;
    STORAGE_PROPERTY_QUERY query = {};
    query.PropertyId = StorageDeviceProperty;
    query.QueryType = PropertyStandardQuery;
    
    STORAGE_DESCRIPTOR_HEADER header = {};
    if (!DeviceIoControl(
        hDevice,
        IOCTL_STORAGE_QUERY_PROPERTY,
        &query,
        sizeof(query),
        &header,
        sizeof(header),
        &bytesReturned,
        nullptr
    )) {
        DWORD error = GetLastError();
        if (error == ERROR_NOT_READY) {
            return DiskStatus::NoMedia;
        } else if (error == ERROR_DEVICE_NOT_CONNECTED) {
            return DiskStatus::Offline;
        } else {
            return DiskStatus::Failed;
        }
    }
    
    // Additional check for disk status using IOCTL_DISK_GET_DISK_ATTRIBUTES
    // Use our own structure to avoid dependency on specific Windows SDK versions
    struct DISK_ATTRS {
        DWORD Version;
        DWORD64 Attributes;
    };
    
    DISK_ATTRS diskAttrs = {}; 
    diskAttrs.Version = sizeof(DISK_ATTRS);
    
    if (DeviceIoControl(
        hDevice,
        IOCTL_DISK_GET_DISK_ATTRIBUTES,
        nullptr,
        0,
        &diskAttrs,
        sizeof(diskAttrs),
        &bytesReturned,
        nullptr
    )) {
        if (diskAttrs.Attributes & DISK_ATTRIBUTE_OFFLINE) {
            return DiskStatus::Offline;
        } else if (diskAttrs.Attributes & DISK_ATTRIBUTE_READ_ONLY) {
            // Disk is online but read-only
            return DiskStatus::Online;
        }
    }
    
    return DiskStatus::Online;
}

// Convert interface type to string
std::wstring InterfaceTypeToString(InterfaceType type) {
    switch (type) {
        case InterfaceType::SATA:   return L"SATA";
        case InterfaceType::USB:    return L"USB";
        case InterfaceType::NVMe:   return L"NVMe";
        case InterfaceType::SCSI:   return L"SCSI";
        case InterfaceType::IDE:    return L"IDE";
        case InterfaceType::SAS:    return L"SAS";
        case InterfaceType::iSCSI:  return L"iSCSI";
        case InterfaceType::RAID:   return L"RAID";
        default:                    return L"Unknown";
    }
}

// Convert partition style to string
std::wstring PartitionStyleToString(PartitionStyle style) {
    switch (style) {
        case PartitionStyle::MBR:   return L"MBR";
        case PartitionStyle::GPT:   return L"GPT";
        default:                    return L"Unknown";
    }
}

// Convert disk status to string
std::wstring DiskStatusToString(DiskStatus status) {
    switch (status) {
        case DiskStatus::Online:    return L"Online";
        case DiskStatus::Offline:   return L"Offline";
        case DiskStatus::Failed:    return L"Failed";
        case DiskStatus::NoMedia:   return L"No Media";
        default:                    return L"Unknown";
    }
}

// Collect disk information
std::vector<DiskInfo> CollectDiskInfo() {
    std::vector<DiskInfo> disks;

    // Try to open each physical drive
    for (int i = 0; i < MAX_PHYSICAL_DRIVES; i++) {
        std::wstring devicePath = L"\\\\.\\PhysicalDrive" + std::to_wstring(i);
        
        HANDLE hDevice = CreateFileW(
            devicePath.c_str(),
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_EXISTING,
            FILE_FLAG_NO_BUFFERING,
            nullptr
        );
        
        if (hDevice == INVALID_HANDLE_VALUE) {
            continue;  // Skip if we can't open this drive
        }
        
        DeviceHandle deviceHandle(hDevice);
        
        // Get device number to confirm disk ID
        STORAGE_DEVICE_NUMBER deviceNumber = {};
        DWORD bytesReturned = 0;
        
        if (!DeviceIoControl(
            hDevice,
            IOCTL_STORAGE_GET_DEVICE_NUMBER,
            nullptr,
            0,
            &deviceNumber,
            sizeof(deviceNumber),
            &bytesReturned,
            nullptr
        )) {
            continue;  // Skip if we can't get device number
        }
        
        // Create disk info structure
        DiskInfo disk = {};
        disk.diskId = static_cast<int>(deviceNumber.DeviceNumber);
        disk.deviceId = devicePath;
        
        // Get disk model
        disk.model = GetDiskModel(hDevice);
        
        // Get interface type
        disk.interfaceType = GetDiskInterfaceType(disk.deviceId);
        
        // Get disk size
        disk.size = GetDiskSize(hDevice);
        
        // Get partition style
        disk.partitionStyle = GetDiskPartitionStyle(hDevice);
        
        // Check if disk is read-only
        disk.isReadOnly = IsDiskReadOnly(hDevice);
        
        // Check if this is the boot/system disk
        auto [isBoot, isSystem] = IsBootOrSystemDisk(disk.diskId);
        disk.isBoot = isBoot;
        disk.isSystem = isSystem;
        
        // Get disk status
        disk.status = GetDiskStatus(hDevice);
        
        disks.push_back(disk);
    }
    
    return disks;
}

} // namespace DiskInfo
