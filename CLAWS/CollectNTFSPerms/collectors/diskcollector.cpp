#include "../collectors/diskcollector.h"
#include "../database/statement.h"
#include "../database/transaction.h"
#include "../utils/stringutils.h"
#include <memory>
#include <sstream>
#include <iostream>

namespace DiskCollector {

int CollectAndStoreDiskInfo(sqlite3* db, const std::string& inventoryId) {
    // Prepare the insert statement
    const char* sql = R"(
        INSERT INTO app__Disks (
            InventoryID, DiskID, DeviceID, Model, InterfaceType,
            Size, PartitionStyle, IsBoot, IsSystem, IsReadOnly, Status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    )";

    Statement stmt(db, sql);

    // Start transaction
    Transaction transaction(db);

    int diskCount = 0;

    try {
        // Collect disk information
        auto disks = DiskInfo::CollectDiskInfo();
        std::cout << "Found " << disks.size() << " disks" << std::endl;
        
        // Set the disk count
        diskCount = static_cast<int>(disks.size());
        
        // Insert each disk
        for (const auto& disk : disks) {
            std::cout << "\nProcessing disk " << disk.diskId << ": " << std::endl;
            std::cout << "  Model: " << WideToNarrow(disk.model) << std::endl;
            std::cout << "  Size: " << disk.size << " bytes" << std::endl;

            // Convert wide strings to UTF-8 for storage
            std::string deviceId = WideToNarrow(disk.deviceId);
            std::string model = WideToNarrow(disk.model);
            std::string interfaceType = WideToNarrow(DiskInfo::InterfaceTypeToString(disk.interfaceType));
            std::string partitionStyle = WideToNarrow(DiskInfo::PartitionStyleToString(disk.partitionStyle));
            std::string status = WideToNarrow(DiskInfo::DiskStatusToString(disk.status));

            // Bind parameters
            sqlite3_bind_text(stmt.get(), 1, inventoryId.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_int(stmt.get(), 2, static_cast<int>(disk.diskId));
            sqlite3_bind_text(stmt.get(), 3, deviceId.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_text(stmt.get(), 4, model.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_text(stmt.get(), 5, interfaceType.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_int64(stmt.get(), 6, static_cast<sqlite3_int64>(disk.size));
            sqlite3_bind_text(stmt.get(), 7, partitionStyle.c_str(), -1, SQLITE_STATIC);
            sqlite3_bind_int(stmt.get(), 8, disk.isBoot ? 1 : 0);
            sqlite3_bind_int(stmt.get(), 9, disk.isSystem ? 1 : 0);
            sqlite3_bind_int(stmt.get(), 10, disk.isReadOnly ? 1 : 0);
            sqlite3_bind_text(stmt.get(), 11, status.c_str(), -1, SQLITE_STATIC);

            // Execute the statement
            int rc = sqlite3_step(stmt.get());
            if (rc != SQLITE_DONE) {
                std::string error = sqlite3_errmsg(db);
                std::cout << "Failed to insert disk " << disk.diskId << ": " << error << std::endl;
                throw DiskCollectionException("Failed to insert disk: " + error);
            }
            std::cout << "  Successfully inserted disk " << disk.diskId << std::endl;

            // Reset the statement for the next iteration
            sqlite3_reset(stmt.get());
        }

        // Commit the transaction
        transaction.Commit();

        // Return the number of disks processed
        return diskCount;
    }
    catch (const std::exception& e) {
        std::cout << "Exception during disk collection: " << e.what() << std::endl;
        // Transaction will automatically roll back in its destructor
        throw DiskCollectionException(std::string("Failed to collect and store disk info: ") + e.what());
    }
}

} // namespace DiskCollector 
