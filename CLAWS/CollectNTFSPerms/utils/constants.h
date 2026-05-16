#ifndef CONSTANTS_H
#define CONSTANTS_H

// Disk collection constants
constexpr int MAX_PHYSICAL_DRIVES = 64;  // Maximum number of physical drives to scan

// Database batch sizes
constexpr int ACL_BATCH_SIZE = 1000;      // Batch size for ACL inserts
constexpr int ACE_BATCH_SIZE = 1000;      // Batch size for ACE inserts
constexpr int SID_BATCH_SIZE = 1000;      // Batch size for SID inserts
constexpr int FOLDER_BATCH_SIZE = 1000;   // Batch size for folder inserts

// Threading constants
constexpr int QUEUE_TIMEOUT_MS = 100;     // Queue timeout in milliseconds

// Console output constants
constexpr int DEFAULT_CONSOLE_WIDTH = 80; // Default console width if detection fails
constexpr int CONSOLE_WIDTH_THRESHOLD_1 = 60;  // First threshold for optional output
constexpr int CONSOLE_WIDTH_THRESHOLD_2 = 75;  // Second threshold for optional output
constexpr int CONSOLE_WIDTH_THRESHOLD_3 = 90;  // Third threshold for optional output

// Progress update intervals
constexpr int PROGRESS_UPDATE_INTERVAL_MS = 1000;  // Update progress every 1 second

#endif // CONSTANTS_H
