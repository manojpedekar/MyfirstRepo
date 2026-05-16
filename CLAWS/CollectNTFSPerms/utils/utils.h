#ifndef UTILS_H
#define UTILS_H

#include <string>
#include <chrono>
#include <fstream>  // For debug file output
#include <mutex>    // For debug file synchronization
#include <windows.h>
#include <psapi.h>
#include <cstdint>   // For std::int32_t
#include <rpc.h>    // For UUID
#include <rpcndr.h>  // For UUID
#include <cstddef>  // For size_t
#include <atomic>   // For std::atomic
#include <process.h>

#pragma comment(lib, "Rpcrt4.lib")  // Ensure linking with required RPC lib

// Convert a string to uppercase (ASCII only)
std::string to_upper(const std::string& str);

// Converts std::wstring to UTF-8 std::string
std::string wstring_to_string(const std::wstring& wstr);

// Checks if the current process is running with admin privileges
bool IsRunningAsAdmin();

// Gets the current user name
std::string GetCurrentUser();

// Initializes and returns the local computer name (UTF-8)
std::string InitializeGlobalComputerName();

// Initializes and returns the local domain or workgroup name (UTF-8)
std::string InitializeGlobalDomainName();

/**
 * @brief Provides globally accessible application state variables.
 *
 * Uses Meyers Singleton pattern (function-local statics) to eliminate
 * static initialization order fiasco (FC-027).
 *
 * Thread-safe initialization guaranteed by C++11 standard.
 */

namespace AppGlobals {
    // Accessor functions returning references to function-local statics
    // These guarantee safe initialization order and are thread-safe
    std::string& ComputerName();              // Modifiable for remote computer override
    const std::string& DomainName();
    const std::string& InventoryID();
    bool IsAdmin();
    const std::string& CurrentUser();

    // Helper to set computer name (for remote scans)
    void SetComputerName(const std::string& name);

    // Simple global variables (safe - no complex initialization)
    extern std::atomic<int> PeakMemoryUsageMB;  // Track peak memory usage
    extern std::int32_t PeakQueueSize;
    extern std::int32_t FoldersProcessed;
    extern std::int32_t FoldersWithErrors;
    extern std::int32_t MemoryUsageMB;

    // Debug flag - controlled by --debug command-line argument
    extern std::atomic<bool> DebugMode;

    // Debug file stream - opened when --Debug is specified
    // Writing to file instead of console improves performance
    extern std::wofstream* DebugFile;
    extern std::mutex DebugFileMutex;  // Protects DebugFile from concurrent access

    // Helper functions for debug output
    void OpenDebugFile(const std::string& filename);
    void CloseDebugFile();
    void WriteDebug(const std::wstring& message);
    void WriteDebug(const std::string& message);
}

// Format current system time in ISO 8601 format (UTC)
std::string FormatTime();

// Format a specific time point in ISO 8601 format (UTC)
std::string FormatTime(const std::chrono::system_clock::time_point& time);

// Format a specific time point in ISO 8601 format (UTC or local)
std::string FormatTime(const std::chrono::system_clock::time_point& time, bool useLocalTime);

// Generate a new GUID as a string
std::string GenerateGUID();

double GetProcessMemoryUsageMB();
void UpdatePeakMemoryUsage();

// Format a number with locale-specific formatting
template<typename T>
std::string FormatNumberWithLocale(T number);

// Console utility functions
/**
 * @brief Gets the current console width in characters
 * @return int The console width, or 80 if detection fails
 */
int GetConsoleWidth();

/**
 * @brief Clears the current console line and moves cursor to the beginning
 *
 * Uses Windows Console API for reliable line clearing without artifacts.
 */
void ClearConsoleLine();

/**
 * @brief Prints a progress message that completely replaces the current line
 * @param message The message to display
 */
void PrintProgressLine(const std::string& message);

#endif // UTILS_H
