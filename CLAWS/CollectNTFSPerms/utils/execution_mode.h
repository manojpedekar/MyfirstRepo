#pragma once

#include <string>
#include <vector>

/**
 * @brief Execution mode for the application
 *
 * Determines the primary operation mode based on command-line arguments.
 */
enum class ExecutionMode {
    Normal,         // Standard single-folder scan with database
    AllFixedDisks,  // Scan all DRIVE_FIXED volumes
    TestAccess      // Access test only, no database operations
};

/**
 * @brief Parsed command-line arguments
 *
 * Contains all parsed arguments in a structured format for easy access
 * throughout the application.
 */
struct ParsedArguments {
    ExecutionMode mode = ExecutionMode::Normal;

    // Folder/path arguments
    std::wstring folderToScan;           // For Normal and TestAccess modes
    std::string databasePath;            // For Normal and AllFixedDisks modes

    // Optional flags
    bool explicitOnly = false;           // --ExplicitOnly flag
    bool debugMode = false;              // --Debug flag
    bool noZip = false;                  // --NoZip flag (skip database compression)
    std::string remoteComputer;          // --RemoteComputer value

    /**
     * @brief Validate the parsed arguments
     * @return true if arguments are valid for the selected mode
     */
    bool isValid() const {
        switch (mode) {
            case ExecutionMode::Normal:
                return !folderToScan.empty() && !databasePath.empty();
            case ExecutionMode::AllFixedDisks:
                return !databasePath.empty();
            case ExecutionMode::TestAccess:
                return !folderToScan.empty();
        }
        return false;
    }

    /**
     * @brief Get validation error message
     * @return Error message if invalid, empty string if valid
     */
    std::string validationError() const {
        switch (mode) {
            case ExecutionMode::Normal:
                if (folderToScan.empty()) return "Missing required argument: <FolderToScan>";
                if (databasePath.empty()) return "Missing required argument: <DatabaseFile>";
                break;

            case ExecutionMode::AllFixedDisks:
                if (databasePath.empty()) return "Missing required argument: <DatabaseFile>";
                if (!remoteComputer.empty()) {
                    return "--allfixeddisks cannot be used with --RemoteComputer "
                           "(cannot enumerate remote fixed disks)";
                }
                break;

            case ExecutionMode::TestAccess:
                if (folderToScan.empty()) return "Missing required argument: <FolderToScan>";
                if (!databasePath.empty()) {
                    return "--testaccess does not accept a database file argument";
                }
                if (explicitOnly) {
                    return "--testaccess cannot be used with --ExplicitOnly";
                }
                if (!remoteComputer.empty()) {
                    return "--testaccess cannot be used with --RemoteComputer";
                }
                break;
        }
        return "";  // Valid
    }

    /**
     * @brief Get string representation of execution mode
     * @return Mode name as string
     */
    const char* modeName() const {
        switch (mode) {
            case ExecutionMode::Normal: return "Normal";
            case ExecutionMode::AllFixedDisks: return "AllFixedDisks";
            case ExecutionMode::TestAccess: return "TestAccess";
        }
        return "Unknown";
    }
};
