#include <algorithm>
#include <cctype>
#include <string>
#include <iostream>
#include <fstream>
#include <windows.h>
#include <sddl.h>
#include <lm.h>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <ctime>
#include <rpc.h>
#include <atomic>
#include <cstdint>

#include "../utils/utils.h"

#pragma comment(lib, "Rpcrt4.lib")  // Ensure linking with required RPC lib

/**
 * FC-027 FIX: Meyers Singleton Pattern for Global Variables
 *
 * Replace static initialization with function-local statics to eliminate
 * static initialization order fiasco. Each function returns a reference to
 * a function-local static variable, which is initialized on first call.
 *
 * C++11 guarantees thread-safe initialization of function-local statics.
 */
namespace AppGlobals {
    // Meyers Singleton: Initialize on first access
    std::string& ComputerName() {
        static std::string instance = InitializeGlobalComputerName();
        return instance;
    }

    const std::string& DomainName() {
        static std::string instance = InitializeGlobalDomainName();
        return instance;
    }

    const std::string& InventoryID() {
        static std::string instance = GenerateGUID();
        return instance;
    }

    bool IsAdmin() {
        static bool instance = IsRunningAsAdmin();
        return instance;
    }

    const std::string& CurrentUser() {
        static std::string instance = GetCurrentUser();
        return instance;
    }

    // Helper to modify ComputerName (for remote computer override)
    void SetComputerName(const std::string& name) {
        ComputerName() = name;
    }

    // Simple globals (no complex initialization - safe as-is)
    std::atomic<int> PeakMemoryUsageMB{0};
    std::int32_t PeakQueueSize = 0;
    std::int32_t FoldersProcessed = 0;
    std::int32_t FoldersWithErrors = 0;
    std::int32_t MemoryUsageMB = 0;
    std::atomic<bool> DebugMode{false};
    std::wofstream* DebugFile = nullptr;
    std::mutex DebugFileMutex;  // Protects DebugFile from concurrent access

    // Open debug file for writing
    void OpenDebugFile(const std::string& filename) {
        std::lock_guard<std::mutex> lock(DebugFileMutex);
        // Close existing file if open
        if (DebugFile != nullptr) {
            if (DebugFile->is_open()) {
                DebugFile->close();
            }
            delete DebugFile;
            DebugFile = nullptr;
        }
        DebugFile = new std::wofstream(filename, std::ios::out | std::ios::trunc);
        // Note: File uses default system encoding (typically UTF-16 on Windows)
        // This is acceptable for debug output purposes
    }

    // Close debug file
    void CloseDebugFile() {
        std::lock_guard<std::mutex> lock(DebugFileMutex);
        if (DebugFile != nullptr) {
            if (DebugFile->is_open()) {
                DebugFile->close();
            }
            delete DebugFile;
            DebugFile = nullptr;
        }
    }

    // Write wide string to debug file - THREAD-SAFE
    void WriteDebug(const std::wstring& message) {
        if (DebugMode.load() && DebugFile != nullptr) {
            std::lock_guard<std::mutex> lock(DebugFileMutex);
            if (DebugFile->is_open()) {
                *DebugFile << message;
                DebugFile->flush();  // Ensure immediate write
            }
        }
    }

    // Write narrow string to debug file - THREAD-SAFE
    void WriteDebug(const std::string& message) {
        if (DebugMode.load() && DebugFile != nullptr) {
            std::lock_guard<std::mutex> lock(DebugFileMutex);
            if (DebugFile->is_open()) {
                // Convert narrow string to wide string
                std::wstring wideMsg(message.begin(), message.end());
                *DebugFile << wideMsg;
                DebugFile->flush();  // Ensure immediate write
            }
        }
    }
}

/**
 * @brief Converts a string to uppercase.
 *
 * @param str The input string to convert.
 * @return std::string The uppercase version of the input string.
 */
std::string to_upper(const std::string& str) {
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::toupper);
    return result;
}

/**
 * @brief Determines if the current process is running with administrative privileges.
 *
 * @return true if the process is running as an administrator, false otherwise.
 */
bool IsRunningAsAdmin() {
    BOOL isAdmin = FALSE;
    PSID adminGroup = nullptr;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;

    if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                 DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &adminGroup)) {
        // FIX FC-030: Check return value from CheckTokenMembership
        if (!CheckTokenMembership(nullptr, adminGroup, &isAdmin)) {
            // If check fails, assume not admin for safety
            isAdmin = FALSE;
        }
        FreeSid(adminGroup);
    }

    return isAdmin != FALSE;
}

/**
 * @brief Retrieves the current Windows user's name.
 *
 * @return The username as a UTF-8 encoded string, or "Unknown" if retrieval fails.
 */
std::string GetCurrentUser() {
    wchar_t username[256];
    DWORD size = static_cast<DWORD>(std::size(username));
    if (GetUserNameW(username, &size)) {
        return wstring_to_string(username);
    }
    return "Unknown";
}

/**
 * @brief Retrieves the local computer's name as a UTF-8 string.
 *
 * Uses the Windows API to obtain the computer name and converts it to UTF-8. Returns "Unknown" if retrieval fails.
 * 
 * @return The computer name in UTF-8 encoding, or "Unknown" on failure.
 */
std::string InitializeGlobalComputerName() {
    wchar_t buffer[256];
    DWORD size = static_cast<DWORD>(std::size(buffer));
    if (GetComputerNameW(buffer, &size)) {
        return wstring_to_string(buffer);
    } else {
        return "Unknown";
    }
}

/**
 * @brief Retrieves the local domain or workgroup name as a UTF-8 string.
 *
 * Uses Windows networking APIs to obtain the computer's domain or workgroup name. Returns "UnknownDomain" if retrieval fails.
 * @return UTF-8 encoded domain or workgroup name, or "UnknownDomain" on failure.
 */
std::string InitializeGlobalDomainName() {
    WKSTA_INFO_100* pWkstaInfo = nullptr;
    if (NetWkstaGetInfo(nullptr, 100, reinterpret_cast<LPBYTE*>(&pWkstaInfo)) == NERR_Success) {
        std::string result = wstring_to_string(pWkstaInfo->wki100_langroup);
        NetApiBufferFree(pWkstaInfo);
        return result;
    } else {
        return "UnknownDomain";
    }
}

/**
 * @brief Converts a UTF-16 wide string to a UTF-8 encoded std::string.
 *
 * Returns an empty string if the input is empty.
 *
 * @param wstr The wide string to convert.
 * @return A UTF-8 encoded string representation of the input.
 */
std::string wstring_to_string(const std::wstring& wstr) {
    if (wstr.empty()) return {};
    int sizeNeeded = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), static_cast<int>(wstr.size()),
                                         nullptr, 0, nullptr, nullptr);
    if (sizeNeeded <= 0) return {};  // Error case

    std::string result(sizeNeeded, 0);
    // FIX FC-031: Check return value from second WideCharToMultiByte call
    int bytesWritten = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), static_cast<int>(wstr.size()),
                        result.data(), sizeNeeded, nullptr, nullptr);
    if (bytesWritten <= 0) {
        throw std::runtime_error("WideCharToMultiByte conversion failed: " + std::to_string(GetLastError()));
    }
    return result;
}

/**
 * @brief Returns the current UTC time formatted as an ISO 8601 string with millisecond precision.
 *
 * @return std::string Current time in the format YYYY-MM-DDTHH:MM:SS.mmm+00:00.
 */
std::string FormatTime() {
    return FormatTime(std::chrono::system_clock::now(), false);
}

/**
 * @brief Formats a time point as an ISO 8601 string in UTC with millisecond precision.
 *
 * @param tp The time point to format.
 * @return std::string The formatted UTC time string in ISO 8601 format with milliseconds and "+00:00" timezone offset.
 */
std::string FormatTime(const std::chrono::system_clock::time_point& tp) {
    return FormatTime(tp, false);
}

/**
 * @brief Formats a time point as an ISO 8601 string with millisecond precision and timezone offset.
 *
 * Converts the given time point to a string in the format `YYYY-MM-DDTHH:MM:SS.mmm±HH:MM`, where the offset reflects either UTC (`+00:00`) or the local timezone depending on the `useLocalTime` flag.
 *
 * @param tp The time point to format.
 * @param useLocalTime If true, formats as local time with the appropriate timezone offset; if false, formats as UTC with `+00:00`.
 * @return std::string The formatted ISO 8601 time string.
 */
std::string FormatTime(const std::chrono::system_clock::time_point& tp, bool useLocalTime) {
    // Convert to time_t for easier formatting
    auto time = std::chrono::system_clock::to_time_t(tp);
    
    // Get milliseconds
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        tp.time_since_epoch()) % 1000;

    // Format the time
    std::tm timeInfo;
    if (useLocalTime) {
        localtime_s(&timeInfo, &time);
    } else {
        gmtime_s(&timeInfo, &time);
    }

    std::ostringstream oss;
    oss << std::put_time(&timeInfo, "%Y-%m-%dT%H:%M:%S");
    oss << '.' << std::setfill('0') << std::setw(3) << ms.count();

    if (useLocalTime) {
        // FIX FC-032: Use GetTimeZoneInformation for correct timezone offset
        // Previous implementation failed on DST boundaries and month/year transitions
        TIME_ZONE_INFORMATION tzi;
        DWORD tzResult = GetTimeZoneInformation(&tzi);

        // Calculate bias in minutes (GetTimeZoneInformation returns bias as minutes west of UTC)
        // Bias is positive for zones west of UTC, negative for zones east of UTC
        LONG biasMinutes = tzi.Bias;

        // Add daylight savings bias if currently in daylight time
        if (tzResult == TIME_ZONE_ID_DAYLIGHT) {
            biasMinutes += tzi.DaylightBias;
        } else if (tzResult == TIME_ZONE_ID_STANDARD) {
            biasMinutes += tzi.StandardBias;
        }
        // For TIME_ZONE_ID_UNKNOWN, just use Bias

        // Convert to offset from UTC (negate because bias is west of UTC)
        int offsetMinutes = -biasMinutes;

        // Format offset as ±HH:MM
        oss << (offsetMinutes >= 0 ? "+" : "-");
        oss << std::setfill('0') << std::setw(2) << std::abs(offsetMinutes) / 60
            << ":" << std::setw(2) << std::abs(offsetMinutes) % 60;
    } else {
        // Use +00:00 for UTC instead of Z
        oss << "+00:00";
    }

    return oss.str();
}

/**
 * @brief Generates a new GUID as a string.
 *
 * @return A string representation of the generated GUID, or an empty string if generation fails.
 */
std::string GenerateGUID() {
    UUID uuid;
    if (UuidCreate(&uuid) != RPC_S_OK) {
        return {};
    }

    RPC_CSTR str = nullptr;
    if (UuidToStringA(&uuid, &str) != RPC_S_OK || str == nullptr) {
        return {};
    }

    std::string guid(reinterpret_cast<char*>(str));
    RpcStringFreeA(&str);
    return guid;
}

/**
 * @brief Gets the current memory usage of the process in megabytes.
 * 
 * @return double Memory usage in megabytes.
 */
double GetProcessMemoryUsageMB() {
    PROCESS_MEMORY_COUNTERS_EX pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS*)&pmc, sizeof(pmc))) {
        // Return working set size (physical memory used) in MB
        return static_cast<double>(pmc.WorkingSetSize) / (1024 * 1024);
    }
    return 0.0;
}

/**
 * @brief Updates the peak memory usage if current usage is higher.
 * 
 * This function should be called periodically throughout the application's
 * lifetime to track peak memory usage.
 */
void UpdatePeakMemoryUsage() {
    double currentUsage = GetProcessMemoryUsageMB();
    int currentUsageInt = static_cast<int>(currentUsage);
    
    // Update peak memory usage atomically if current usage is higher
    int currentPeak = AppGlobals::PeakMemoryUsageMB.load();
    while (currentUsageInt > currentPeak) {
        if (AppGlobals::PeakMemoryUsageMB.compare_exchange_weak(currentPeak, currentUsageInt)) {
            break;
        }
    }
}

// Format a number with locale-specific formatting
template<typename T>
std::string FormatNumberWithLocale(T number) {
    std::stringstream ss;
    ss.imbue(std::locale(""));
    ss << number;
    return ss.str();
}

// Explicit template instantiations for common types
template std::string FormatNumberWithLocale<int>(int);
template std::string FormatNumberWithLocale<int64_t>(int64_t);
template std::string FormatNumberWithLocale<double>(double);
template std::string FormatNumberWithLocale<size_t>(size_t);
template std::string FormatNumberWithLocale<unsigned __int64>(unsigned __int64);

// Console utility function implementations

/**
 * @brief Gets the current console width in characters
 * @return int The console width, or 80 if detection fails
 */
int GetConsoleWidth() {
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi)) {
        return csbi.srWindow.Right - csbi.srWindow.Left + 1;
    }
    return 80; // Default width
}

/**
 * @brief Clears the current console line and moves cursor to the beginning
 *
 * Uses Windows Console API for reliable line clearing without artifacts.
 */
void ClearConsoleLine() {
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);

    if (GetConsoleScreenBufferInfo(hConsole, &csbi)) {
        DWORD written;
        COORD coord = csbi.dwCursorPosition;
        coord.X = 0;  // Move to beginning of line

        // Fill the line with spaces
        FillConsoleOutputCharacterA(hConsole, ' ', csbi.dwSize.X,
                                    coord, &written);

        // Move cursor to beginning of line
        SetConsoleCursorPosition(hConsole, coord);
    }
}

/**
 * @brief Prints a progress message that completely replaces the current line
 * @param message The message to display
 *
 * Truncates the message to fit within the console width to prevent wrapping
 * and visual artifacts when the message is updated.
 */
void PrintProgressLine(const std::string& message) {
    // Move cursor to beginning and clear line
    std::cout << '\r';
    ClearConsoleLine();

    // Get console width and truncate message if needed
    int consoleWidth = GetConsoleWidth();
    std::string displayMessage = message;

    // Reserve 3 characters for "..." if we need to truncate
    if (static_cast<int>(displayMessage.length()) > consoleWidth) {
        displayMessage = displayMessage.substr(0, consoleWidth - 3) + "...";
    }

    // Print the truncated message without newline
    std::cout << displayMessage << std::flush;
}
