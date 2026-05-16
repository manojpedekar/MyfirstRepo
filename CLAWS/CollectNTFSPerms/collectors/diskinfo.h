#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <windows.h>
#include <setupapi.h>
#include <winioctl.h>
#include <devguid.h>
#include <cfgmgr32.h>
#include <stdexcept>

namespace DiskInfo {

/**
 * @brief Represents the interface type of a disk
 */
enum class InterfaceType {
    Unknown,
    SATA,
    USB,
    NVMe,
    SCSI,
    IDE,
    SAS,
    iSCSI,
    RAID
};

/**
 * @brief Represents the partition style of a disk
 */
enum class PartitionStyle {
    Unknown,
    MBR,
    GPT
};

/**
 * @brief Represents the operational status of a disk
 */
enum class DiskStatus {
    Unknown,
    Online,
    Offline,
    Failed,
    NoMedia
};

/**
 * @brief Structure containing information about a physical disk
 */
struct DiskInfo {
    int diskId               = -1;          // Physical drive number
    std::wstring deviceId;          // Device path (e.g., \\.\PHYSICALDRIVE0)
    std::wstring model;             // Disk model
    InterfaceType interfaceType = InterfaceType::Unknown;
    uint64_t      size          = 0;
    PartitionStyle partitionStyle = PartitionStyle::Unknown;
    bool isBoot      = false;
    bool isSystem    = false;
    bool isReadOnly  = false;
    DiskStatus status = DiskStatus::Unknown;
};

/**
 * @brief Exception class for disk information collection errors
 */
class DiskInfoException : public std::runtime_error {
public:
    explicit DiskInfoException(const std::string& message, DWORD errorCode = 0)
        : std::runtime_error(message), errorCode_(errorCode) {}
    
    DWORD getErrorCode() const { return errorCode_; }
    
private:
    DWORD errorCode_;
};

/**
 * @brief Collects information about all physical disks in the system
 * 
 * @return std::vector<DiskInfo> Vector containing information about each disk
 * @throw DiskInfoException if an error occurs during collection
 */
std::vector<DiskInfo> CollectDiskInfo();

/**
 * @brief Converts a disk interface type to a string
 * 
 * @param type The interface type to convert
 * @return std::wstring String representation of the interface type
 */
std::wstring InterfaceTypeToString(InterfaceType type);

/**
 * @brief Converts a partition style to a string
 * 
 * @param style The partition style to convert
 * @return std::wstring String representation of the partition style
 */
std::wstring PartitionStyleToString(PartitionStyle style);

/**
 * @brief Converts a disk status to a string
 * 
 * @param status The disk status to convert
 * @return std::wstring String representation of the disk status
 */
std::wstring DiskStatusToString(DiskStatus status);

/**
 * @brief Checks if a disk is read-only
 * 
 * @param hDevice Handle to the disk device
 * @return bool True if the disk is read-only, false otherwise
 */
bool IsDiskReadOnly(HANDLE hDevice);

/**
 * @brief Gets the operational status of a disk
 * 
 * @param hDevice Handle to the disk device
 * @return DiskStatus The operational status of the disk
 */
DiskStatus GetDiskStatus(HANDLE hDevice);

/**
 * @brief Gets the partition style of a disk
 * 
 * @param hDevice Handle to the disk device
 * @return PartitionStyle The partition style of the disk
 */
PartitionStyle GetDiskPartitionStyle(HANDLE hDevice) noexcept;

/**
 * @brief Gets the interface type of a disk
 * 
 * @param deviceId The device ID of the disk
 * @return InterfaceType The interface type of the disk
 */
InterfaceType GetDiskInterfaceType(const std::wstring& deviceId);

/**
 * @brief Gets the size of a disk
 * 
 * @param hDevice Handle to the disk device
 * @return uint64_t The size of the disk in bytes
 */
uint64_t GetDiskSize(HANDLE hDevice);

/**
 * @brief Gets the model of a disk
 * 
 * @param hDevice Handle to the disk device
 * @return std::wstring The model of the disk
 */
std::wstring GetDiskModel(HANDLE hDevice);

/**
 * @brief Checks if a disk is the boot or system disk
 * 
 * @param diskId The ID of the disk
 * @return std::pair<bool, bool> First element is true if the disk is the boot disk,
 *                              second element is true if the disk is the system disk
 */
std::pair<bool, bool> IsBootOrSystemDisk(int diskId);

} // namespace DiskInfo
