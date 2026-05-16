#pragma once

#include <string>
#include "../../sqlite/sqlite3.h"

/**
 * Collects partition information from all physical disks and stores it in the database.
 * 
 * @param db Pointer to an open SQLite database connection
 * @param inventoryId The inventory ID (GUID string) to associate with the collected partitions
 * @param partitionCount Optional output parameter to return the number of partitions processed
 * @return true if at least one partition was successfully collected and stored, false otherwise
 */
bool CollectPartitions(sqlite3* db, const std::string& inventoryId, int* partitionCount = nullptr);
