#include <iostream>
#include <iomanip>   // for std::setprecision
#include <thread>
#include <cctype>  // for isalpha in IsUncPath
#include <fstream>  // for ZIP file creation

// Windows headers
#include <windows.h>
#include <processthreadsapi.h>
#include <errhandlingapi.h>
#include <shlobj.h>      // Shell API for ZIP operations
#include <shlwapi.h>     // Path helper functions
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")

// Project headers
#include "version.h"
#include "utils/utils.h"
#include "database/database.h"
#include "core/folderscanner.h"
#include "utils/folderutils.h"
#include "utils/security_utils.h"
#include "utils/SnapshotExclusions.h"
#include "collectors/diskcollector.h"
#include "core/AclProcessor.h"
#include "collectors/volumes.h"
#include "collectors/SMBShare.h"
#include "collectors/partitions.h"
#include "collectors/fixed_disk_enumerator.h"
#include "core/access_test_scanner.h"
#include "utils/execution_mode.h"

bool g_explicitOnly = false;
std::atomic<bool> shouldStop{false};  // Global flag for stopping threads

/**
 * @brief Check if sqlite3.dll is available before using SQLite APIs
 *
 * Uses LoadLibraryEx with LOAD_LIBRARY_AS_DATAFILE to check if sqlite3.dll
 * can be found without actually loading it for execution.
 *
 * @return true if sqlite3.dll is found, false otherwise
 */
bool CheckSQLiteDllAvailable() {
    HMODULE hModule = LoadLibraryExA("sqlite3.dll", NULL, LOAD_LIBRARY_AS_DATAFILE);
    if (hModule != NULL) {
        FreeLibrary(hModule);
        return true;
    }
    std::cerr << "Application failed to load. Please ensure that the sqlite3.dll is available in the application path\n";
    return false;
}

/**
 * @brief RAII guard to ensure shouldStop is set to true on scope exit
 *
 * This ensures the memory monitor thread stops cleanly even if main()
 * exits early due to errors. Prevents resource leak and use-after-free.
 */
class ShouldStopGuard {
public:
    ~ShouldStopGuard() {
        shouldStop.store(true);
        // Give the memory monitor thread time to see the flag and exit
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
};

/**
 * @brief Gets the absolute path for a given file path using Win32 APIs
 *
 * @param path The input path (can be relative or absolute)
 * @return std::string The absolute path, or the original path if conversion fails
 */
std::string GetAbsolutePath(const std::string& path) {
    char absolutePath[MAX_PATH];
    DWORD result = GetFullPathNameA(path.c_str(), MAX_PATH, absolutePath, nullptr);
    if (result == 0 || result > MAX_PATH) {
        return path;  // Return original path if conversion fails
    }
    return std::string(absolutePath);
}

/**
 * @brief Create an empty ZIP file with the proper ZIP header
 *
 * A valid empty ZIP file consists of the End of Central Directory record.
 * This is required before using the Shell API to add files.
 *
 * @param zipPath Path for the new ZIP file
 * @return true if file was created successfully
 */
bool CreateEmptyZipFile(const std::string& zipPath) {
    // ZIP End of Central Directory signature and minimal header
    // This creates a valid empty ZIP file that Windows Shell API can work with
    static const unsigned char zipHeader[] = {
        0x50, 0x4B, 0x05, 0x06,  // End of central directory signature
        0x00, 0x00,              // Number of this disk
        0x00, 0x00,              // Disk where central directory starts
        0x00, 0x00,              // Number of central directory records on this disk
        0x00, 0x00,              // Total number of central directory records
        0x00, 0x00, 0x00, 0x00,  // Size of central directory (bytes)
        0x00, 0x00, 0x00, 0x00,  // Offset of start of central directory
        0x00, 0x00               // Comment length
    };

    std::ofstream zipFile(zipPath, std::ios::binary | std::ios::trunc);
    if (!zipFile.is_open()) {
        return false;
    }

    zipFile.write(reinterpret_cast<const char*>(zipHeader), sizeof(zipHeader));
    zipFile.close();

    return zipFile.good();
}

/**
 * @brief Compress the database file to a ZIP archive using Windows Shell API
 *
 * Uses the built-in Windows Shell API (available since Windows XP) to create
 * a ZIP file. This approach works on all Windows systems without requiring
 * PowerShell or any external dependencies.
 *
 * @param dbPath Path to the database file
 * @param noZip If true, skip compression and cleanup
 * @return true if successful (or skipped), false on error
 */
bool CompressAndCleanupDatabase(const std::string& dbPath, bool noZip) {
    if (noZip) {
        std::cout << "\n--------------------------------------------------\n";
        std::cout << "Database compression skipped (--NoZip specified)\n";
        std::cout << "Database file: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return true;
    }

    std::cout << "\n--------------------------------------------------\n";
    std::cout << "Compressing database file...\n";

    // Generate ZIP filename by replacing .db extension with .zip
    std::string zipPath = dbPath;
    size_t dotPos = zipPath.rfind('.');
    if (dotPos != std::string::npos) {
        zipPath = zipPath.substr(0, dotPos) + ".zip";
    } else {
        zipPath = dbPath + ".zip";
    }

    std::cout << "Source: " << dbPath << "\n";
    std::cout << "Target: " << zipPath << "\n";

    // Get the original file size for progress tracking
    HANDLE hFile = CreateFileA(dbPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
                               nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    LARGE_INTEGER originalFileSize = {0};
    if (hFile != INVALID_HANDLE_VALUE) {
        GetFileSizeEx(hFile, &originalFileSize);
        CloseHandle(hFile);
    }

    // Delete existing ZIP file if present
    DeleteFileA(zipPath.c_str());

    // Create an empty ZIP file with proper header
    if (!CreateEmptyZipFile(zipPath)) {
        std::cerr << "Warning: Failed to create ZIP file\n";
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    // Initialize COM for Shell operations
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) {
        std::cerr << "Warning: Failed to initialize COM (0x" << std::hex << hr << std::dec << ")\n";
        DeleteFileA(zipPath.c_str());
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }
    bool comInitialized = SUCCEEDED(hr);

    // Convert paths to wide strings for Shell API
    std::wstring wZipPath(zipPath.begin(), zipPath.end());
    std::wstring wDbPath(dbPath.begin(), dbPath.end());

    // Get IShellDispatch interface
    IShellDispatch* pShellDispatch = nullptr;
    hr = CoCreateInstance(CLSID_Shell, nullptr, CLSCTX_INPROC_SERVER,
                          IID_IShellDispatch, reinterpret_cast<void**>(&pShellDispatch));
    if (FAILED(hr) || !pShellDispatch) {
        std::cerr << "Warning: Failed to create Shell instance (0x" << std::hex << hr << std::dec << ")\n";
        DeleteFileA(zipPath.c_str());
        if (comInitialized) CoUninitialize();
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    // Get the ZIP file as a Folder object
    VARIANT vZipPath;
    VariantInit(&vZipPath);
    vZipPath.vt = VT_BSTR;
    vZipPath.bstrVal = SysAllocString(wZipPath.c_str());

    Folder* pZipFolder = nullptr;
    hr = pShellDispatch->NameSpace(vZipPath, &pZipFolder);
    VariantClear(&vZipPath);

    if (FAILED(hr) || !pZipFolder) {
        std::cerr << "Warning: Failed to open ZIP as folder (0x" << std::hex << hr << std::dec << ")\n";
        pShellDispatch->Release();
        DeleteFileA(zipPath.c_str());
        if (comInitialized) CoUninitialize();
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    // Create VARIANT for the source file
    VARIANT vSourceFile;
    VariantInit(&vSourceFile);
    vSourceFile.vt = VT_BSTR;
    vSourceFile.bstrVal = SysAllocString(wDbPath.c_str());

    // Create VARIANT for copy options (no progress dialog, respond yes to all)
    VARIANT vOptions;
    VariantInit(&vOptions);
    vOptions.vt = VT_I4;
    vOptions.lVal = 0x0614;  // FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_NOCOPYSECURITYATTRIBS

    // Copy the file into the ZIP
    hr = pZipFolder->CopyHere(vSourceFile, vOptions);
    VariantClear(&vSourceFile);
    VariantClear(&vOptions);

    if (FAILED(hr)) {
        std::cerr << "Warning: Failed to copy file to ZIP (0x" << std::hex << hr << std::dec << ")\n";
        pZipFolder->Release();
        pShellDispatch->Release();
        DeleteFileA(zipPath.c_str());
        if (comInitialized) CoUninitialize();
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    // Wait for the copy operation to complete
    // The Shell API CopyHere is asynchronous, so we need to wait
    // We monitor the ZIP file size - when it stops growing, compression is complete
    std::cout << "Waiting for compression to complete";

    // Calculate a reasonable timeout based on file size
    // Assume minimum 1 MB/sec compression speed, with 60 second minimum
    int64_t fileSizeMB = originalFileSize.QuadPart / (1024 * 1024);
    int maxWaitSeconds = static_cast<int>((std::max)(60LL, fileSizeMB + 60));

    LONGLONG lastZipSize = 0;
    int stableCount = 0;  // Count consecutive checks with same size
    const int STABLE_THRESHOLD = 6;  // 3 seconds of stable size = done
    bool compressionComplete = false;

    for (int i = 0; i < maxWaitSeconds * 2; i++) {
        // Check ZIP file size
        HANDLE hZipCheck = CreateFileA(zipPath.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hZipCheck != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER currentZipSize;
            GetFileSizeEx(hZipCheck, &currentZipSize);
            CloseHandle(hZipCheck);

            // Check if size is stable (compression complete)
            if (currentZipSize.QuadPart > 22) {  // More than just header
                if (currentZipSize.QuadPart == lastZipSize) {
                    stableCount++;
                    if (stableCount >= STABLE_THRESHOLD) {
                        compressionComplete = true;
                        break;
                    }
                } else {
                    stableCount = 0;  // Size changed, reset counter
                }
                lastZipSize = currentZipSize.QuadPart;
            }
        }

        // Print progress dot every 2 seconds
        if (i % 4 == 0) {
            std::cout << "." << std::flush;
        }
        Sleep(500);
    }
    std::cout << "\n";

    // Cleanup COM objects
    pZipFolder->Release();
    pShellDispatch->Release();
    if (comInitialized) CoUninitialize();

    if (!compressionComplete) {
        std::cerr << "Warning: Compression timed out after " << maxWaitSeconds << " seconds\n";
        std::cerr << "The ZIP file may still be incomplete. Please check manually.\n";
        // Don't delete the ZIP - compression may still be running in background
        std::cout << "ZIP file (possibly incomplete): " << zipPath << "\n";
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    // Verify the ZIP file exists and has content
    DWORD zipAttribs = GetFileAttributesA(zipPath.c_str());
    if (zipAttribs == INVALID_FILE_ATTRIBUTES) {
        std::cerr << "Warning: ZIP file was not created\n";
        std::cout << "Database file preserved: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    // Check ZIP file size is reasonable (should be > 22 bytes which is just the header)
    HANDLE hZipFile = CreateFileA(zipPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                   nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (hZipFile != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER zipFileSize;
        GetFileSizeEx(hZipFile, &zipFileSize);
        CloseHandle(hZipFile);

        if (zipFileSize.QuadPart <= 22) {
            std::cerr << "Warning: ZIP file appears to be empty\n";
            DeleteFileA(zipPath.c_str());
            std::cout << "Database file preserved: " << dbPath << "\n";
            std::cout << "--------------------------------------------------\n";
            return false;
        }

        // Report compression ratio
        if (originalFileSize.QuadPart > 0) {
            double ratio = 100.0 * (1.0 - static_cast<double>(zipFileSize.QuadPart) /
                                          static_cast<double>(originalFileSize.QuadPart));
            std::cout << "Compression ratio: " << std::fixed << std::setprecision(1)
                      << ratio << "% reduction\n";
        }
    }

    std::cout << "Database compressed successfully\n";

    // Delete the original database file
    std::cout << "Deleting original database file...\n";
    if (!DeleteFileA(dbPath.c_str())) {
        DWORD error = GetLastError();
        std::cerr << "Warning: Failed to delete original database file (error: " << error << ")\n";
        std::cout << "ZIP file created: " << zipPath << "\n";
        std::cout << "Original file still exists: " << dbPath << "\n";
        std::cout << "--------------------------------------------------\n";
        return false;
    }

    std::cout << "Original database file deleted\n";
    std::cout << "Final output: " << zipPath << "\n";
    std::cout << "--------------------------------------------------\n";

    return true;
}

/**
 * @brief Checks if a path is a UNC share root (e.g., \\server\share or \\server\share\)
 *
 * A UNC share root has exactly the format \\server\share with no additional path components.
 * This function is used to properly handle UNC paths for Windows APIs that require
 * special formatting (like trailing backslash for GetDriveTypeW).
 *
 * @param path The path to check (wide string)
 * @return true if this is a UNC share root, false otherwise
 */
bool IsUncShareRoot(const std::wstring& path) {
    if (path.length() < 5) return false;  // Minimum: \\a\b
    if (path[0] != L'\\' || path[1] != L'\\') return false;  // Must start with double backslash
    if (path[2] == L'?' || path[2] == L'\\') return false;  // Not \\?\ prefix or triple backslash

    // Find the server name end (first backslash after \\)
    size_t serverEnd = path.find(L'\\', 2);
    if (serverEnd == std::wstring::npos) return false;  // No share name

    // Find the share name end (next backslash after server)
    size_t shareEnd = path.find(L'\\', serverEnd + 1);

    // It's a share root if there's no more path after the share name,
    // or if the only thing after is a trailing backslash
    if (shareEnd == std::wstring::npos) {
        return true;  // \\server\share (no trailing backslash)
    }
    if (shareEnd == path.length() - 1) {
        return true;  // \\server\share\ (with trailing backslash)
    }
    return false;  // \\server\share\subfolder - not a share root
}

/**
 * @brief Checks if a path is a UNC path (starts with \\)
 *
 * @param path The path to check (narrow string)
 * @return true if this is a UNC path, false otherwise
 */
bool IsUncPath(const std::string& path) {
    return path.length() >= 2 && path[0] == '\\' && path[1] == '\\' &&
           (path.length() < 4 || path[2] != '?' || path[3] != '\\');
}

/**
 * @brief OPT-004: Determines optimal thread count based on drive type
 *
 * Folder scanning is I/O-bound, not CPU-bound. Too many threads cause disk thrashing.
 * - HDD: Limited to 4-8 threads (mechanical seek latency dominates)
 * - SATA SSD: Limited to 8 threads (moderate parallelism)
 * - NVMe SSD: Can use more threads (high IOPS, low latency)
 * - Network: Limited threads (network latency dominates)
 *
 * @param scanPath The path being scanned
 * @param hardwareConcurrency Number of logical CPU cores
 * @return Optimal thread count for scanning
 */
unsigned int CalculateOptimalThreadCount(const std::wstring& scanPath, unsigned int hardwareConcurrency) {
    // For GetDriveTypeW to work correctly with UNC paths, they need a trailing backslash
    // e.g., \\server\share\ not \\server\share
    std::wstring pathForDriveType = scanPath;

    // Check if this is a UNC path and ensure it has trailing backslash for GetDriveTypeW
    if (scanPath.length() >= 2 && scanPath[0] == L'\\' && scanPath[1] == L'\\') {
        // It's a UNC path - GetDriveTypeW needs \\server\share\ format
        if (pathForDriveType.back() != L'\\') {
            pathForDriveType += L'\\';
        }
    }

    // Get drive type
    UINT driveType = GetDriveTypeW(pathForDriveType.c_str());

    // Default: conservative thread count for I/O workloads
    // Note: Parentheses around std::max/min prevent Windows macro expansion
    unsigned int optimalThreads = (std::max)(2u, (std::min)(hardwareConcurrency, 8u));

    switch (driveType) {
        case DRIVE_FIXED:
            // Local fixed disk - check if it's NVMe/SSD via device properties
            // For simplicity, assume SATA SSD characteristics (can be enhanced with WMI)
            optimalThreads = (std::min)(hardwareConcurrency, 8u);
            break;

        case DRIVE_REMOTE:
        case DRIVE_REMOVABLE:
            // Network or removable drive - use fewer threads (network/USB bandwidth limited)
            optimalThreads = (std::min)(hardwareConcurrency / 2, 4u);
            break;

        case DRIVE_RAMDISK:
            // RAM disk - can use more threads (extremely fast)
            optimalThreads = hardwareConcurrency;
            break;

        case DRIVE_CDROM:
            // Optical drive - very limited parallelism
            optimalThreads = 2;
            break;

        default:
            // Unknown - use conservative default
            optimalThreads = (std::min)(hardwareConcurrency, 8u);
            break;
    }

    // Ensure at least 2 threads
    // Note: Parentheses around std::max/min prevent Windows macro expansion
    return (std::max)(2u, optimalThreads);
}

/**
 * @brief Parse command-line arguments into structured format
 *
 * Handles all three execution modes:
 * - Normal: <FolderToScan> <DatabaseFile> [options]
 * - AllFixedDisks: --allfixeddisks <DatabaseFile> [options]
 * - TestAccess: --testaccess <FolderToScan>
 *
 * @param argc Argument count
 * @param argv Argument values
 * @return ParsedArguments with mode, paths, and options
 */
ParsedArguments ParseCommandLineArguments(int argc, char* argv[]) {
    ParsedArguments args;

    if (argc < 2) {
        return args;  // Will fail validation
    }

    // Check for special modes first
    std::string firstArg = to_upper(argv[1]);

    if (firstArg == "--ALLFIXEDDISKS") {
        args.mode = ExecutionMode::AllFixedDisks;
        // Next argument should be database path
        if (argc >= 3) {
            args.databasePath = argv[2];
        }
        // Parse remaining optional arguments starting at index 3
        for (int i = 3; i < argc; i++) {
            std::string arg = to_upper(argv[i]);
            if (arg == "--EXPLICITONLY") {
                args.explicitOnly = true;
            } else if (arg == "--DEBUG") {
                args.debugMode = true;
            } else if (arg == "--NOZIP") {
                args.noZip = true;
            } else if (arg == "--REMOTECOMPUTER" && i + 1 < argc) {
                args.remoteComputer = argv[++i];
            }
        }
    } else if (firstArg == "--TESTACCESS") {
        args.mode = ExecutionMode::TestAccess;
        // Next argument should be folder path
        if (argc >= 3) {
            std::string folderPath = argv[2];
            // Remove surrounding quotes if present
            if (!folderPath.empty() && folderPath.front() == '"' && folderPath.back() == '"') {
                folderPath = folderPath.substr(1, folderPath.size() - 2);
            }
            args.folderToScan = FolderUtils::toWideFromAcp(folderPath);
        }
        // Parse optional arguments
        for (int i = 3; i < argc; i++) {
            std::string arg = to_upper(argv[i]);
            if (arg == "--DEBUG") {
                args.debugMode = true;
            }
        }
    } else if (firstArg == "--TESTEXCLUDE") {
        // Special case: handled separately in main(), return empty args
        return args;
    } else {
        // Normal mode: <FolderToScan> <DatabaseFile> [options]
        args.mode = ExecutionMode::Normal;

        std::string folderPath = argv[1];
        // Remove surrounding quotes if present
        if (!folderPath.empty() && folderPath.front() == '"' && folderPath.back() == '"') {
            folderPath = folderPath.substr(1, folderPath.size() - 2);
        }
        args.folderToScan = FolderUtils::toWideFromAcp(folderPath);

        if (argc >= 3) {
            args.databasePath = argv[2];
        }

        // Parse optional arguments starting at index 3
        for (int i = 3; i < argc; i++) {
            std::string arg = to_upper(argv[i]);
            if (arg == "--EXPLICITONLY") {
                args.explicitOnly = true;
            } else if (arg == "--DEBUG") {
                args.debugMode = true;
            } else if (arg == "--NOZIP") {
                args.noZip = true;
            } else if (arg == "--REMOTECOMPUTER" && i + 1 < argc) {
                args.remoteComputer = argv[++i];
            }
        }
    }

    return args;
}

/**
 * @brief Display usage message including all modes
 * @param programName The program name (argv[0])
 */
void DisplayUsage(const char* programName) {
    std::cerr << "\n"
              << "DESCRIPTION\n"
              << "    Collects NTFS folder permissions and stores them in a SQLite database.\n"
              << "    Enumerates folders, retrieves DACLs (Discretionary Access Control Lists),\n"
              << "    and records ACE (Access Control Entry) details for security analysis.\n"
              << "\n"
              << "SYNTAX\n"
              << "\n"
              << "    Folder Scan (default mode):\n"
              << "        " << programName << " <FolderPath> <DatabaseFile> [options]\n"
              << "\n"
              << "    All Fixed Disks:\n"
              << "        " << programName << " --allfixeddisks <DatabaseFile> [options]\n"
              << "\n"
              << "    Access Test:\n"
              << "        " << programName << " --testaccess <FolderPath>\n"
              << "\n"
              << "    Exclusion Test:\n"
              << "        " << programName << " --testexclude <Path>\n"
              << "\n"
              << "PARAMETERS\n"
              << "\n"
              << "    <FolderPath>      Root folder path to scan. Supports local paths (C:\\Data)\n"
              << "                      and UNC paths (\\\\Server\\Share).\n"
              << "\n"
              << "    <DatabaseFile>    Output SQLite database file path. Created if it does not\n"
              << "                      exist; appends to existing database if present.\n"
              << "\n"
              << "OPTIONS\n"
              << "\n"
              << "    --allfixeddisks   Scan all fixed disk volumes on the local machine.\n"
              << "                      Discovers volumes via Windows Volume Management APIs,\n"
              << "                      including volumes mounted as folders or without drive\n"
              << "                      letters. Cannot be combined with --RemoteComputer.\n"
              << "\n"
              << "    --testaccess      Test folder access permissions without writing to a\n"
              << "                      database. Reports all folders returning ACCESS_DENIED.\n"
              << "                      Useful for pre-scan validation.\n"
              << "\n"
              << "    --testexclude     Test whether a path matches the built-in exclusion\n"
              << "                      filters (snapshot directories, replication folders).\n"
              << "\n"
              << "    --ExplicitOnly    Collect only explicitly-set DACLs; skip inherited ACLs.\n"
              << "                      Reduces database size when inheritance analysis is not\n"
              << "                      required. Not available with --testaccess.\n"
              << "\n"
              << "    --RemoteComputer <Name>\n"
              << "                      Specify the source computer name for UNC path scans.\n"
              << "                      Recorded in the database for inventory identification.\n"
              << "                      Not available with --allfixeddisks or --testaccess.\n"
              << "\n"
              << "    --Debug           Enable verbose diagnostic output. Writes detailed\n"
              << "                      trace information to CollectNTFSPerms.debug file.\n"
              << "\n"
              << "    --NoZip           Skip automatic compression and cleanup of the database\n"
              << "                      file. By default, the database is compressed to a .zip\n"
              << "                      file and the original .db file is deleted to save space.\n"
              << "                      Use this option to preserve the original database file.\n"
              << "\n"
              << "EXAMPLES\n"
              << "\n"
              << "    Scan a folder and store permissions:\n"
              << "        " << programName << " D:\\SharedData D:\\Output\\permissions.db\n"
              << "\n"
              << "    Scan with explicit-only ACLs:\n"
              << "        " << programName << " E:\\Projects E:\\Output\\projects.db --ExplicitOnly\n"
              << "\n"
              << "    Scan a remote share:\n"
              << "        " << programName << " \"\\\\FileServer01\\Data\" C:\\Output\\server01.db --RemoteComputer FileServer01\n"
              << "\n"
              << "    Scan all local fixed disks:\n"
              << "        " << programName << " --allfixeddisks C:\\Output\\full_inventory.db\n"
              << "\n"
              << "    Test access before scanning:\n"
              << "        " << programName << " --testaccess D:\\SecureFolder\n"
              << "\n"
              << "    Check if a path is excluded:\n"
              << "        " << programName << " --testexclude \"C:\\System Volume Information\"\n"
              << "\n"
              << "EXIT CODES\n"
              << "\n"
              << "    0    Success\n"
              << "    1    Error (invalid arguments, access denied, database failure)\n"
              << "\n"
              << "NOTES\n"
              << "\n"
              << "    - Run as Administrator for full access to all folders and system metadata.\n"
              << "    - Certain system folders are automatically excluded (Recycle Bin, System\n"
              << "      Volume Information, DFS staging, etc.).\n"
              << "    - Thread count is automatically optimized based on storage type (SSD/HDD).\n"
              << "\n";
}

/**
 * @brief Run the access test mode
 *
 * Lightweight scanner that only tests folder access and reports ACCESS_DENIED paths.
 * No database operations are performed.
 *
 * @param args Parsed command-line arguments
 * @return 0 on success, 1 on error
 */
int RunAccessTestMode(const ParsedArguments& args) {
    std::cout << "\n=== ACCESS TEST MODE ===" << std::endl;
    std::cout << "Testing folder access permissions (no database operations)\n" << std::endl;

    // Validate the root path exists
    if (!SecurityUtils::isValidPath(args.folderToScan)) {
        std::cerr << "Error: Invalid or inaccessible folder path: "
                  << FolderUtils::toUtf8(args.folderToScan) << std::endl;
        return 1;
    }

    std::cout << "Root folder: " << FolderUtils::toUtf8(args.folderToScan) << std::endl;

    // Calculate thread count based on drive type
    unsigned int hardwareConcurrency = std::thread::hardware_concurrency();
    if (hardwareConcurrency == 0) hardwareConcurrency = 4;
    int threadCount = CalculateOptimalThreadCount(args.folderToScan, hardwareConcurrency);

    std::cout << "Thread count: " << threadCount << std::endl;
    std::cout << "\n--------------------------------------------------\n";
    std::cout << "Scanning folders (ACCESS DENIED paths shown in summary)...\n";

    // Create and run scanner
    // Note: Not using real-time callback to keep progress line clean
    AccessTestScanner scanner(args.folderToScan, threadCount);

    // Run the scan
    AccessTestResults results = scanner.run();

    // Print summary
    std::cout << "\n--------------------------------------------------\n";
    std::cout << "ACCESS TEST SUMMARY\n";
    std::cout << "--------------------------------------------------\n";
    std::cout << "Total folders scanned   : " << results.totalFolders << std::endl;
    std::cout << "Accessible folders      : " << results.accessibleFolders << std::endl;
    std::cout << "Access denied folders   : " << results.accessDeniedFolders << std::endl;
    std::cout << "Other errors            : " << results.otherErrors << std::endl;
    std::cout << "--------------------------------------------------\n";

    if (results.accessDeniedFolders > 0) {
        std::cout << "\nPaths with ACCESS DENIED:\n";
        for (const auto& entry : results.deniedPaths) {
            std::wcout << L"  " << entry.path << std::endl;
        }
    }

    return 0;
}

/**
 * @brief Main entry point for the CollectNTFSPerms utility.
 *
 * Orchestrates the scanning of NTFS folder permissions and stores results in an SQLite database. Handles command-line argument parsing, input validation, environment setup, database initialization or opening, metadata insertion, disk information collection (if running as administrator), and the folder scanning process. Logs key events and updates the database with scan statistics. Exits with code 0 on success or 1 on failure.
 *
 * @param argc Number of command-line arguments.
 * @param argv Array of command-line argument strings.
 * @return int Returns 0 on successful completion, or 1 if an error occurs.
 */
int main(int argc, char* argv[]) {
    // Force console output to be unbuffered
    std::cout.setf(std::ios::unitbuf);
    std::cerr.setf(std::ios::unitbuf);

    // Check for sqlite3.dll before any database operations
    if (!CheckSQLiteDllAvailable()) {
        return 1;
    }

    std::cout << "\n"
              << "CollectNTFSPerms v" << VERSION_STRING << "\n"
              << "NTFS Permissions Collection Utility\n"
              << "Build: " << BUILD_DATE_TIME << "\n\n";

    // Check for --TestExclude option first (standalone operation)
    if (argc >= 3) {
        std::string arg = to_upper(argv[1]);
        if (arg == "--TESTEXCLUDE") {
            // Test if the provided path would be excluded
            std::string testPath = argv[2];
            // Remove surrounding quotes if present
            if (!testPath.empty() && testPath.front() == '"' && testPath.back() == '"') {
                testPath = testPath.substr(1, testPath.size() - 2);
            }

            std::wstring wideTestPath = FolderUtils::toWideFromAcp(testPath);
            bool isExcluded = IsExcludedSnapshotPath(wideTestPath);

            std::cout << "Path: " << testPath << "\n";
            std::cout << "Result: " << (isExcluded ? "True" : "False") << "\n";
            std::cout << (isExcluded ? "EXCLUDED - This path would be skipped during scanning\n" :
                                       "INCLUDED - This path would be scanned\n");

            return 0;
        }
    }

    // Parse command-line arguments
    ParsedArguments parsedArgs = ParseCommandLineArguments(argc, argv);

    // Validate arguments
    if (!parsedArgs.isValid()) {
        std::string error = parsedArgs.validationError();
        if (!error.empty()) {
            std::cerr << "Error: " << error << "\n\n";
        }
        DisplayUsage(argv[0]);
        return 1;
    }

    // Handle TestAccess mode early (no database operations)
    if (parsedArgs.mode == ExecutionMode::TestAccess) {
        // Enable debug mode if requested
        if (parsedArgs.debugMode) {
            AppGlobals::DebugMode.store(true);
            AppGlobals::OpenDebugFile("CollectNTFSPerms.debug");
            std::cout << "[DEBUG MODE ENABLED - Output: CollectNTFSPerms.debug]\n\n";
        }
        return RunAccessTestMode(parsedArgs);
    }

    // For AllFixedDisks and Normal modes, continue with database operations
    g_explicitOnly = parsedArgs.explicitOnly;
    std::string dbPath = parsedArgs.databasePath;
    std::string remoteComputer = parsedArgs.remoteComputer;
    std::chrono::system_clock::time_point global_utc_time = std::chrono::system_clock::now();
    unsigned int hardwareConcurrency = std::thread::hardware_concurrency();
    if (hardwareConcurrency == 0) hardwareConcurrency = 4;  // Fallback if detection fails

    // Start tracking peak memory usage
    std::thread memoryMonitor([]() {
        while (!shouldStop.load()) {  // Use atomic load
            UpdatePeakMemoryUsage();
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    });
    memoryMonitor.detach();  // Let it run in the background

    // RAII guard ensures shouldStop is set on ALL exit paths (success or error)
    ShouldStopGuard stopGuard;

    // Enable debug mode if requested
    if (parsedArgs.debugMode) {
        AppGlobals::DebugMode.store(true);
        AppGlobals::OpenDebugFile("CollectNTFSPerms.debug");
        std::cout << "[DEBUG MODE ENABLED - Output: CollectNTFSPerms.debug]\n\n";

        // Write application header to debug file
        AppGlobals::WriteDebug("CollectNTFSPerms v" + std::string(VERSION_STRING) + "\n");
        AppGlobals::WriteDebug("NTFS Permissions Collection Utility\n");
        AppGlobals::WriteDebug("Build: " + std::string(BUILD_DATE_TIME) + "\n\n");
        AppGlobals::WriteDebug("[DEBUG MODE ENABLED]\n\n");
    }

    // Variables for scan path - set based on execution mode
    std::wstring wideScanPath;
    std::string folderToScan;
    bool isUncScan = false;
    int threadCount = 0;

    // For AllFixedDisks mode, we'll enumerate all fixed disks
    // For now, set up for the first disk (will be handled in the loop below)
    std::vector<FixedDiskEnumerator::FixedDiskInfo> fixedDisks;

    // Mount point traversal context for AllFixedDisks mode
    FixedDiskEnumerator::MountPointTraversalContext mountPointContext;

    if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
        std::cout << "=== ALL FIXED DISKS MODE ===\n";
        std::cout << "Enumerating all fixed disk volumes with nesting detection...\n\n";

        // Use the new nesting-aware enumeration
        fixedDisks = FixedDiskEnumerator::EnumerateFixedDisksWithNesting();

        if (fixedDisks.empty()) {
            std::cerr << "Error: No scannable fixed disk volumes found.\n";
            return 1;
        }

        // Build traversal context for mount point handling
        mountPointContext = FixedDiskEnumerator::BuildTraversalContext(fixedDisks);

        // Count root vs nested volumes
        int rootCount = 0;
        int nestedCount = 0;
        for (const auto& disk : fixedDisks) {
            if (disk.isRootVolume) rootCount++;
            else nestedCount++;
        }

        std::cout << "\nFound " << fixedDisks.size() << " fixed disk volume(s):\n";
        std::cout << "  - " << rootCount << " root volume(s) (will be scanned as starting points)\n";
        std::cout << "  - " << nestedCount << " nested volume(s) (will be reached via mount point traversal)\n\n";

        std::cout << "Root volumes to scan:\n";
        for (const auto& disk : fixedDisks) {
            if (disk.isRootVolume) {
                std::wcout << L"  - " << disk.primaryPath;
                if (!disk.volumeLabel.empty()) {
                    std::wcout << L" (" << disk.volumeLabel << L")";
                }
                if (disk.isSystem) {
                    std::wcout << L" [System]";
                }
                std::wcout << std::endl;
            }
        }
        std::cout << std::endl;

        // Build scan path string with all root volumes for metadata
        std::string allVolumePaths;
        for (const auto& disk : fixedDisks) {
            if (disk.isRootVolume) {
                if (!allVolumePaths.empty()) {
                    allVolumePaths += ", ";
                }
                allVolumePaths += FolderUtils::toUtf8(disk.primaryPath);
            }
        }
        folderToScan = "AllFixedDisks: " + allVolumePaths;

        // Find first root volume for initial validation/setup
        for (const auto& disk : fixedDisks) {
            if (disk.isRootVolume) {
                wideScanPath = disk.primaryPath;
                break;
            }
        }
    } else {
        // Normal mode: validate the provided folder path
        wideScanPath = parsedArgs.folderToScan;
        folderToScan = FolderUtils::toUtf8(wideScanPath);

        // UNC-FIX: Detect and log UNC path handling
        isUncScan = (wideScanPath.length() >= 2 &&
                     wideScanPath[0] == L'\\' &&
                     wideScanPath[1] == L'\\');
        if (isUncScan) {
            std::cout << "Detected UNC path: " << folderToScan << "\n";
            // For debug mode, show additional path details
            if (AppGlobals::DebugMode.load()) {
                AppGlobals::WriteDebug("UNC Path Details:\n");
                AppGlobals::WriteDebug("  Original path: " + folderToScan + "\n");
                AppGlobals::WriteDebug("  Wide path length: " + std::to_string(wideScanPath.length()) + "\n");
            }
        }

        std::cout << "Checking if folder exists and is accessible...\n";
        if (!SecurityUtils::isValidPath(wideScanPath)) {
            std::cerr << "Error: Invalid or inaccessible folder path: " << folderToScan << "\n";

            // UNC-FIX: Provide additional troubleshooting for UNC paths
            if (isUncScan) {
                std::cerr << "\nUNC Path Troubleshooting:\n";
                std::cerr << "  - Verify the server is reachable (try: ping <servername>)\n";
                std::cerr << "  - Verify the share exists (try: net view \\\\<servername>)\n";
                std::cerr << "  - Verify you have access to the share\n";
                std::cerr << "  - Try accessing the path in Windows Explorer first\n\n";
            }
            return 1;
        }
    }

    // OPT-004: Calculate optimal thread count based on drive type (I/O-bound workload)
    threadCount = CalculateOptimalThreadCount(wideScanPath, hardwareConcurrency);

    // UNC-FIX: Provide drive type info in output for network paths
    if (isUncScan) {
        std::cout << "Network path detected - using " << threadCount << " threads (optimized for network I/O)\n";
    } else {
        std::cout << "Optimized thread count: " << threadCount
                  << " (Drive type detection based on: " << FolderUtils::toUtf8(wideScanPath) << ")\n";
    }

    // Sanitize computer name if provided
    if (!remoteComputer.empty()) {
        if (!SecurityUtils::isValidComputerName(remoteComputer)) {
            std::cerr << "Error: Invalid computer name: " << remoteComputer << "\n";
            return 1;
        }
        remoteComputer = SecurityUtils::sanitizeComputerName(remoteComputer);
        AppGlobals::SetComputerName(remoteComputer);
        std::cout << "Overriding local computer name with: " << remoteComputer << "\n";
    }
    // Sanitize domain name
    std::string sanitizedDomain = SecurityUtils::sanitizeDomainName(AppGlobals::DomainName());

    global_utc_time = std::chrono::system_clock::now();
    std::string isoUtc = FormatTime(global_utc_time, false);

    std::cout << "--------------------------------------------------\n";
    std::cout << "Execution Mode : " << parsedArgs.modeName() << "\n";
    std::cout << "Start Time     : " << isoUtc << " UTC\n";
    if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
        // Count root volumes for display
        size_t rootVols = 0;
        for (const auto& d : fixedDisks) if (d.isRootVolume) rootVols++;
        std::cout << "Scan Target    : " << fixedDisks.size() << " fixed disk volume(s) ("
                  << rootVols << " root, " << (fixedDisks.size() - rootVols) << " nested)\n";
    } else {
        std::cout << "Scan Folder    : " << folderToScan << (isUncScan ? " (UNC/Network)" : " (Local)") << "\n";
    }
    std::cout << "Database File  : " << dbPath << "\n";
    std::cout << "Computer Name  : " << AppGlobals::ComputerName() << "\n";
    if (g_explicitOnly) std::cout << "Explicit Only  : Enabled\n";
    std::cout << "Hardware Cores : " << hardwareConcurrency << "\n";
    std::cout << "Thread Count   : " << threadCount << "\n";
    std::cout << "--------------------------------------------------\n\n";

    // Write settings to debug file
    AppGlobals::WriteDebug("--------------------------------------------------\n");
    AppGlobals::WriteDebug("Execution Mode : " + std::string(parsedArgs.modeName()) + "\n");
    AppGlobals::WriteDebug("Start Time     : " + isoUtc + " UTC\n");
    if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
        size_t rootVols = 0;
        for (const auto& d : fixedDisks) if (d.isRootVolume) rootVols++;
        AppGlobals::WriteDebug("Scan Target    : " + std::to_string(fixedDisks.size()) + " fixed disk volume(s) ("
                              + std::to_string(rootVols) + " root, " + std::to_string(fixedDisks.size() - rootVols) + " nested)\n");
    } else {
        AppGlobals::WriteDebug("Scan Folder    : " + folderToScan + (isUncScan ? " (UNC/Network)" : " (Local)") + "\n");
    }
    AppGlobals::WriteDebug("Database File  : " + dbPath + "\n");
    AppGlobals::WriteDebug("Computer Name  : " + AppGlobals::ComputerName() + "\n");
    if (g_explicitOnly) AppGlobals::WriteDebug("Explicit Only  : Enabled\n");
    AppGlobals::WriteDebug("Hardware Cores : " + std::to_string(hardwareConcurrency) + "\n");
    AppGlobals::WriteDebug("Thread Count   : " + std::to_string(threadCount) + "\n");
    AppGlobals::WriteDebug("--------------------------------------------------\n\n");

    // Initialize database context
    DatabaseContext dbCtx;
    dbCtx.inventoryID = AppGlobals::InventoryID();

    // Check if database file exists using Win32 API
    DWORD fileAttribs = GetFileAttributesA(dbPath.c_str());
    bool databaseAlreadyExists = (fileAttribs != INVALID_FILE_ATTRIBUTES &&
                                   !(fileAttribs & FILE_ATTRIBUTE_DIRECTORY));

    try {
        // Check if database already exists
        if (databaseAlreadyExists) {
            std::cout << "Database file already exists: " << dbPath << std::endl;
            if (!OpenExistingDatabase(dbCtx, dbPath)) {
                std::cerr << "Failed to open existing database" << std::endl;
                return 1;
            }
            std::cout << "Successfully opened existing database" << std::endl;
        } else {
            // Initialize new database
            std::cout << "Starting database initialization..." << std::endl;
            if (!InitializeDatabase(dbCtx, dbPath)) {
                std::cerr << "Failed to initialize database" << std::endl;
                return 1;
            }
            std::cout << "Database initialization completed successfully" << std::endl;
        }

    } catch (const std::exception& e) {
        std::cerr << "Exception during database initialization: " << e.what() << std::endl;
        return 1;
    } catch (...) {
        std::cerr << "Unknown exception during database initialization" << std::endl;
        return 1;
    }

    // Log the database operation
    const char* source = databaseAlreadyExists ? "DatabaseOpen" : "DatabaseInit";
    const char* message = databaseAlreadyExists ? 
        "Existing database opened successfully" : 
        "New database initialized successfully";

    // Insert initial collection info
    if (!InsertCollectionInfo(
        dbCtx,                          // Database context
        dbCtx.inventoryID,              // Inventory ID
        AppGlobals::ComputerName(),     // Computer name
        sanitizedDomain,                // Domain name (sanitized)
        global_utc_time,                // Collection time (time_point)
        VERSION_STRING,                 // Application version
        BUILD_DATE_TIME,                // Application build
        IsRunningAsAdmin(),             // Is admin
        GetCurrentUser(),               // Who
        hardwareConcurrency,            // Hardware concurrency
        threadCount,                    // Thread count
        GetAbsolutePath(dbPath),        // Output path (absolute)
        folderToScan,                   // Scan path
        !remoteComputer.empty(),        // Remote computer flag
        g_explicitOnly                  // Explicit only flag
    )) {
        std::cerr << "Failed to insert collection info" << std::endl;
        return 1;
    }

    LogEvent(
        dbCtx,                          // Database context
        Logging::Severity::INFO,        // Severity level
        source,                         // Source of the event
        message,                        // Event message
        dbPath,                         // Database path
        0,                              // Error code (0 for success)
        GetCurrentThreadId(),           // Current thread ID
        "Database Version: " + std::string(DB_SCHEMA_VERSION),  // Additional data
        dbCtx.inventoryID               // Inventory ID
    );

    // Collect and store disk information
    std::cout << "\nCollecting disk information...\n";
    std::cout << "--------------------------------------------------\n";
    if (!AppGlobals::IsAdmin() || !remoteComputer.empty()) {
        if (!AppGlobals::IsAdmin()) {
            std::cout << "Disk information not collected. User "
                      << AppGlobals::CurrentUser() << " is not running as admin!" << std::endl;
        } else {
            std::cout << "Disk information not collected. Remote computer scan detected." << std::endl;
        }

        // Log skipped disk collection
        LogEvent(
            dbCtx,
            Logging::Severity::WARNING,
            "DiskCollection",
            "Disk information collection skipped",
            "",
            0,
            GetCurrentThreadId(),
            !AppGlobals::IsAdmin() ? "User is not running as administrator" : "Remote computer scan - local disk info not applicable",
            dbCtx.inventoryID
        );
    } else {
        try {
            int diskCount = DiskCollector::CollectAndStoreDiskInfo(dbCtx.db->get(), dbCtx.inventoryID);
            std::cout << "\nDisk information collected successfully\n";
            
            // Log successful disk collection with summary
            LogEvent(
                dbCtx,
                Logging::Severity::INFO,
                "DiskCollection",
                "Disk information collected successfully",
                "",
                0,
                GetCurrentThreadId(),
                "Processed " + std::to_string(diskCount) + " disks",
                dbCtx.inventoryID
            );
        } catch (const DiskCollector::DiskCollectionException& e) {
            std::cerr << "Failed to collect disk information: " << e.what() << std::endl;
            
            // Log disk collection failure
            LogEvent(
                dbCtx,
                Logging::Severity::ERR,
                "DiskCollection",
                "Failed to collect disk information",
                "",
                0,
                GetCurrentThreadId(),
                e.what(),
                dbCtx.inventoryID
            );
        }
    }

    // Collect and store volume information
    std::cout << "\n\nCollecting volume information...\n";
    std::cout << "--------------------------------------------------\n";
    if (!AppGlobals::IsAdmin() || !remoteComputer.empty()) {
        if (!AppGlobals::IsAdmin()) {
            std::cout << "Volume information not collected. User "
                      << AppGlobals::CurrentUser() << " is not running as admin!" << std::endl;
        } else {
            std::cout << "Volume information not collected. Remote computer scan detected." << std::endl;
        }

        // Log skipped volume collection
        LogEvent(
            dbCtx,
            Logging::Severity::WARNING,
            "VolumeCollection",
            "Volume information collection skipped",
            "",
            0,
            GetCurrentThreadId(),
            !AppGlobals::IsAdmin() ? "User is not running as administrator" : "Remote computer scan - local volume info not applicable",
            dbCtx.inventoryID
        );
    } else {
        try {
            int volumeCount = VolumeCollector::CollectAndStoreVolumeInfo(dbCtx.db->get(), dbCtx.inventoryID);
            std::cout << "Volume information collected successfully\n";

            // Log successful volume collection with summary
            LogEvent(
                dbCtx,
                Logging::Severity::INFO,
                "VolumeCollection",
                "Volume information collected successfully",
                "",
                0,
                GetCurrentThreadId(),
                "Processed " + std::to_string(volumeCount) + " volumes",
                dbCtx.inventoryID
            );
        } catch (const VolumeCollector::VolumeCollectionException& e) {
            std::cerr << "Failed to collect volume information: " << e.what() << std::endl;

            // Log volume collection failure
            LogEvent(
                dbCtx,
                Logging::Severity::ERR,
                "VolumeCollection",
                "Failed to collect volume information",
                "",
                0,
                GetCurrentThreadId(),
                e.what(),
                dbCtx.inventoryID
            );
        }
    }

    // Collect and store partition information
    std::cout << "\nCollecting partition information...\n";
    std::cout << "--------------------------------------------------\n";
    if (!AppGlobals::IsAdmin() || !remoteComputer.empty()) {
        if (!AppGlobals::IsAdmin()) {
            std::cout << "Partition information not collected. User "
                      << AppGlobals::CurrentUser() << " is not running as admin!" << std::endl;
        } else {
            std::cout << "Partition information not collected. Remote computer scan detected." << std::endl;
        }

        // Log skipped partition collection
        LogEvent(
            dbCtx,
            Logging::Severity::WARNING,
            "PartitionCollection",
            "Partition information collection skipped",
            "",
            0,
            GetCurrentThreadId(),
            !AppGlobals::IsAdmin() ? "User is not running as administrator" : "Remote computer scan - local partition info not applicable",
            dbCtx.inventoryID
        );
    } else {
        int partitionCount = 0;
        if (!CollectPartitions(dbCtx.db->get(), dbCtx.inventoryID, &partitionCount)) {
            std::cerr << "Failed to collect partition information" << std::endl;
            LogEvent(
                dbCtx,
                Logging::Severity::ERR,
                "PartitionCollection",
                "Failed to collect partition information",
                "",
                0,
                GetCurrentThreadId(),
                "",
                dbCtx.inventoryID
            );
        } else {
            std::cout << "Partition information collected successfully\n";
            LogEvent(
                dbCtx,
                Logging::Severity::INFO,
                "PartitionCollection",
                "Partition information collected successfully",
                "",
                0,
                GetCurrentThreadId(),
                "Processed " + std::to_string(partitionCount) + " partitions",
                dbCtx.inventoryID
            );
        }
    }

    // Initialize and start folder scanning
    std::cout << "\n\nStarting folder inventory scan...\n";
    std::cout << "--------------------------------------------------\n";

    // Track timing for each phase
    auto overallStartTime = std::chrono::high_resolution_clock::now();
    auto folderScanStartTime = std::chrono::high_resolution_clock::now();

    // Build list of paths to scan
    std::vector<std::wstring> pathsToScan;
    if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
        // Only scan ROOT volumes - nested volumes will be reached via mount point traversal
        for (const auto& disk : fixedDisks) {
            if (disk.isRootVolume) {
                pathsToScan.push_back(disk.primaryPath);
            }
        }
        // Set the mount point traversal context so scanner can traverse into mount points
        dbCtx.mountPointContext = &mountPointContext;
        std::cout << "Mount point traversal enabled: scanner will traverse into "
                  << mountPointContext.targetVolumeGuids.size() << " target volume mount points\n\n";
    } else {
        pathsToScan.push_back(wideScanPath);
    }

    // For multi-disk scanning, we need to track IDs across volumes
    // Each volume's FolderScanner and AclProcessor should start from where the previous one left off
    size_t totalVolumesScanned = 0;
    size_t totalVolumeErrors = 0;
    int64_t nextFolderId = 1;  // Track next available folder ID across volume scans
    int64_t nextAclId = 1;     // Track next available ACL ID across volume scans
    int64_t nextAceId = 1;     // Track next available ACE ID across volume scans

    // Cumulative statistics for AllFixedDisks mode (aggregated across all volumes)
    int64_t cumulativeFoldersProcessed = 0;
    int cumulativeFoldersWithErrors = 0;
    int maxPeakQueueSize = 0;
    int maxPeakMemoryUsageMB = 0;

    // Loop through all paths to scan
    for (size_t volumeIndex = 0; volumeIndex < pathsToScan.size(); volumeIndex++) {
        const std::wstring& currentScanPath = pathsToScan[volumeIndex];

        if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
            std::wcout << L"\n=== Scanning Volume " << (volumeIndex + 1) << L" of "
                       << pathsToScan.size() << L": " << currentScanPath << L" ===\n" << std::endl;
            std::cout << "Starting folder ID: " << nextFolderId << std::endl;
        }

    try {
        // Create and start the folder scanner
        // Pass the next available folder ID to ensure unique IDs across volume scans
        FolderScanner scanner(currentScanPath, dbCtx.inventoryID, threadCount, dbCtx, nextFolderId);
        if (!scanner.start()) {
            std::cerr << "Failed to start folder scanning for: "
                      << FolderUtils::toUtf8(currentScanPath) << std::endl;

            // For AllFixedDisks mode, continue to next volume
            if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
                totalVolumeErrors++;
                std::cerr << "Continuing to next volume..." << std::endl;
                continue;  // Continue to next volume in the loop
            }
            return 1;
        }

        // Now discover SMB shares to add paths to folder index BEFORE ACL processing
        // For AllFixedDisks mode, only run on first volume (shares are system-wide)
        bool shouldRunSmbOperations = (parsedArgs.mode != ExecutionMode::AllFixedDisks) || (volumeIndex == 0);

        if (shouldRunSmbOperations) {
            std::cout << "\nDiscovering SMB shares...\n";
            std::cout << "--------------------------------------------------\n";
            if (!remoteComputer.empty()) {
                std::cout << "SMB share discovery not collected. Remote computer scan detected." << std::endl;

                // Log skipped share discovery
                LogEvent(
                    dbCtx,
                    Logging::Severity::WARNING,
                    "SMBShareDiscovery",
                    "SMB share discovery skipped",
                    "",
                    0,
                    GetCurrentThreadId(),
                    "Remote computer scan - local SMB share info not applicable",
                    dbCtx.inventoryID
                );
            } else {
                // Create SMB share collector using the folder index from the scanner
                SMBShareCollector shareDiscoverer(dbCtx, scanner.getFolderIndex());

                // Discover shares to add paths to folder index
                auto startTime = std::chrono::high_resolution_clock::now();
                int shareCount = 0;
                if (shareDiscoverer.DiscoverShares(&shareCount)) {
                    auto endTime = std::chrono::high_resolution_clock::now();
                    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
                    std::cout << "SMB share discovery completed in " << duration << "ms" << std::endl;
                    std::cout << "SMB share discovery completed successfully\n";

                    // Log successful share discovery with summary
                    LogEvent(
                        dbCtx,
                        Logging::Severity::INFO,
                        "SMBShareDiscovery",
                        "SMB share discovery completed successfully",
                        "",
                        0,
                        GetCurrentThreadId(),
                        "Discovered " + std::to_string(shareCount) + " shares",
                        dbCtx.inventoryID
                    );
                }
            }
        }

        // Record folder scan end time
        auto folderScanEndTime = std::chrono::high_resolution_clock::now();

        // ARCH-003 FIX: Commit any pending transaction from folder scanning
        // InsertFolderBatch uses transaction batching and may leave final batch uncommitted
        if (dbCtx.isInTransaction()) {
            std::cout << "\nCommitting pending transaction from folder scan..." << std::endl;
            if (!dbCtx.commitTransaction()) {
                std::cerr << "ERROR: Failed to commit folder scan transaction, attempting rollback" << std::endl;
                dbCtx.rollbackTransaction();
                LogEvent(
                    dbCtx,
                    Logging::Severity::ERR,
                    "Database",
                    "Failed to commit pending transaction after folder scan",
                    "",
                    0,
                    GetCurrentThreadId(),
                    "Transaction rolled back to ensure clean state",
                    dbCtx.inventoryID
                );
            } else {
                std::cout << "Folder scan transaction committed successfully" << std::endl;
            }
        }

        // ARCH-003 FIX: Double-check transaction state before ACL processing
        if (dbCtx.isInTransaction()) {
            std::cerr << "WARNING: Transaction still active after commit attempt, forcing rollback" << std::endl;
            dbCtx.rollbackTransaction();
            LogEvent(
                dbCtx,
                Logging::Severity::WARNING,
                "Database",
                "Forced rollback of persistent transaction before ACL processing",
                "",
                0,
                GetCurrentThreadId(),
                "Transaction state was inconsistent",
                dbCtx.inventoryID
            );
        }

        std::cout << "\n\nStarting ACE/ACL processing scan...\n";
        std::cout << "--------------------------------------------------\n";

        // Track ACL processing start time
        auto aclProcessingStartTime = std::chrono::high_resolution_clock::now();

        // Create ACL processor with reference to FolderIndex (no copy)
        AclProcessor aclProcessor(dbCtx, scanner.getFolderIndex(), threadCount);

        // Set starting ACL/ACE IDs for AllFixedDisks mode to ensure unique IDs across volumes
        if (parsedArgs.mode == ExecutionMode::AllFixedDisks && volumeIndex > 0) {
            aclProcessor.setNextAclId(nextAclId);
            aclProcessor.setNextAceId(nextAceId);
            std::cout << "Starting ACL ID: " << nextAclId << ", ACE ID: " << nextAceId << std::endl;
        }

        // Set the total folder count
        aclProcessor.SetTotalFolders(scanner.getFolderIndex().size());

        // Initialize SID lookup
        std::cout << "Initializing SID lookup...\n";
        aclProcessor.InitializeSidLookup();

        if (AppGlobals::DebugMode.load()) {
            AppGlobals::WriteDebug("[DEBUG] InitializeSidLookup completed successfully\n");
            AppGlobals::WriteDebug("[DEBUG] About to call forEachScannedFolder on " +
                                   std::to_string(scanner.getFolderIndex().size()) + " folders\n");
        }

        // Process folders - ONLY scanned folders, not ancestors
        // This prevents ACL processing for ancestor folders (like drive roots) that were
        // indexed for hierarchy but never actually scanned/enumerated
        //std::cout << "Processing ACLs...\n";
        try {
            if (AppGlobals::DebugMode.load()) {
                AppGlobals::WriteDebug("[DEBUG] Entering forEachScannedFolder try block\n");
            }

            static std::atomic<int> folderCount{0};
            static auto lastDebugTime = std::chrono::steady_clock::now();

            scanner.forEachScannedFolder([&](const std::wstring& path, int64_t localFolderId) {
                try {
                    // Debug output every 10,000 folders
                    if (AppGlobals::DebugMode.load()) {
                        int count = ++folderCount;
                        if (count == 1) {
                            AppGlobals::WriteDebug("[DEBUG] Processing first folder in lambda\n");
                        } else if (count % 10000 == 0) {
                            auto now = std::chrono::steady_clock::now();
                            auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - lastDebugTime).count();
                            AppGlobals::WriteDebug("[DEBUG] Processed " + std::to_string(count) +
                                                   " folders (+" + std::to_string(elapsed) + "s)\n");
                            lastDebugTime = now;
                        }
                    }

                    aclProcessor.AddFolder(path, localFolderId);
                } catch (const std::exception& e) {
                    std::cerr << "Exception in folder processing callback: " << e.what() << std::endl;

                    // Log the error
                    LogEvent(
                        dbCtx,
                        Logging::Severity::ERR,
                        "FolderProcessing",
                        "Exception in folder processing callback",
                        "",
                        0,
                        GetCurrentThreadId(),
                        e.what(),
                        dbCtx.inventoryID
                    );
                }
            });

            if (AppGlobals::DebugMode.load()) {
                AppGlobals::WriteDebug("[DEBUG] forEachScannedFolder completed, total folders: " +
                                       std::to_string(folderCount.load()) + "\n");
                AppGlobals::WriteDebug("[DEBUG] Calling WaitForCompletion...\n");
            }

            // Wait for processing to complete
            //std::cout << "Waiting for ACL processing to complete...\n";
            aclProcessor.WaitForCompletion();

            if (AppGlobals::DebugMode.load()) {
                AppGlobals::WriteDebug("[DEBUG] WaitForCompletion returned\n");
            }

            // Record ACL processing end time
            auto aclProcessingEndTime = std::chrono::high_resolution_clock::now();

            std::cout << "\nACL/ACL processing summary";
            std::cout << "\n--------------------------------------------------\n";
            
            // Get individual statistics values
            const auto& stats = aclProcessor.GetStats();
            int64_t processedFolders = stats.processedFolders.load();
            int64_t failedFolders = stats.failedFolders.load();
            int64_t newSids = stats.newSids.load();
            int64_t totalAcls = stats.totalAcls.load();
            int64_t totalAces = stats.totalAces.load();
            int64_t skippedEmptySids = stats.skippedEmptySids.load();
            int64_t invalidSids = stats.invalidSids.load();
            int64_t sidConversionFailures = stats.sidConversionFailures.load();
            int64_t skippedUnsupportedAceTypes = stats.skippedUnsupportedAceTypes.load();

            std::cout << "Total folders processed : " << FormatNumberWithLocale(processedFolders) << "\n";
            std::cout << "Failed folders          : " << FormatNumberWithLocale(failedFolders) << "\n";
            std::cout << "New SIDs added          : " << FormatNumberWithLocale(newSids) << "\n";
            std::cout << "ACLs processed          : " << FormatNumberWithLocale(totalAcls) << "\n";
            std::cout << "ACEs processed          : " << FormatNumberWithLocale(totalAces) << "\n";
            std::cout << "Skipped empty SIDs      : " << FormatNumberWithLocale(skippedEmptySids) << "\n";
            std::cout << "Invalid SIDs            : " << FormatNumberWithLocale(invalidSids) << "\n";
            std::cout << "SID conversion failures : " << FormatNumberWithLocale(sidConversionFailures) << "\n";
            std::cout << "Unsupported ACE types   : " << FormatNumberWithLocale(skippedUnsupportedAceTypes) << "\n";
            std::cout << "--------------------------------------------------\n";

            // Write ACL processing summary to debug file
            AppGlobals::WriteDebug("\nACL/ACE processing summary\n");
            AppGlobals::WriteDebug("--------------------------------------------------\n");
            AppGlobals::WriteDebug("Total folders processed : " + FormatNumberWithLocale(processedFolders) + "\n");
            AppGlobals::WriteDebug("Failed folders          : " + FormatNumberWithLocale(failedFolders) + "\n");
            AppGlobals::WriteDebug("New SIDs added          : " + FormatNumberWithLocale(newSids) + "\n");
            AppGlobals::WriteDebug("ACLs processed          : " + FormatNumberWithLocale(totalAcls) + "\n");
            AppGlobals::WriteDebug("ACEs processed          : " + FormatNumberWithLocale(totalAces) + "\n");
            AppGlobals::WriteDebug("Skipped empty SIDs      : " + FormatNumberWithLocale(skippedEmptySids) + "\n");
            AppGlobals::WriteDebug("Invalid SIDs            : " + FormatNumberWithLocale(invalidSids) + "\n");
            AppGlobals::WriteDebug("SID conversion failures : " + FormatNumberWithLocale(sidConversionFailures) + "\n");
            AppGlobals::WriteDebug("Unsupported ACE types   : " + FormatNumberWithLocale(skippedUnsupportedAceTypes) + "\n");
            AppGlobals::WriteDebug("--------------------------------------------------\n");

            // Log completion
            LogEvent(
                dbCtx,
                Logging::Severity::INFO,
                "ACLProcessing",
                "ACL processing completed successfully",
                "",
                0,
                GetCurrentThreadId(),
                "Processing complete",
                dbCtx.inventoryID
            );
            
            // Get end time and calculate statistics
            auto endTime = std::chrono::system_clock::now();

            // Get statistics from both the scanner and ACL processor
            const auto& scannerStats = scanner.getStats();

            // Combine statistics from both sources
            int64_t foldersProcessed = aclProcessor.GetStats().processedFolders;  // Use int64_t instead of int
            int foldersWithErrors = static_cast<int>(scannerStats.foldersWithErrors.load() + scannerStats.accessDeniedFolders.load());
            int peakQueueSize = static_cast<int>(scannerStats.peakQueueSize.load());  // FIX: Explicit cast from size_t

            // Use the tracked peak memory usage
            int peakMemoryUsageMB = AppGlobals::PeakMemoryUsageMB.load();

            // For AllFixedDisks mode, accumulate stats across volumes
            // UpdateCollectionInfo will be called once after all volumes are scanned
            if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
                cumulativeFoldersProcessed += foldersProcessed;
                cumulativeFoldersWithErrors += foldersWithErrors;
                if (peakQueueSize > maxPeakQueueSize) maxPeakQueueSize = peakQueueSize;
                if (peakMemoryUsageMB > maxPeakMemoryUsageMB) maxPeakMemoryUsageMB = peakMemoryUsageMB;

                std::cout << "\nVolume statistics: " << foldersProcessed << " folders, "
                          << foldersWithErrors << " errors" << std::endl;
                std::cout << "Cumulative total: " << cumulativeFoldersProcessed << " folders, "
                          << cumulativeFoldersWithErrors << " errors" << std::endl;
            } else {
                // Normal mode: Update collection info immediately
                if (!UpdateCollectionInfo(
                    dbCtx,                  // Database context
                    dbCtx.inventoryID,      // Inventory ID
                    endTime,                // End time
                    static_cast<int>(foldersProcessed),  // Explicit cast to int
                    foldersWithErrors,      // Folders with errors
                    peakQueueSize,          // Peak queue size
                    peakMemoryUsageMB       // Peak memory usage in MB
                )) {
                    std::cerr << "Warning: Failed to update collection info with statistics" << std::endl;
                    LogEvent(
                        dbCtx,
                        Logging::Severity::WARNING,
                        "Main",
                        "Failed to update collection info with statistics",
                        "",
                        0,
                        GetCurrentThreadId(),
                        "",
                        dbCtx.inventoryID
                    );
                } else {
                    std::cout << "\nCollection statistics updated in database" << std::endl;
                    LogEvent(
                        dbCtx,
                        Logging::Severity::INFO,
                        "Main",
                        "Collection statistics updated in database",
                        "",
                        0,
                        GetCurrentThreadId(),
                        "Processed " + std::to_string(foldersProcessed) + " folders with " +
                        std::to_string(foldersWithErrors) + " errors, peak memory: " +
                        std::to_string(peakMemoryUsageMB) + " MB",
                        dbCtx.inventoryID
                    );
                }
            }

            // Calculate and display timing breakdown
            auto overallEndTime = std::chrono::high_resolution_clock::now();
            auto folderScanDuration = std::chrono::duration_cast<std::chrono::milliseconds>(folderScanEndTime - folderScanStartTime).count();
            auto aclProcessingDuration = std::chrono::duration_cast<std::chrono::milliseconds>(aclProcessingEndTime - aclProcessingStartTime).count();
            auto totalDuration = std::chrono::duration_cast<std::chrono::milliseconds>(overallEndTime - overallStartTime).count();

            // Database write time is implicit (total - scan - acl)
            auto databaseWriteDuration = totalDuration - folderScanDuration - aclProcessingDuration;

            // Helper lambda to format duration as Xm Ys
            auto formatDuration = [](int64_t milliseconds) -> std::string {
                int64_t totalSeconds = milliseconds / 1000;
                int64_t minutes = totalSeconds / 60;
                int64_t seconds = totalSeconds % 60;

                if (minutes > 0) {
                    return std::to_string(minutes) + "m " + std::to_string(seconds) + "s";
                } else {
                    return std::to_string(seconds) + "s";
                }
            };

            std::cout << "\n\nTiming Breakdown:\n";
            std::cout << "--------------------------------------------------\n";
            std::cout << "  Folder Scan Time    : " << formatDuration(folderScanDuration) << "\n";
            std::cout << "  ACL Processing Time : " << formatDuration(aclProcessingDuration) << "\n";
            std::cout << "  Database Write Time : " << formatDuration(databaseWriteDuration) << "\n";
            std::cout << "  Total Runtime       : " << formatDuration(totalDuration) << "\n";
            std::cout << "--------------------------------------------------\n";

            // Memory monitor will be stopped automatically by ShouldStopGuard destructor

            // ARCH-003 FIX: Ensure no pending transaction before SMB share collection
            // InsertFolderBatch/AclProcessor start transactions but may not commit final batch
            // If the final batch is smaller than BATCH_SIZE, transaction remains open causing deadlock
            if (AppGlobals::DebugMode.load()) {
                std::cout << "[DEBUG] ARCH-003 Check #2: Checking transaction state before SMB share collection\n";
                std::cout << "[DEBUG] Transaction active: " << (dbCtx.isInTransaction() ? "YES" : "NO") << "\n";
            }

            if (dbCtx.isInTransaction()) {
                std::cout << "\nCommitting pending database transaction before SMB share collection..." << std::endl;
                if (!dbCtx.commitTransaction()) {
                    std::cerr << "ERROR: Failed to commit pending transaction, attempting rollback" << std::endl;
                    dbCtx.rollbackTransaction();  // Ensure clean state

                    if (AppGlobals::DebugMode.load()) {
                        std::cerr << "[DEBUG] Transaction commit failed, rollback completed\n";
                        std::cerr << "[DEBUG] Transaction state after rollback: "
                                  << (dbCtx.isInTransaction() ? "STILL ACTIVE" : "CLEARED") << "\n";
                    }

                    LogEvent(
                        dbCtx,
                        Logging::Severity::ERR,
                        "Database",
                        "Failed to commit pending transaction before SMB share collection",
                        "",
                        0,
                        GetCurrentThreadId(),
                        "Transaction rolled back to ensure clean state",
                        dbCtx.inventoryID
                    );
                } else {
                    std::cout << "Pending transaction committed successfully" << std::endl;
                    if (AppGlobals::DebugMode.load()) {
                        std::cout << "[DEBUG] Transaction committed successfully\n";
                    }
                }
            } else {
                if (AppGlobals::DebugMode.load()) {
                    std::cout << "[DEBUG] No active transaction before SMB share collection\n";
                }
            }

            // ARCH-003 FIX: Double-check transaction state
            // On some Windows versions, transaction state may be inconsistent
            if (dbCtx.isInTransaction()) {
                std::cerr << "WARNING: Transaction still active after commit attempt, forcing rollback" << std::endl;
                dbCtx.rollbackTransaction();

                if (AppGlobals::DebugMode.load()) {
                    std::cerr << "[DEBUG] Double-check found active transaction, rollback forced\n";
                    std::cerr << "[DEBUG] Transaction state after forced rollback: "
                              << (dbCtx.isInTransaction() ? "STILL ACTIVE" : "CLEARED") << "\n";
                }

                LogEvent(
                    dbCtx,
                    Logging::Severity::WARNING,
                    "Database",
                    "Forced rollback of persistent transaction before SMB share collection",
                    "",
                    0,
                    GetCurrentThreadId(),
                    "Transaction state was inconsistent",
                    dbCtx.inventoryID
                );
            } else {
                if (AppGlobals::DebugMode.load()) {
                    std::cout << "[DEBUG] Double-check passed: No active transaction\n";
                }
            }

            // Now collect SMB shares (AFTER ACL processing)
            // For AllFixedDisks mode, only run on first volume (shares are system-wide)
            if (shouldRunSmbOperations) {
                std::cout << "\n\nCollecting SMB share information...\n";
                std::cout << "--------------------------------------------------\n";

                if (AppGlobals::DebugMode.load()) {
                    std::cout << "[DEBUG] About to start SMB share collection\n";
                    std::cout << "[DEBUG] Transaction state before SMB collection: "
                              << (dbCtx.isInTransaction() ? "ACTIVE" : "NONE") << "\n";
                }

                if (!remoteComputer.empty()) {
                    std::cout << "SMB share information not collected. Remote computer scan detected." << std::endl;

                    // Log skipped share collection
                    LogEvent(
                        dbCtx,
                        Logging::Severity::WARNING,
                        "SMBShareCollection",
                        "SMB share collection skipped",
                        "",
                        0,
                        GetCurrentThreadId(),
                        "Remote computer scan - local SMB share info not applicable",
                        dbCtx.inventoryID
                    );
                } else {
                    try {
                        if (AppGlobals::DebugMode.load()) {
                            std::cout << "[DEBUG] Entering SMB share collection try block\n";
                            std::cout << "[DEBUG] Creating SMBShareCollector...\n";
                        }

                        // Create and run the SMB share collector
                        SMBShareCollector shareCollector(dbCtx, const_cast<FolderIndex&>(scanner.getFolderIndex()));

                        if (AppGlobals::DebugMode.load()) {
                            std::cout << "[DEBUG] SMBShareCollector created successfully\n";
                            std::cout << "[DEBUG] Transaction state after constructor: "
                                      << (dbCtx.isInTransaction() ? "ACTIVE" : "NONE") << "\n";
                            std::cout << "[DEBUG] Calling CollectShares()...\n";
                        }

                        // Collect share information
                        auto startTime = std::chrono::high_resolution_clock::now();
                        if (shareCollector.CollectShares()) {
                            auto endTime = std::chrono::high_resolution_clock::now();
                            auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
                            std::cout << "SMB share collection completed in " << duration << "ms" << std::endl;
                            int shareCount = shareCollector.GetShareCount();
                            int shareAccessCount = shareCollector.GetShareAccessCount();
                            std::cout << "Collected " << shareCount << " shares and "
                                      << shareAccessCount << " share permissions\n";

                            // Log successful share collection with summary
                            LogEvent(
                                dbCtx,
                                Logging::Severity::INFO,
                                "SMBShareCollection",
                                "SMB share collection completed successfully",
                                "",
                                0,
                                GetCurrentThreadId(),
                                "Collected " + std::to_string(shareCount) + " shares and " +
                                std::to_string(shareAccessCount) + " share permissions",
                                dbCtx.inventoryID
                            );
                        } else {
                            std::cerr << "Failed to collect SMB shares\n";

                            // Log share collection failure
                            LogEvent(
                                dbCtx,
                                Logging::Severity::ERR,
                                "SMBShareCollection",
                                "Failed to collect SMB shares",
                                "",
                                0,
                                GetCurrentThreadId(),
                                "Share collection operation failed",
                                dbCtx.inventoryID
                            );
                        }
                    } catch (const std::exception& e) {
                        std::cerr << "Exception during SMB share collection: " << e.what() << std::endl;

                        if (AppGlobals::DebugMode.load()) {
                            std::cerr << "[DEBUG] Exception caught in SMB share collection\n";
                            std::cerr << "[DEBUG] Exception type: " << typeid(e).name() << "\n";
                            std::cerr << "[DEBUG] Exception message: " << e.what() << "\n";
                            std::cerr << "[DEBUG] Transaction state in catch block: "
                                      << (dbCtx.isInTransaction() ? "ACTIVE" : "NONE") << "\n";

                            // Try to force rollback if transaction is active
                            if (dbCtx.isInTransaction()) {
                                std::cerr << "[DEBUG] Forcing rollback of active transaction in catch block\n";
                                dbCtx.rollbackTransaction();
                            }
                        }

                        // Log the error
                        LogEvent(
                            dbCtx,
                            Logging::Severity::ERR,
                            "SMBShareCollection",
                            "Exception during SMB share collection",
                            "",
                            0,
                            GetCurrentThreadId(),
                            e.what(),
                            dbCtx.inventoryID
                        );
                    }
                }
            }
            
        } catch (const std::exception& e) {
            std::cerr << "Exception during ACL processing: " << e.what() << std::endl;

            // Log the error
            LogEvent(
                dbCtx,
                Logging::Severity::ERR,
                "ACLProcessing",
                "Exception during ACL processing",
                "",
                0,
                GetCurrentThreadId(),
                e.what(),
                dbCtx.inventoryID
            );

            // For AllFixedDisks mode, continue to next volume
            if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
                totalVolumeErrors++;
                std::cerr << "Continuing to next volume..." << std::endl;
                continue;  // Continue to next volume in the loop
            }
            return 1;
        }

        // Update the next IDs for the next volume scan
        // This ensures unique IDs across all volumes in AllFixedDisks mode
        nextFolderId = scanner.getFolderIndex().getNextId();
        nextAclId = aclProcessor.getNextAclId();
        nextAceId = aclProcessor.getNextAceId();
        if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
            std::cout << "Volume scan complete. Next folder ID: " << nextFolderId
                      << ", ACL ID: " << nextAclId << ", ACE ID: " << nextAceId << std::endl;
        }

    } catch (const std::exception& e) {
        std::cerr << "Exception during folder scanning: " << e.what() << std::endl;

        // Log the error
        LogEvent(
            dbCtx,
            Logging::Severity::ERR,
            "FolderScanning",
            "Exception during folder scanning",
            "",
            0,
            GetCurrentThreadId(),
            e.what(),
            dbCtx.inventoryID
        );

        // For AllFixedDisks mode, continue to next volume
        if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
            totalVolumeErrors++;
            std::cerr << "Continuing to next volume..." << std::endl;
            continue;  // Continue to next volume in the loop
        }
        return 1;
    }

        // Track successful volume scan
        totalVolumesScanned++;

    }  // End of volume scanning loop

    // For AllFixedDisks mode, update collection info with cumulative stats after all volumes are scanned
    if (parsedArgs.mode == ExecutionMode::AllFixedDisks) {
        auto endTime = std::chrono::system_clock::now();

        if (!UpdateCollectionInfo(
            dbCtx,
            dbCtx.inventoryID,
            endTime,
            static_cast<int>(cumulativeFoldersProcessed),
            cumulativeFoldersWithErrors,
            maxPeakQueueSize,
            maxPeakMemoryUsageMB
        )) {
            std::cerr << "Warning: Failed to update collection info with cumulative statistics" << std::endl;
            LogEvent(
                dbCtx,
                Logging::Severity::WARNING,
                "Main",
                "Failed to update collection info with cumulative statistics",
                "",
                0,
                GetCurrentThreadId(),
                "",
                dbCtx.inventoryID
            );
        } else {
            std::cout << "\nCumulative collection statistics updated in database" << std::endl;
            LogEvent(
                dbCtx,
                Logging::Severity::INFO,
                "Main",
                "Cumulative collection statistics updated in database",
                "",
                0,
                GetCurrentThreadId(),
                "Processed " + std::to_string(cumulativeFoldersProcessed) + " folders across " +
                std::to_string(totalVolumesScanned) + " volumes with " +
                std::to_string(cumulativeFoldersWithErrors) + " errors, peak memory: " +
                std::to_string(maxPeakMemoryUsageMB) + " MB",
                dbCtx.inventoryID
            );
        }

        std::cout << "\n================================================\n";
        std::cout << "ALL FIXED DISKS SCAN COMPLETE\n";
        std::cout << "================================================\n";
        std::cout << "Total volumes scanned : " << totalVolumesScanned << "\n";
        std::cout << "Volumes with errors   : " << totalVolumeErrors << "\n";
        std::cout << "Total folders processed: " << cumulativeFoldersProcessed << "\n";
        std::cout << "Total folders w/errors: " << cumulativeFoldersWithErrors << "\n";
        std::cout << "Peak memory usage     : " << maxPeakMemoryUsageMB << " MB\n";
        std::cout << "================================================\n\n";
    }

    // Close the database connection before compression
    // This ensures the database file is not locked when we try to zip it
    std::cout << "Closing database connection...\n";
    dbCtx.insertFolderStmt.reset();  // Release prepared statements first
    dbCtx.stmtCache_.clear();        // Clear statement cache
    dbCtx.db.reset();                // Close the database connection
    std::cout << "Database connection closed\n";

    // Compress the database file and delete the original (unless --NoZip specified)
    CompressAndCleanupDatabase(dbPath, parsedArgs.noZip);

    std::cout << "\nProcessing completed successfully!\n\n\n";

    // Write completion message and close debug file
    AppGlobals::WriteDebug("\nProcessing completed successfully!\n\n\n");
    AppGlobals::CloseDebugFile();

    return 0;
}
