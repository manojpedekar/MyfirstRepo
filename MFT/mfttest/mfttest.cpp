// mfttest.cpp - Filesystem Enumeration Test
// Producer-Consumer architecture for high-performance directory scanning
// Compatible with Windows Server 2008 R2 and newer (64-bit only)
//
// Usage:
//   mfttest.exe [drive] [min_size_mb] [num_threads]
//   mfttest.exe C 100 4
//

#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <io.h>
#include <fcntl.h>
#include <psapi.h>

#pragma comment(lib, "shell32.lib")

#pragma comment(lib, "psapi.lib")

// ============================================================================
// Configuration
// ============================================================================

static const size_t MAX_PATH_LENGTH = 32768;
static const size_t QUEUE_INITIAL_CAPACITY = 10000;
static const size_t FILE_LIST_INITIAL_CAPACITY = 10000;
static const DWORD PROGRESS_INTERVAL = 100000;

// ============================================================================
// Thread-Safe Queue (Lock-based for 2008R2 compatibility)
// ============================================================================

struct PathQueue {
    WCHAR** items;
    size_t capacity;
    size_t count;
    size_t head;
    size_t tail;
    CRITICAL_SECTION lock;
    HANDLE itemAvailable;     // Event signaled when items available
    HANDLE spaceAvailable;    // Event signaled when space available
    volatile LONG producersDone;
    volatile LONG activeProducers;
};

static void PathQueue_Init(PathQueue* q, size_t initialCapacity) {
    q->capacity = initialCapacity;
    q->items = (WCHAR**)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                   sizeof(WCHAR*) * initialCapacity);
    q->count = 0;
    q->head = 0;
    q->tail = 0;
    q->producersDone = 0;
    q->activeProducers = 0;
    InitializeCriticalSection(&q->lock);
    q->itemAvailable = CreateEventW(NULL, TRUE, FALSE, NULL);  // Manual reset
    q->spaceAvailable = CreateEventW(NULL, TRUE, TRUE, NULL);  // Manual reset, initially signaled
}

static void PathQueue_Destroy(PathQueue* q) {
    // Free any remaining paths
    for (size_t i = 0; i < q->count; i++) {
        size_t idx = (q->head + i) % q->capacity;
        if (q->items[idx]) {
            HeapFree(GetProcessHeap(), 0, q->items[idx]);
        }
    }
    HeapFree(GetProcessHeap(), 0, q->items);
    DeleteCriticalSection(&q->lock);
    CloseHandle(q->itemAvailable);
    CloseHandle(q->spaceAvailable);
}

static void PathQueue_Grow(PathQueue* q) {
    size_t newCapacity = q->capacity * 2;
    WCHAR** newItems = (WCHAR**)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                          sizeof(WCHAR*) * newCapacity);

    // Copy items to new buffer (linearize the circular buffer)
    for (size_t i = 0; i < q->count; i++) {
        size_t oldIdx = (q->head + i) % q->capacity;
        newItems[i] = q->items[oldIdx];
    }

    HeapFree(GetProcessHeap(), 0, q->items);
    q->items = newItems;
    q->capacity = newCapacity;
    q->head = 0;
    q->tail = q->count;
}

static BOOL PathQueue_Push(PathQueue* q, const WCHAR* path) {
    EnterCriticalSection(&q->lock);

    // Grow if needed
    if (q->count >= q->capacity) {
        PathQueue_Grow(q);
    }

    // Allocate and copy path
    size_t len = wcslen(path) + 1;
    WCHAR* copy = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, len * sizeof(WCHAR));
    if (!copy) {
        LeaveCriticalSection(&q->lock);
        return FALSE;
    }
    wcscpy(copy, path);

    q->items[q->tail] = copy;
    q->tail = (q->tail + 1) % q->capacity;
    q->count++;

    SetEvent(q->itemAvailable);

    LeaveCriticalSection(&q->lock);
    return TRUE;
}

// Returns NULL if queue is empty and all work is done
static WCHAR* PathQueue_Pop(PathQueue* q) {
    while (TRUE) {
        EnterCriticalSection(&q->lock);

        if (q->count > 0) {
            WCHAR* item = q->items[q->head];
            q->items[q->head] = NULL;
            q->head = (q->head + 1) % q->capacity;
            q->count--;
            q->activeProducers++;  // Mark this worker as actively processing

            if (q->count == 0) {
                ResetEvent(q->itemAvailable);
            }

            LeaveCriticalSection(&q->lock);
            return item;
        }

        // Queue is empty - check if all workers are idle (no more work coming)
        if (q->activeProducers == 0) {
            // No items and no workers processing = all done
            q->producersDone = 1;
            SetEvent(q->itemAvailable);  // Wake up any other waiting workers
            LeaveCriticalSection(&q->lock);
            return NULL;
        }

        ResetEvent(q->itemAvailable);
        LeaveCriticalSection(&q->lock);

        // Wait for items or completion
        WaitForSingleObject(q->itemAvailable, 100);
    }
}

// Called when worker finishes processing a directory
static void PathQueue_WorkerDone(PathQueue* q) {
    EnterCriticalSection(&q->lock);
    q->activeProducers--;
    if (q->activeProducers == 0 && q->count == 0) {
        SetEvent(q->itemAvailable);  // Wake up waiting workers
    }
    LeaveCriticalSection(&q->lock);
}

// ============================================================================
// File Info Structure
// ============================================================================

struct FileInfo {
    WCHAR* path;
    ULONGLONG size;
    FILETIME modifiedTime;
    FILETIME accessedTime;
};

struct FileList {
    FileInfo* items;
    size_t capacity;
    size_t count;
    CRITICAL_SECTION lock;
};

static void FileList_Init(FileList* list, size_t initialCapacity) {
    list->capacity = initialCapacity;
    list->items = (FileInfo*)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                       sizeof(FileInfo) * initialCapacity);
    list->count = 0;
    InitializeCriticalSection(&list->lock);
}

static void FileList_Destroy(FileList* list) {
    for (size_t i = 0; i < list->count; i++) {
        if (list->items[i].path) {
            HeapFree(GetProcessHeap(), 0, list->items[i].path);
        }
    }
    HeapFree(GetProcessHeap(), 0, list->items);
    DeleteCriticalSection(&list->lock);
}

static void FileList_Add(FileList* list, const WCHAR* path, ULONGLONG size,
                         const FILETIME* mtime, const FILETIME* atime) {
    EnterCriticalSection(&list->lock);

    // Grow if needed
    if (list->count >= list->capacity) {
        size_t newCapacity = list->capacity * 2;
        FileInfo* newItems = (FileInfo*)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                                  sizeof(FileInfo) * newCapacity);
        memcpy(newItems, list->items, sizeof(FileInfo) * list->count);
        HeapFree(GetProcessHeap(), 0, list->items);
        list->items = newItems;
        list->capacity = newCapacity;
    }

    // Copy path
    size_t len = wcslen(path) + 1;
    list->items[list->count].path = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, len * sizeof(WCHAR));
    wcscpy(list->items[list->count].path, path);
    list->items[list->count].size = size;
    list->items[list->count].modifiedTime = *mtime;
    list->items[list->count].accessedTime = *atime;
    list->count++;

    LeaveCriticalSection(&list->lock);
}

// ============================================================================
// Statistics (Thread-safe using Interlocked operations)
// ============================================================================

static const size_t MAX_ERROR_LOG = 100;  // Store first N errors

struct ErrorEntry {
    WCHAR* path;
    DWORD errorCode;
};

struct ScanStats {
    volatile LONGLONG totalEntries;
    volatile LONGLONG fileCount;
    volatile LONGLONG dirCount;
    volatile LONGLONG matchingFiles;
    volatile LONGLONG totalMatchedSize;
    volatile LONGLONG errors;

    // Error logging
    ErrorEntry errorLog[MAX_ERROR_LOG];
    volatile LONG errorLogCount;
    CRITICAL_SECTION errorLock;
};

static void Stats_Init(ScanStats* stats) {
    stats->totalEntries = 0;
    stats->fileCount = 0;
    stats->dirCount = 0;
    stats->matchingFiles = 0;
    stats->totalMatchedSize = 0;
    stats->errors = 0;
    stats->errorLogCount = 0;
    memset(stats->errorLog, 0, sizeof(stats->errorLog));
    InitializeCriticalSection(&stats->errorLock);
}

static void Stats_Destroy(ScanStats* stats) {
    for (size_t i = 0; i < MAX_ERROR_LOG; i++) {
        if (stats->errorLog[i].path) {
            HeapFree(GetProcessHeap(), 0, stats->errorLog[i].path);
        }
    }
    DeleteCriticalSection(&stats->errorLock);
}

static void Stats_LogError(ScanStats* stats, const WCHAR* path, DWORD errorCode) {
    InterlockedIncrement64(&stats->errors);

    // Only log first MAX_ERROR_LOG errors
    LONG idx = InterlockedIncrement(&stats->errorLogCount) - 1;
    if (idx < MAX_ERROR_LOG) {
        EnterCriticalSection(&stats->errorLock);
        size_t len = wcslen(path) + 1;
        stats->errorLog[idx].path = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, len * sizeof(WCHAR));
        if (stats->errorLog[idx].path) {
            wcscpy(stats->errorLog[idx].path, path);
        }
        stats->errorLog[idx].errorCode = errorCode;
        LeaveCriticalSection(&stats->errorLock);
    }
}

// ============================================================================
// Worker Context
// ============================================================================

struct WorkerContext {
    PathQueue* queue;
    FileList* files;
    ScanStats* stats;
    ULONGLONG minSizeBytes;
    volatile LONG* runningWorkers;
    DWORD workerId;
};

// ============================================================================
// Utility Functions
// ============================================================================

static void FormatSize(ULONGLONG bytes, WCHAR* buffer, size_t bufferSize) {
    const WCHAR* units[] = { L"B", L"KB", L"MB", L"GB", L"TB" };
    double size = (double)bytes;
    int unitIndex = 0;

    while (size >= 1024.0 && unitIndex < 4) {
        size /= 1024.0;
        unitIndex++;
    }

    swprintf(buffer, bufferSize, L"%.1f %s", size, units[unitIndex]);
}

static SIZE_T GetMemoryUsageMB() {
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) {
        return pmc.WorkingSetSize / (1024 * 1024);
    }
    return 0;
}

static double GetElapsedSeconds(LARGE_INTEGER start, LARGE_INTEGER freq) {
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return (double)(now.QuadPart - start.QuadPart) / (double)freq.QuadPart;
}

// ============================================================================
// Directory Scanning Worker
// ============================================================================

static DWORD WINAPI ScanWorker(LPVOID param) {
    WorkerContext* ctx = (WorkerContext*)param;
    WCHAR searchPath[MAX_PATH_LENGTH];
    WCHAR fullPath[MAX_PATH_LENGTH];
    WIN32_FIND_DATAW findData;

    while (TRUE) {
        // Get next directory to process (also marks us as active)
        WCHAR* dirPath = PathQueue_Pop(ctx->queue);
        if (!dirPath) {
            break;  // No more work
        }

        // Build search pattern
        size_t dirLen = wcslen(dirPath);
        if (dirLen > MAX_PATH_LENGTH - 10) {
            Stats_LogError(ctx->stats, dirPath, ERROR_BUFFER_OVERFLOW);
            HeapFree(GetProcessHeap(), 0, dirPath);
            PathQueue_WorkerDone(ctx->queue);
            continue;
        }

        wcscpy(searchPath, dirPath);
        if (dirPath[dirLen - 1] != L'\\') {
            wcscat(searchPath, L"\\");
        }
        wcscat(searchPath, L"*");

        // Enumerate directory
        HANDLE hFind = FindFirstFileW(searchPath, &findData);
        if (hFind == INVALID_HANDLE_VALUE) {
            DWORD err = GetLastError();
            Stats_LogError(ctx->stats, dirPath, err);
            HeapFree(GetProcessHeap(), 0, dirPath);
            PathQueue_WorkerDone(ctx->queue);
            continue;
        }

        do {
            // Skip . and ..
            if (wcscmp(findData.cFileName, L".") == 0 ||
                wcscmp(findData.cFileName, L"..") == 0) {
                continue;
            }

            InterlockedIncrement64(&ctx->stats->totalEntries);

            // Build full path
            wcscpy(fullPath, dirPath);
            if (dirPath[dirLen - 1] != L'\\') {
                wcscat(fullPath, L"\\");
            }
            wcscat(fullPath, findData.cFileName);

            BOOL isDir = (findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
            BOOL isReparse = (findData.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;

            if (isDir) {
                InterlockedIncrement64(&ctx->stats->dirCount);

                // Queue subdirectory for processing (skip reparse points to avoid loops)
                if (!isReparse) {
                    PathQueue_Push(ctx->queue, fullPath);
                }
            } else {
                InterlockedIncrement64(&ctx->stats->fileCount);

                // Check file size
                ULONGLONG fileSize = ((ULONGLONG)findData.nFileSizeHigh << 32) |
                                     findData.nFileSizeLow;

                if (fileSize >= ctx->minSizeBytes) {
                    InterlockedIncrement64(&ctx->stats->matchingFiles);
                    InterlockedAdd64(&ctx->stats->totalMatchedSize, (LONGLONG)fileSize);

                    FileList_Add(ctx->files, fullPath, fileSize,
                                &findData.ftLastWriteTime, &findData.ftLastAccessTime);
                }
            }

        } while (FindNextFileW(hFind, &findData));

        FindClose(hFind);
        HeapFree(GetProcessHeap(), 0, dirPath);
        PathQueue_WorkerDone(ctx->queue);  // Mark this directory as done
    }

    InterlockedDecrement(ctx->runningWorkers);
    return 0;
}

// ============================================================================
// Progress Reporter
// ============================================================================

struct ProgressContext {
    ScanStats* stats;
    LARGE_INTEGER startTime;
    LARGE_INTEGER freq;
    volatile LONG* running;
};

static DWORD WINAPI ProgressWorker(LPVOID param) {
    ProgressContext* ctx = (ProgressContext*)param;
    LONGLONG lastTotal = 0;

    while (*ctx->running) {
        Sleep(1000);  // Update every second

        LONGLONG total = ctx->stats->totalEntries;
        if (total - lastTotal >= PROGRESS_INTERVAL ||
            (total != lastTotal && total % PROGRESS_INTERVAL < (total - lastTotal))) {

            double elapsed = GetElapsedSeconds(ctx->startTime, ctx->freq);
            double rate = (elapsed > 0) ? (double)total / elapsed : 0;
            SIZE_T memMB = GetMemoryUsageMB();

            wprintf(L"  Processed %lld entries (%.0f/sec, %zu MB RAM, %lld files matched)\n",
                    total, rate, memMB, ctx->stats->matchingFiles);

            lastTotal = (total / PROGRESS_INTERVAL) * PROGRESS_INTERVAL;
        }
    }

    return 0;
}

// ============================================================================
// Comparison function for sorting files
// ============================================================================

static int CompareFilesBySize(const void* a, const void* b) {
    const FileInfo* fa = (const FileInfo*)a;
    const FileInfo* fb = (const FileInfo*)b;

    if (fb->size > fa->size) return 1;
    if (fb->size < fa->size) return -1;
    return 0;
}

// Get error message for Windows error code
static const WCHAR* GetErrorDescription(DWORD errorCode) {
    switch (errorCode) {
        case ERROR_ACCESS_DENIED:       return L"Access denied";
        case ERROR_PATH_NOT_FOUND:      return L"Path not found";
        case ERROR_FILE_NOT_FOUND:      return L"File not found";
        case ERROR_SHARING_VIOLATION:   return L"Sharing violation";
        case ERROR_INVALID_NAME:        return L"Invalid name";
        case ERROR_BUFFER_OVERFLOW:     return L"Path too long";
        case ERROR_DIRECTORY:           return L"Invalid directory";
        case ERROR_NOT_READY:           return L"Device not ready";
        case ERROR_INVALID_PARAMETER:   return L"Invalid parameter";
        case ERROR_NO_MORE_FILES:       return L"No more files";
        default:                        return L"Unknown error";
    }
}

static void PrintErrors(ScanStats* stats) {
    if (stats->errors == 0) return;

    wprintf(L"\nErrors encountered:\n");
    wprintf(L"------------------------------------------------------------\n");

    LONG count = stats->errorLogCount;
    if (count > MAX_ERROR_LOG) count = MAX_ERROR_LOG;

    for (LONG i = 0; i < count; i++) {
        if (stats->errorLog[i].path) {
            const WCHAR* path = stats->errorLog[i].path;
            size_t pathLen = wcslen(path);
            DWORD err = stats->errorLog[i].errorCode;

            if (pathLen > 50) {
                wprintf(L"  [%lu] %s: ...%s\n", err, GetErrorDescription(err), path + pathLen - 47);
            } else {
                wprintf(L"  [%lu] %s: %s\n", err, GetErrorDescription(err), path);
            }
        }
    }

    if (stats->errors > MAX_ERROR_LOG) {
        wprintf(L"  ... and %lld more errors\n", stats->errors - MAX_ERROR_LOG);
    }
}

// ============================================================================
// Main Scan Function
// ============================================================================

static int ScanFilesystem(const WCHAR* rootPath, ULONGLONG minSizeBytes, DWORD numThreads) {
    wprintf(L"============================================================\n");
    wprintf(L"FILESYSTEM ENUMERATION TEST (C++)\n");
    wprintf(L"============================================================\n\n");

    wprintf(L"Scanning: %s\n", rootPath);
    wprintf(L"Threads: %lu\n", numThreads);

    WCHAR sizeStr[64];
    FormatSize(minSizeBytes, sizeStr, 64);
    wprintf(L"Minimum file size: %s\n", sizeStr);
    wprintf(L"------------------------------------------------------------\n");

    // Initialize structures
    PathQueue queue;
    PathQueue_Init(&queue, QUEUE_INITIAL_CAPACITY);

    FileList files;
    FileList_Init(&files, FILE_LIST_INITIAL_CAPACITY);

    ScanStats stats;
    Stats_Init(&stats);

    volatile LONG runningWorkers = (LONG)numThreads;
    volatile LONG progressRunning = 1;

    // Start timing
    LARGE_INTEGER startTime, freq;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&startTime);
    SIZE_T startMemory = GetMemoryUsageMB();

    // Seed the queue with root path
    PathQueue_Push(&queue, rootPath);

    // Create worker contexts
    WorkerContext* contexts = (WorkerContext*)HeapAlloc(GetProcessHeap(), 0,
                                                        sizeof(WorkerContext) * numThreads);
    HANDLE* threads = (HANDLE*)HeapAlloc(GetProcessHeap(), 0, sizeof(HANDLE) * numThreads);

    for (DWORD i = 0; i < numThreads; i++) {
        contexts[i].queue = &queue;
        contexts[i].files = &files;
        contexts[i].stats = &stats;
        contexts[i].minSizeBytes = minSizeBytes;
        contexts[i].runningWorkers = &runningWorkers;
        contexts[i].workerId = i;

        threads[i] = CreateThread(NULL, 0, ScanWorker, &contexts[i], 0, NULL);
    }

    // Start progress reporter
    ProgressContext progressCtx;
    progressCtx.stats = &stats;
    progressCtx.startTime = startTime;
    progressCtx.freq = freq;
    progressCtx.running = &progressRunning;
    HANDLE progressThread = CreateThread(NULL, 0, ProgressWorker, &progressCtx, 0, NULL);

    // Wait for all workers to complete
    WaitForMultipleObjects(numThreads, threads, TRUE, INFINITE);

    // Signal producers done
    queue.producersDone = 1;
    SetEvent(queue.itemAvailable);

    // Stop progress reporter
    progressRunning = 0;
    WaitForSingleObject(progressThread, INFINITE);
    CloseHandle(progressThread);

    // Calculate elapsed time
    double elapsed = GetElapsedSeconds(startTime, freq);
    SIZE_T endMemory = GetMemoryUsageMB();

    // Clean up threads
    for (DWORD i = 0; i < numThreads; i++) {
        CloseHandle(threads[i]);
    }
    HeapFree(GetProcessHeap(), 0, threads);
    HeapFree(GetProcessHeap(), 0, contexts);

    // Print summary
    wprintf(L"\n============================================================\n");
    wprintf(L"SCAN COMPLETE\n");
    wprintf(L"============================================================\n");
    wprintf(L"Drive:                  %s\n", rootPath);
    wprintf(L"Worker threads:         %lu\n", numThreads);
    wprintf(L"Total entries scanned:  %lld\n", stats.totalEntries);
    wprintf(L"  - Directories:        %lld\n", stats.dirCount);
    wprintf(L"  - Files:              %lld\n", stats.fileCount);
    wprintf(L"  - Errors/skipped:     %lld\n", stats.errors);
    wprintf(L"Files matching filter:  %lld\n", stats.matchingFiles);

    FormatSize((ULONGLONG)stats.totalMatchedSize, sizeStr, 64);
    wprintf(L"Total size (matched):   %s\n", sizeStr);

    wprintf(L"------------------------------------------------------------\n");
    wprintf(L"Elapsed time:           %.1f seconds\n", elapsed);

    double rate = (elapsed > 0) ? (double)stats.totalEntries / elapsed : 0;
    wprintf(L"Processing rate:        %.0f entries/sec\n", rate);
    wprintf(L"Memory used:            %zu MB\n", endMemory - startMemory);
    wprintf(L"============================================================\n");

    // Show top 10 largest files
    if (files.count > 0) {
        wprintf(L"\nTop 10 largest files:\n");
        wprintf(L"------------------------------------------------------------\n");

        // Sort files by size
        qsort(files.items, files.count, sizeof(FileInfo), CompareFilesBySize);

        size_t showCount = (files.count < 10) ? files.count : 10;
        for (size_t i = 0; i < showCount; i++) {
            FormatSize(files.items[i].size, sizeStr, 64);

            // Truncate path for display
            const WCHAR* path = files.items[i].path;
            size_t pathLen = wcslen(path);

            if (pathLen > 60) {
                wprintf(L"  %2zu. %10s  ...%s\n", i + 1, sizeStr, path + pathLen - 57);
            } else {
                wprintf(L"  %2zu. %10s  %s\n", i + 1, sizeStr, path);
            }
        }
    }

    // Show errors if any
    PrintErrors(&stats);

    // Cleanup
    PathQueue_Destroy(&queue);
    FileList_Destroy(&files);
    Stats_Destroy(&stats);

    return 0;
}

// ============================================================================
// Main Entry Point
// ============================================================================

int wmain(int argc, wchar_t* argv[]) {
    // Use UTF-8 output (compatible with console redirection)
    SetConsoleOutputCP(CP_UTF8);
    setvbuf(stdout, NULL, _IONBF, 0);  // Disable buffering for real-time output

    // Parse arguments
    WCHAR driveLetter = L'C';
    DWORD minSizeMB = 1;
    DWORD numThreads = 4;

    if (argc >= 2) {
        driveLetter = argv[1][0];
    }
    if (argc >= 3) {
        minSizeMB = (DWORD)_wtoi(argv[2]);
        if (minSizeMB == 0) minSizeMB = 1;
    }
    if (argc >= 4) {
        numThreads = (DWORD)_wtoi(argv[3]);
        if (numThreads == 0) numThreads = 1;
        if (numThreads > 64) numThreads = 64;
    }

    // Build root path
    WCHAR rootPath[16];
    swprintf(rootPath, 16, L"%c:\\", driveLetter);

    // Calculate minimum size in bytes
    ULONGLONG minSizeBytes = (ULONGLONG)minSizeMB * 1024ULL * 1024ULL;

    return ScanFilesystem(rootPath, minSizeBytes, numThreads);
}

// For linking with non-Unicode entry point
int main(int argc, char* argv[]) {
    // Convert to wide args and call wmain
    LPWSTR cmdLine = GetCommandLineW();
    int wargc;
    LPWSTR* wargv = CommandLineToArgvW(cmdLine, &wargc);

    int result = wmain(wargc, wargv);

    LocalFree(wargv);
    return result;
}
