#pragma once

#include <string>
#include "../../sqlite/sqlite3.h"
#include "../collectors/diskinfo.h"

namespace DiskCollector {

// Exception class for disk collection errors
class DiskCollectionException : public std::runtime_error {
public:
    explicit DiskCollectionException(const std::string& message) 
        : std::runtime_error(message) {}
};

// Function to collect disk information and insert into database
// Changed return type from void to int to return the number of disks processed
int CollectAndStoreDiskInfo(sqlite3* db, const std::string& inventoryId);

} // namespace DiskCollector 
