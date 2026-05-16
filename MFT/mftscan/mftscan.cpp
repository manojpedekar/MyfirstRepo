// mftscan.cpp - NTFS Volume Scanner for Space Utilization Reporting
// Multi-threaded filesystem enumeration with CSV output
//
// Scans NTFS volumes and outputs file/directory metadata to CSV for
// downstream analysis and reporting. Designed for large Windows Server
// volumes with millions of files.
//
// Usage:
//   mftscan.exe [options] [volume...]
//   mftscan.exe C: D: --output results.csv
//   mftscan.exe --allVolumes --threads 8
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

static const size_t MAX_PATH_LEN       = 32768;
static const size_t QUEUE_INITIAL_CAP  = 10000;
static const DWORD  PROGRESS_INTERVAL  = 100000;
static const size_t MAX_VOLUMES        = 64;
static const DWORD  MAX_THREADS        = 64;
static const size_t CSV_WRITE_BUF_SIZE = 4 * 1024 * 1024;  // 4 MB write buffer
static const size_t ERR_WRITE_BUF_SIZE = 256 * 1024;        // 256 KB write buffer
static const size_t MAX_ERROR_LOG      = 100;               // Console error log cap
static const size_t ROW_BUF_SIZE       = 200 * 1024;        // Per-thread row buffer

static const char* TOOL_NAME    = "mftscan";
static const char* TOOL_VERSION = "1.0";

struct VolumeInfo {
    WCHAR devicePath[128];       // "\\?\Volume{GUID}" or "\\.\C:" — for raw access
    WCHAR mountPath[MAX_PATH];   // "C:\" or "E:\Data2\DSS\" — with trailing backslash
    WCHAR displayName[MAX_PATH]; // "C:" or "E:\Data2\DSS" — for CSV and console
};

struct VolumeScanResult {
    LONGLONG entryCount;
    LONGLONG directoryCount;
    LONGLONG fileCount;
    LONGLONG errorCount;
    double   durationSec;
};

// ============================================================================
// Thread-Safe Path Queue (circular buffer)
// ============================================================================

struct PathQueue {
    WCHAR** items;
    size_t capacity;
    size_t count;
    size_t head;
    size_t tail;
    CRITICAL_SECTION lock;
    HANDLE itemAvailable;
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
    q->itemAvailable = CreateEventW(NULL, TRUE, FALSE, NULL);
}

static void PathQueue_Destroy(PathQueue* q) {
    for (size_t i = 0; i < q->count; i++) {
        size_t idx = (q->head + i) % q->capacity;
        if (q->items[idx]) {
            HeapFree(GetProcessHeap(), 0, q->items[idx]);
        }
    }
    HeapFree(GetProcessHeap(), 0, q->items);
    DeleteCriticalSection(&q->lock);
    CloseHandle(q->itemAvailable);
}

static void PathQueue_Grow(PathQueue* q) {
    size_t newCapacity = q->capacity * 2;
    WCHAR** newItems = (WCHAR**)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                          sizeof(WCHAR*) * newCapacity);
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
    if (q->count >= q->capacity) {
        PathQueue_Grow(q);
    }
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

static WCHAR* PathQueue_Pop(PathQueue* q) {
    while (TRUE) {
        EnterCriticalSection(&q->lock);
        if (q->count > 0) {
            WCHAR* item = q->items[q->head];
            q->items[q->head] = NULL;
            q->head = (q->head + 1) % q->capacity;
            q->count--;
            q->activeProducers++;
            if (q->count == 0) ResetEvent(q->itemAvailable);
            LeaveCriticalSection(&q->lock);
            return item;
        }
        if (q->activeProducers == 0) {
            q->producersDone = 1;
            SetEvent(q->itemAvailable);
            LeaveCriticalSection(&q->lock);
            return NULL;
        }
        ResetEvent(q->itemAvailable);
        LeaveCriticalSection(&q->lock);
        WaitForSingleObject(q->itemAvailable, 100);
    }
}

static void PathQueue_WorkerDone(PathQueue* q) {
    EnterCriticalSection(&q->lock);
    q->activeProducers--;
    if (q->activeProducers == 0 && q->count == 0) {
        SetEvent(q->itemAvailable);
    }
    LeaveCriticalSection(&q->lock);
}

// ============================================================================
// Buffered File Writer (thread-safe)
// ============================================================================

struct BufferedWriter {
    HANDLE hFile;
    CRITICAL_SECTION lock;
    char* buffer;
    size_t bufferSize;
    size_t bufferPos;
    volatile LONGLONG rowsWritten;
};

static BOOL BufferedWriter_Init(BufferedWriter* w, const WCHAR* filePath,
                                size_t bufSize, BOOL writeBom) {
    memset(w, 0, sizeof(BufferedWriter));
    w->hFile = INVALID_HANDLE_VALUE;
    w->rowsWritten = 0;
    w->bufferSize = bufSize;
    w->bufferPos = 0;
    InitializeCriticalSection(&w->lock);

    w->buffer = (char*)HeapAlloc(GetProcessHeap(), 0, bufSize);
    if (!w->buffer) return FALSE;

    w->hFile = CreateFileW(filePath, GENERIC_WRITE, FILE_SHARE_READ,
                           NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (w->hFile == INVALID_HANDLE_VALUE) {
        HeapFree(GetProcessHeap(), 0, w->buffer);
        w->buffer = NULL;
        return FALSE;
    }

    if (writeBom) {
        BYTE bom[] = { 0xEF, 0xBB, 0xBF };
        DWORD written;
        WriteFile(w->hFile, bom, 3, &written, NULL);
    }
    return TRUE;
}

static void BufferedWriter_Write(BufferedWriter* w, const char* data, size_t len) {
    if (!w->buffer) return;  // Writer not initialized
    DWORD written;
    EnterCriticalSection(&w->lock);

    if (len > w->bufferSize) {
        // Flush existing buffer then write directly
        if (w->bufferPos > 0) {
            WriteFile(w->hFile, w->buffer, (DWORD)w->bufferPos, &written, NULL);
            w->bufferPos = 0;
        }
        WriteFile(w->hFile, data, (DWORD)len, &written, NULL);
    } else {
        if (w->bufferPos + len > w->bufferSize) {
            WriteFile(w->hFile, w->buffer, (DWORD)w->bufferPos, &written, NULL);
            w->bufferPos = 0;
        }
        memcpy(w->buffer + w->bufferPos, data, len);
        w->bufferPos += len;
    }

    w->rowsWritten++;
    LeaveCriticalSection(&w->lock);
}

static void BufferedWriter_Flush(BufferedWriter* w) {
    if (!w->buffer) return;
    DWORD written;
    EnterCriticalSection(&w->lock);
    if (w->bufferPos > 0) {
        WriteFile(w->hFile, w->buffer, (DWORD)w->bufferPos, &written, NULL);
        w->bufferPos = 0;
    }
    LeaveCriticalSection(&w->lock);
}

static void BufferedWriter_Destroy(BufferedWriter* w) {
    if (w->buffer) {
        BufferedWriter_Flush(w);
        HeapFree(GetProcessHeap(), 0, w->buffer);
    }
    if (w->hFile != INVALID_HANDLE_VALUE) {
        CloseHandle(w->hFile);
    }
    DeleteCriticalSection(&w->lock);
}

// ============================================================================
// Statistics (thread-safe via Interlocked operations)
// ============================================================================

struct ErrorEntry {
    WCHAR* path;
    DWORD errorCode;
};

struct ScanStats {
    volatile LONGLONG totalEntries;
    volatile LONGLONG fileCount;
    volatile LONGLONG dirCount;
    volatile LONGLONG errors;
    ErrorEntry errorLog[MAX_ERROR_LOG];
    volatile LONG errorLogCount;
    CRITICAL_SECTION errorLock;
};

static void Stats_Init(ScanStats* s) {
    s->totalEntries = 0;
    s->fileCount = 0;
    s->dirCount = 0;
    s->errors = 0;
    s->errorLogCount = 0;
    memset(s->errorLog, 0, sizeof(s->errorLog));
    InitializeCriticalSection(&s->errorLock);
}

static void Stats_Destroy(ScanStats* s) {
    for (size_t i = 0; i < MAX_ERROR_LOG; i++) {
        if (s->errorLog[i].path) {
            HeapFree(GetProcessHeap(), 0, s->errorLog[i].path);
        }
    }
    DeleteCriticalSection(&s->errorLock);
}

static void Stats_LogError(ScanStats* s, const WCHAR* path, DWORD errorCode) {
    InterlockedIncrement64(&s->errors);
    LONG idx = InterlockedIncrement(&s->errorLogCount) - 1;
    if (idx < (LONG)MAX_ERROR_LOG) {
        EnterCriticalSection(&s->errorLock);
        size_t len = wcslen(path) + 1;
        s->errorLog[idx].path = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, len * sizeof(WCHAR));
        if (s->errorLog[idx].path) {
            wcscpy(s->errorLog[idx].path, path);
        }
        s->errorLog[idx].errorCode = errorCode;
        LeaveCriticalSection(&s->errorLock);
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

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

static SIZE_T GetMemoryUsageMB(void) {
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

// Convert FILETIME to ISO 8601 UTC string: "YYYY-MM-DDTHH:MM:SS"
static int FileTimeToIso8601(const FILETIME* ft, char* buf, size_t bufSize) {
    SYSTEMTIME st;
    if (FileTimeToSystemTime(ft, &st)) {
        return snprintf(buf, bufSize, "%04d-%02d-%02dT%02d:%02d:%02d",
                        st.wYear, st.wMonth, st.wDay,
                        st.wHour, st.wMinute, st.wSecond);
    }
    buf[0] = '\0';
    return 0;
}

// Write a UTF-8 string as a quoted CSV field into dest.
// Always quotes the field. Escapes internal double-quotes as "".
// Returns number of bytes written.
static int CsvQuoteUtf8(char* dest, size_t destSize, const char* src) {
    int pos = 0;
    if (pos < (int)destSize) dest[pos++] = '"';
    for (int i = 0; src[i] && pos < (int)destSize - 2; i++) {
        if (src[i] == '"') {
            if (pos < (int)destSize - 3) dest[pos++] = '"';
        }
        dest[pos++] = src[i];
    }
    if (pos < (int)destSize) dest[pos++] = '"';
    return pos;
}

// Write an error entry to the error log file
static void WriteErrorToLog(BufferedWriter* errLog, const WCHAR* path,
                            DWORD errorCode, const WCHAR* errorDesc) {
    SYSTEMTIME st;
    GetSystemTime(&st);

    // Convert path to UTF-8
    char utf8Path[MAX_PATH_LEN * 3];
    WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8Path, sizeof(utf8Path), NULL, NULL);

    char utf8Desc[256];
    WideCharToMultiByte(CP_UTF8, 0, errorDesc, -1, utf8Desc, sizeof(utf8Desc), NULL, NULL);

    char buf[MAX_PATH_LEN * 3 + 512];
    int len = snprintf(buf, sizeof(buf),
        "%04d-%02d-%02dT%02d:%02d:%02dZ | ERROR | %lu | %s | %s\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
        errorCode, utf8Desc, utf8Path);

    if (len > 0) {
        BufferedWriter_Write(errLog, buf, (size_t)len);
    }
}

// ============================================================================
// Worker Context
// ============================================================================

struct WorkerContext {
    PathQueue* queue;
    BufferedWriter* csv;
    BufferedWriter* errLog;
    ScanStats* stats;
    ULONGLONG minSizeBytes;
    volatile LONG* runningWorkers;
    DWORD workerId;
    const char* volumeUtf8;     // e.g., "C:"
};

// ============================================================================
// Directory Scanning Worker
// ============================================================================

static DWORD WINAPI ScanWorker(LPVOID param) {
    WorkerContext* ctx = (WorkerContext*)param;

    // Stack-allocate fixed-size buffers for path building
    WCHAR searchPath[MAX_PATH_LEN];
    WCHAR fullPath[MAX_PATH_LEN];
    WIN32_FIND_DATAW findData;
    char createdStr[32], modifiedStr[32], accessedStr[32];

    // Heap-allocate the large per-thread buffers
    char* rowBuffer   = (char*)HeapAlloc(GetProcessHeap(), 0, ROW_BUF_SIZE);
    char* utf8Path    = (char*)HeapAlloc(GetProcessHeap(), 0, MAX_PATH_LEN * 3);
    char* utf8Name    = (char*)HeapAlloc(GetProcessHeap(), 0, 2048);
    char* quotedPath  = (char*)HeapAlloc(GetProcessHeap(), 0, MAX_PATH_LEN * 6);
    char* quotedName  = (char*)HeapAlloc(GetProcessHeap(), 0, 4096);

    if (!rowBuffer || !utf8Path || !utf8Name || !quotedPath || !quotedName) {
        // Fatal allocation failure
        if (rowBuffer)  HeapFree(GetProcessHeap(), 0, rowBuffer);
        if (utf8Path)   HeapFree(GetProcessHeap(), 0, utf8Path);
        if (utf8Name)   HeapFree(GetProcessHeap(), 0, utf8Name);
        if (quotedPath) HeapFree(GetProcessHeap(), 0, quotedPath);
        if (quotedName) HeapFree(GetProcessHeap(), 0, quotedName);
        InterlockedDecrement(ctx->runningWorkers);
        return 1;
    }

    while (TRUE) {
        WCHAR* dirPath = PathQueue_Pop(ctx->queue);
        if (!dirPath) break;

        size_t dirLen = wcslen(dirPath);
        if (dirLen > MAX_PATH_LEN - 10) {
            Stats_LogError(ctx->stats, dirPath, ERROR_BUFFER_OVERFLOW);
            WriteErrorToLog(ctx->errLog, dirPath, ERROR_BUFFER_OVERFLOW, L"Path too long");
            HeapFree(GetProcessHeap(), 0, dirPath);
            PathQueue_WorkerDone(ctx->queue);
            continue;
        }

        // Build search pattern: dirPath\*
        wcscpy(searchPath, dirPath);
        if (dirPath[dirLen - 1] != L'\\') {
            wcscat(searchPath, L"\\");
        }
        wcscat(searchPath, L"*");

        HANDLE hFind = FindFirstFileW(searchPath, &findData);
        if (hFind == INVALID_HANDLE_VALUE) {
            DWORD err = GetLastError();
            Stats_LogError(ctx->stats, dirPath, err);
            WriteErrorToLog(ctx->errLog, dirPath, err, GetErrorDescription(err));
            HeapFree(GetProcessHeap(), 0, dirPath);
            PathQueue_WorkerDone(ctx->queue);
            continue;
        }

        do {
            // Skip . and ..
            if (findData.cFileName[0] == L'.') {
                if (findData.cFileName[1] == L'\0') continue;
                if (findData.cFileName[1] == L'.' && findData.cFileName[2] == L'\0') continue;
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
                // Queue subdirectory (skip reparse points to avoid loops)
                if (!isReparse) {
                    PathQueue_Push(ctx->queue, fullPath);
                }
            } else {
                InterlockedIncrement64(&ctx->stats->fileCount);
            }

            // Calculate file size
            ULONGLONG fileSize = ((ULONGLONG)findData.nFileSizeHigh << 32) |
                                 findData.nFileSizeLow;

            // Apply minSize filter (files only; directories always included)
            if (!isDir && ctx->minSizeBytes > 0 && fileSize < ctx->minSizeBytes) {
                continue;
            }

            // Convert timestamps
            FileTimeToIso8601(&findData.ftCreationTime, createdStr, sizeof(createdStr));
            FileTimeToIso8601(&findData.ftLastWriteTime, modifiedStr, sizeof(modifiedStr));
            FileTimeToIso8601(&findData.ftLastAccessTime, accessedStr, sizeof(accessedStr));

            // Convert path and filename to UTF-8
            WideCharToMultiByte(CP_UTF8, 0, fullPath, -1, utf8Path, (int)(MAX_PATH_LEN * 3), NULL, NULL);
            WideCharToMultiByte(CP_UTF8, 0, findData.cFileName, -1, utf8Name, 2048, NULL, NULL);

            // Quote path and filename for CSV
            int qpLen = CsvQuoteUtf8(quotedPath, MAX_PATH_LEN * 6, utf8Path);
            int qnLen = CsvQuoteUtf8(quotedName, 4096, utf8Name);

            // Build CSV row
            int pos = 0;

            // Volume
            int vlLen = (int)strlen(ctx->volumeUtf8);
            memcpy(rowBuffer + pos, ctx->volumeUtf8, vlLen);
            pos += vlLen;
            rowBuffer[pos++] = ',';

            // FullPath (quoted)
            memcpy(rowBuffer + pos, quotedPath, qpLen);
            pos += qpLen;
            rowBuffer[pos++] = ',';

            // FileName (quoted)
            memcpy(rowBuffer + pos, quotedName, qnLen);
            pos += qnLen;
            rowBuffer[pos++] = ',';

            // FileSize (empty for directories)
            if (!isDir) {
                pos += snprintf(rowBuffer + pos, ROW_BUF_SIZE - pos, "%llu", fileSize);
            }
            rowBuffer[pos++] = ',';

            // CreatedTime
            int csLen = (int)strlen(createdStr);
            memcpy(rowBuffer + pos, createdStr, csLen);
            pos += csLen;
            rowBuffer[pos++] = ',';

            // ModifiedTime
            int msLen = (int)strlen(modifiedStr);
            memcpy(rowBuffer + pos, modifiedStr, msLen);
            pos += msLen;
            rowBuffer[pos++] = ',';

            // AccessedTime
            int asLen = (int)strlen(accessedStr);
            memcpy(rowBuffer + pos, accessedStr, asLen);
            pos += asLen;
            rowBuffer[pos++] = ',';

            // IsDirectory
            rowBuffer[pos++] = isDir ? '1' : '0';
            rowBuffer[pos++] = ',';

            // Attributes
            pos += snprintf(rowBuffer + pos, ROW_BUF_SIZE - pos, "%lu",
                            findData.dwFileAttributes);

            // Line ending
            rowBuffer[pos++] = '\r';
            rowBuffer[pos++] = '\n';

            BufferedWriter_Write(ctx->csv, rowBuffer, (size_t)pos);

        } while (FindNextFileW(hFind, &findData));

        FindClose(hFind);
        HeapFree(GetProcessHeap(), 0, dirPath);
        PathQueue_WorkerDone(ctx->queue);
    }

    HeapFree(GetProcessHeap(), 0, rowBuffer);
    HeapFree(GetProcessHeap(), 0, utf8Path);
    HeapFree(GetProcessHeap(), 0, utf8Name);
    HeapFree(GetProcessHeap(), 0, quotedPath);
    HeapFree(GetProcessHeap(), 0, quotedName);

    InterlockedDecrement(ctx->runningWorkers);
    return 0;
}

// ============================================================================
// Progress Reporter
// ============================================================================

struct ProgressContext {
    ScanStats* stats;
    BufferedWriter* csv;
    LARGE_INTEGER startTime;
    LARGE_INTEGER freq;
    volatile LONG* running;
};

static DWORD WINAPI ProgressWorker(LPVOID param) {
    ProgressContext* ctx = (ProgressContext*)param;
    LONGLONG lastTotal = 0;

    while (*ctx->running) {
        Sleep(1000);
        LONGLONG total = ctx->stats->totalEntries;
        if (total - lastTotal >= PROGRESS_INTERVAL ||
            (total != lastTotal && total % PROGRESS_INTERVAL < (total - lastTotal))) {
            double elapsed = GetElapsedSeconds(ctx->startTime, ctx->freq);
            double rate = (elapsed > 0) ? (double)total / elapsed : 0;
            SIZE_T memMB = GetMemoryUsageMB();
            wprintf(L"  Processed %lld entries (%.0f/sec, %zu MB RAM, %lld CSV rows)\n",
                    total, rate, memMB, ctx->csv->rowsWritten);
            lastTotal = (total / PROGRESS_INTERVAL) * PROGRESS_INTERVAL;
        }
    }
    return 0;
}

// ============================================================================
// Print Errors to Console
// ============================================================================

static void PrintErrors(ScanStats* stats) {
    if (stats->errors == 0) return;

    wprintf(L"\nErrors encountered (see error log for full details):\n");
    wprintf(L"------------------------------------------------------------\n");

    LONG count = stats->errorLogCount;
    if (count > (LONG)MAX_ERROR_LOG) count = (LONG)MAX_ERROR_LOG;

    for (LONG i = 0; i < count; i++) {
        if (stats->errorLog[i].path) {
            const WCHAR* path = stats->errorLog[i].path;
            size_t pathLen = wcslen(path);
            DWORD err = stats->errorLog[i].errorCode;

            if (pathLen > 50) {
                wprintf(L"  [%lu] %s: ...%s\n", err,
                        GetErrorDescription(err), path + pathLen - 47);
            } else {
                wprintf(L"  [%lu] %s: %s\n", err,
                        GetErrorDescription(err), path);
            }
        }
    }

    if (stats->errors > (LONGLONG)MAX_ERROR_LOG) {
        wprintf(L"  ... and %lld more errors (see error log file)\n",
                stats->errors - (LONGLONG)MAX_ERROR_LOG);
    }
}

// ============================================================================
// Scan a Single Volume
// ============================================================================

static int ScanVolume(const VolumeInfo* vol, BufferedWriter* csv,
                      BufferedWriter* errLog, ULONGLONG minSizeBytes,
                      DWORD numThreads, VolumeScanResult* outResult) {

    // Build root path with \\?\ prefix for long path support
    WCHAR rootPath[MAX_PATH + 8];
    swprintf(rootPath, MAX_PATH + 8, L"\\\\?\\%s", vol->mountPath);

    // Build volume label for CSV column
    char volumeUtf8[MAX_PATH * 3];
    WideCharToMultiByte(CP_UTF8, 0, vol->displayName, -1,
                        volumeUtf8, sizeof(volumeUtf8), NULL, NULL);

    wprintf(L"\nScanning: %s\n", vol->displayName);
    wprintf(L"------------------------------------------------------------\n");

    // Initialize queue and stats for this volume
    PathQueue queue;
    PathQueue_Init(&queue, QUEUE_INITIAL_CAP);

    ScanStats stats;
    Stats_Init(&stats);

    volatile LONG runningWorkers = (LONG)numThreads;
    volatile LONG progressRunning = 1;

    LARGE_INTEGER startTime, freq;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&startTime);

    // Seed queue with root path
    PathQueue_Push(&queue, rootPath);

    // Create worker threads
    WorkerContext* contexts = (WorkerContext*)HeapAlloc(GetProcessHeap(), 0,
                                                        sizeof(WorkerContext) * numThreads);
    HANDLE* threads = (HANDLE*)HeapAlloc(GetProcessHeap(), 0, sizeof(HANDLE) * numThreads);

    for (DWORD i = 0; i < numThreads; i++) {
        contexts[i].queue = &queue;
        contexts[i].csv = csv;
        contexts[i].errLog = errLog;
        contexts[i].stats = &stats;
        contexts[i].minSizeBytes = minSizeBytes;
        contexts[i].runningWorkers = &runningWorkers;
        contexts[i].workerId = i;
        contexts[i].volumeUtf8 = volumeUtf8;
        threads[i] = CreateThread(NULL, 0, ScanWorker, &contexts[i], 0, NULL);
    }

    // Start progress reporter
    ProgressContext progressCtx;
    progressCtx.stats = &stats;
    progressCtx.csv = csv;
    progressCtx.startTime = startTime;
    progressCtx.freq = freq;
    progressCtx.running = &progressRunning;
    HANDLE progressThread = CreateThread(NULL, 0, ProgressWorker, &progressCtx, 0, NULL);

    // Wait for all workers
    WaitForMultipleObjects(numThreads, threads, TRUE, INFINITE);

    queue.producersDone = 1;
    SetEvent(queue.itemAvailable);

    progressRunning = 0;
    WaitForSingleObject(progressThread, INFINITE);
    CloseHandle(progressThread);

    double elapsed = GetElapsedSeconds(startTime, freq);

    for (DWORD i = 0; i < numThreads; i++) {
        CloseHandle(threads[i]);
    }
    HeapFree(GetProcessHeap(), 0, threads);
    HeapFree(GetProcessHeap(), 0, contexts);

    // Print volume summary
    wprintf(L"\n  Volume:               %s\n", vol->displayName);
    wprintf(L"  Threads:              %lu\n", numThreads);
    wprintf(L"  Total entries:        %lld\n", stats.totalEntries);
    wprintf(L"    - Directories:      %lld\n", stats.dirCount);
    wprintf(L"    - Files:            %lld\n", stats.fileCount);
    wprintf(L"    - Errors:           %lld\n", stats.errors);
    wprintf(L"  Elapsed:              %.1f seconds\n", elapsed);

    double rate = (elapsed > 0) ? (double)stats.totalEntries / elapsed : 0;
    wprintf(L"  Rate:                 %.0f entries/sec\n", rate);

    PrintErrors(&stats);

    if (outResult) {
        outResult->entryCount     = stats.totalEntries;
        outResult->directoryCount = stats.dirCount;
        outResult->fileCount      = stats.fileCount;
        outResult->errorCount     = stats.errors;
        outResult->durationSec    = elapsed;
    }

    PathQueue_Destroy(&queue);
    Stats_Destroy(&stats);

    return 0;
}

// ============================================================================
// Volume Enumeration (discovers drive letters AND mount points)
// ============================================================================

static int EnumerateAllNtfsVolumes(VolumeInfo* volumes, int maxVolumes) {
    WCHAR volumeGuid[128];
    int count = 0;

    HANDLE hFind = FindFirstVolumeW(volumeGuid, 128);
    if (hFind == INVALID_HANDLE_VALUE) return 0;

    do {
        if (count >= maxVolumes) break;

        // Only fixed NTFS drives
        DWORD driveType = GetDriveTypeW(volumeGuid);
        if (driveType != DRIVE_FIXED) continue;

        WCHAR fsName[64];
        if (!GetVolumeInformationW(volumeGuid, NULL, 0, NULL, NULL, NULL, fsName, 64))
            continue;
        if (_wcsicmp(fsName, L"NTFS") != 0) continue;

        // Get mount paths for this volume
        WCHAR pathNames[4096];
        DWORD returnLen = 0;
        if (!GetVolumePathNamesForVolumeNameW(volumeGuid, pathNames, 4096, &returnLen))
            continue;

        // Pick primary mount path: prefer drive letter over directory mount
        const WCHAR* bestPath = NULL;
        BOOL bestIsDriveLetter = FALSE;
        const WCHAR* p = pathNames;
        while (*p) {
            size_t plen = wcslen(p);
            BOOL isDriveLetter = (plen <= 3 && plen >= 2 && p[1] == L':');
            if (!bestPath || (isDriveLetter && !bestIsDriveLetter)) {
                bestPath = p;
                bestIsDriveLetter = isDriveLetter;
            }
            p += plen + 1;
        }
        if (!bestPath || bestPath[0] == L'\0') continue;

        // Store devicePath = GUID path without trailing backslash
        wcscpy(volumes[count].devicePath, volumeGuid);
        size_t guidLen = wcslen(volumes[count].devicePath);
        if (guidLen > 0 && volumes[count].devicePath[guidLen - 1] == L'\\')
            volumes[count].devicePath[guidLen - 1] = L'\0';

        // Store mountPath = with trailing backslash
        wcscpy(volumes[count].mountPath, bestPath);
        size_t mountLen = wcslen(volumes[count].mountPath);
        if (mountLen > 0 && volumes[count].mountPath[mountLen - 1] != L'\\')
            wcscat(volumes[count].mountPath, L"\\");

        // Store displayName = without trailing backslash
        wcscpy(volumes[count].displayName, bestPath);
        size_t dispLen = wcslen(volumes[count].displayName);
        if (dispLen > 1 && volumes[count].displayName[dispLen - 1] == L'\\')
            volumes[count].displayName[dispLen - 1] = L'\0';

        count++;
    } while (FindNextVolumeW(hFind, volumeGuid, 128));

    FindVolumeClose(hFind);
    return count;
}

// ============================================================================
// Scan Configuration
// ============================================================================

struct ScanConfig {
    VolumeInfo volumes[MAX_VOLUMES];
    int volumeCount;
    WCHAR outputPath[MAX_PATH_LEN];
    DWORD numThreads;
    ULONGLONG minSizeBytes;
    BOOL allVolumes;
    BOOL showHelp;
};

// ============================================================================
// Usage / Help
// ============================================================================

static void PrintUsage(void) {
    wprintf(L"mftscan - NTFS Volume Scanner for Space Utilization Reporting\n\n");
    wprintf(L"Usage:\n");
    wprintf(L"  mftscan.exe [options] [volume...]\n\n");
    wprintf(L"Volumes:\n");
    wprintf(L"  C: D: E:              Scan specific volumes\n");
    wprintf(L"  --allVolumes          Scan all local NTFS volumes (incl. mount points)\n\n");
    wprintf(L"Options:\n");
    wprintf(L"  --output <path>       Output CSV file path\n");
    wprintf(L"                        (default: mftscan_YYYYMMDD_HHMMSS.csv)\n");
    wprintf(L"  --threads <n>         Worker threads (default: number of processors)\n");
    wprintf(L"  --minSize <bytes>     Minimum file size filter (default: 0, no filter)\n");
    wprintf(L"  --help                Show this help message\n\n");
    wprintf(L"Output:\n");
    wprintf(L"  <output>.csv          Combined CSV with Volume column\n");
    wprintf(L"  <output>_errors.log   Separate error log for inaccessible files\n\n");
    wprintf(L"Examples:\n");
    wprintf(L"  mftscan.exe C:\n");
    wprintf(L"  mftscan.exe C: D: --output results.csv\n");
    wprintf(L"  mftscan.exe --allVolumes --threads 8\n");
    wprintf(L"  mftscan.exe D: --minSize 1048576\n");
}

// ============================================================================
// Argument Parsing
// ============================================================================

static BOOL ParseArguments(int argc, wchar_t* argv[], ScanConfig* config) {
    memset(config, 0, sizeof(ScanConfig));

    // Default thread count: number of logical processors
    SYSTEM_INFO sysInfo;
    GetSystemInfo(&sysInfo);
    config->numThreads = sysInfo.dwNumberOfProcessors;
    if (config->numThreads == 0) config->numThreads = 4;
    if (config->numThreads > MAX_THREADS) config->numThreads = MAX_THREADS;

    config->minSizeBytes = 0;  // No filter by default
    config->allVolumes = FALSE;
    config->showHelp = FALSE;
    config->volumeCount = 0;
    config->outputPath[0] = L'\0';

    for (int i = 1; i < argc; i++) {
        if (_wcsicmp(argv[i], L"--help") == 0 || _wcsicmp(argv[i], L"-h") == 0) {
            config->showHelp = TRUE;
            return TRUE;
        }
        else if (_wcsicmp(argv[i], L"--allVolumes") == 0 ||
                 _wcsicmp(argv[i], L"--allvolumes") == 0) {
            config->allVolumes = TRUE;
        }
        else if (_wcsicmp(argv[i], L"--output") == 0) {
            if (i + 1 < argc) {
                wcscpy(config->outputPath, argv[++i]);
            } else {
                wprintf(L"Error: --output requires a file path argument\n");
                return FALSE;
            }
        }
        else if (_wcsicmp(argv[i], L"--threads") == 0) {
            if (i + 1 < argc) {
                config->numThreads = (DWORD)_wtoi(argv[++i]);
                if (config->numThreads == 0) config->numThreads = 1;
                if (config->numThreads > MAX_THREADS) config->numThreads = MAX_THREADS;
            } else {
                wprintf(L"Error: --threads requires a number argument\n");
                return FALSE;
            }
        }
        else if (_wcsicmp(argv[i], L"--minSize") == 0 ||
                 _wcsicmp(argv[i], L"--minsize") == 0) {
            if (i + 1 < argc) {
                config->minSizeBytes = (ULONGLONG)_wtoi64(argv[++i]);
            } else {
                wprintf(L"Error: --minSize requires a byte count argument\n");
                return FALSE;
            }
        }
        else if (wcslen(argv[i]) >= 2 && argv[i][1] == L':') {
            // Volume specifier (e.g., "C:" or "D:\")
            if (config->volumeCount < (int)MAX_VOLUMES) {
                VolumeInfo* vi = &config->volumes[config->volumeCount];
                WCHAR letter = towupper(argv[i][0]);
                swprintf(vi->devicePath, 128, L"\\\\.\\%c:", letter);
                swprintf(vi->mountPath, MAX_PATH, L"%c:\\", letter);
                swprintf(vi->displayName, MAX_PATH, L"%c:", letter);
                config->volumeCount++;
            }
        }
        else {
            wprintf(L"Error: Unknown argument: %s\n", argv[i]);
            return FALSE;
        }
    }

    // Validate: must have volumes or --allVolumes
    if (!config->showHelp && !config->allVolumes && config->volumeCount == 0) {
        wprintf(L"Error: Specify at least one volume (e.g., C:) or use --allVolumes\n\n");
        PrintUsage();
        return FALSE;
    }

    return TRUE;
}

// Build default output filename: mftscan_YYYYMMDD_HHMMSS.csv
static void BuildDefaultOutputPath(WCHAR* path, size_t pathSize) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    swprintf(path, pathSize, L"mftscan_%04d%02d%02d_%02d%02d%02d.csv",
             st.wYear, st.wMonth, st.wDay,
             st.wHour, st.wMinute, st.wSecond);
}

// Build error log path from CSV path: replace .csv with _errors.log
static void BuildErrorLogPath(const WCHAR* csvPath, WCHAR* errPath, size_t errPathSize) {
    wcscpy_s(errPath, errPathSize, csvPath);
    size_t len = wcslen(errPath);

    // Find .csv extension
    if (len >= 4 && _wcsicmp(errPath + len - 4, L".csv") == 0) {
        wcscpy(errPath + len - 4, L"_errors.log");
    } else {
        wcscat_s(errPath, errPathSize, L"_errors.log");
    }
}

// ============================================================================
// JSON Manifest Writer
// ============================================================================

static void WriteJsonString(HANDLE hFile, const char* s) {
    DWORD written;
    WriteFile(hFile, "\"", 1, &written, NULL);
    for (const char* p = s; *p; p++) {
        switch (*p) {
            case '\\': WriteFile(hFile, "\\\\", 2, &written, NULL); break;
            case '"':  WriteFile(hFile, "\\\"", 2, &written, NULL); break;
            case '\n': WriteFile(hFile, "\\n", 2, &written, NULL); break;
            case '\r': WriteFile(hFile, "\\r", 2, &written, NULL); break;
            case '\t': WriteFile(hFile, "\\t", 2, &written, NULL); break;
            default:
                if ((unsigned char)*p < 0x20) {
                    char esc[8];
                    int n = snprintf(esc, sizeof(esc), "\\u%04x", (unsigned char)*p);
                    WriteFile(hFile, esc, n, &written, NULL);
                } else {
                    WriteFile(hFile, p, 1, &written, NULL);
                }
                break;
        }
    }
    WriteFile(hFile, "\"", 1, &written, NULL);
}

static void WriteJsonManifest(const WCHAR* csvPath, const WCHAR* errorLogPath,
                              const ScanConfig* config,
                              const VolumeScanResult* results,
                              double totalDurationSec,
                              LONGLONG totalEntries) {

    WCHAR jsonPath[MAX_PATH_LEN];
    wcscpy(jsonPath, csvPath);
    size_t len = wcslen(jsonPath);
    if (len >= 4 && _wcsicmp(jsonPath + len - 4, L".csv") == 0) {
        wcscpy(jsonPath + len - 4, L".json");
    } else {
        wcscat(jsonPath, L".json");
    }

    HANDLE hFile = CreateFileW(jsonPath, GENERIC_WRITE, FILE_SHARE_READ,
                               NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        wprintf(L"Warning: Cannot create manifest file: %s\n", jsonPath);
        return;
    }

    DWORD written;
    char buf[4096];
    int n;

    WCHAR serverNameW[256];
    DWORD serverNameLen = 256;
    GetComputerNameW(serverNameW, &serverNameLen);
    char serverName[256];
    WideCharToMultiByte(CP_UTF8, 0, serverNameW, -1, serverName, sizeof(serverName), NULL, NULL);

    WCHAR domainW[256], userW[256];
    DWORD userLen = 256;
    GetEnvironmentVariableW(L"USERDOMAIN", domainW, 256);
    GetUserNameW(userW, &userLen);
    char collectedBy[512];
    char domainUtf8[256], userUtf8[256];
    WideCharToMultiByte(CP_UTF8, 0, domainW, -1, domainUtf8, sizeof(domainUtf8), NULL, NULL);
    WideCharToMultiByte(CP_UTF8, 0, userW, -1, userUtf8, sizeof(userUtf8), NULL, NULL);
    snprintf(collectedBy, sizeof(collectedBy), "%s\\%s", domainUtf8, userUtf8);

    SYSTEMTIME st;
    GetSystemTime(&st);
    char timestamp[32];
    snprintf(timestamp, sizeof(timestamp), "%04d-%02d-%02dT%02d:%02d:%02dZ",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    const WCHAR* csvFile = wcsrchr(csvPath, L'\\');
    csvFile = csvFile ? csvFile + 1 : csvPath;
    char csvFileUtf8[MAX_PATH];
    WideCharToMultiByte(CP_UTF8, 0, csvFile, -1, csvFileUtf8, sizeof(csvFileUtf8), NULL, NULL);

    const WCHAR* errFile = wcsrchr(errorLogPath, L'\\');
    errFile = errFile ? errFile + 1 : errorLogPath;
    char errFileUtf8[MAX_PATH];
    WideCharToMultiByte(CP_UTF8, 0, errFile, -1, errFileUtf8, sizeof(errFileUtf8), NULL, NULL);

    WriteFile(hFile, "{\n", 2, &written, NULL);

    n = snprintf(buf, sizeof(buf), "  \"schemaVersion\": 1,\n");
    WriteFile(hFile, buf, n, &written, NULL);

    WriteFile(hFile, "  \"toolName\": ", 14, &written, NULL);
    WriteJsonString(hFile, TOOL_NAME);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    WriteFile(hFile, "  \"toolVersion\": ", 17, &written, NULL);
    WriteJsonString(hFile, TOOL_VERSION);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    WriteFile(hFile, "  \"serverName\": ", 16, &written, NULL);
    WriteJsonString(hFile, serverName);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    WriteFile(hFile, "  \"collectedAtUtc\": ", 20, &written, NULL);
    WriteJsonString(hFile, timestamp);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    WriteFile(hFile, "  \"collectedBy\": ", 17, &written, NULL);
    WriteJsonString(hFile, collectedBy);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    n = snprintf(buf, sizeof(buf), "  \"durationSec\": %.1f,\n", totalDurationSec);
    WriteFile(hFile, buf, n, &written, NULL);

    WriteFile(hFile, "  \"dataFile\": ", 14, &written, NULL);
    WriteJsonString(hFile, csvFileUtf8);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    WriteFile(hFile, "  \"errorFile\": ", 15, &written, NULL);
    WriteJsonString(hFile, errFileUtf8);
    WriteFile(hFile, ",\n", 2, &written, NULL);

    n = snprintf(buf, sizeof(buf), "  \"totalEntries\": %lld,\n", totalEntries);
    WriteFile(hFile, buf, n, &written, NULL);

    WriteFile(hFile, "  \"volumes\": [\n", 15, &written, NULL);

    for (int i = 0; i < config->volumeCount; i++) {
        const VolumeInfo* vol = &config->volumes[i];
        const VolumeScanResult* r = &results[i];

        WCHAR volumeLabelW[256] = {0};
        WCHAR fsNameW[64] = {0};
        GetVolumeInformationW(vol->mountPath, volumeLabelW, 256,
                              NULL, NULL, NULL, fsNameW, 64);

        char volumeLabel[256], fsName[64];
        WideCharToMultiByte(CP_UTF8, 0, volumeLabelW, -1, volumeLabel, sizeof(volumeLabel), NULL, NULL);
        WideCharToMultiByte(CP_UTF8, 0, fsNameW, -1, fsName, sizeof(fsName), NULL, NULL);

        ULARGE_INTEGER totalBytes = {0}, freeBytes = {0};
        GetDiskFreeSpaceExW(vol->mountPath, NULL, &totalBytes, &freeBytes);

        char displayNameUtf8[MAX_PATH * 3];
        WideCharToMultiByte(CP_UTF8, 0, vol->displayName, -1,
                            displayNameUtf8, sizeof(displayNameUtf8), NULL, NULL);

        WriteFile(hFile, "    {\n", 6, &written, NULL);

        WriteFile(hFile, "      \"name\": ", 14, &written, NULL);
        WriteJsonString(hFile, displayNameUtf8);
        WriteFile(hFile, ",\n", 2, &written, NULL);

        WriteFile(hFile, "      \"label\": ", 15, &written, NULL);
        WriteJsonString(hFile, volumeLabel);
        WriteFile(hFile, ",\n", 2, &written, NULL);

        WriteFile(hFile, "      \"fileSystem\": ", 20, &written, NULL);
        WriteJsonString(hFile, fsName);
        WriteFile(hFile, ",\n", 2, &written, NULL);

        n = snprintf(buf, sizeof(buf),
            "      \"totalSizeBytes\": %llu,\n"
            "      \"freeSizeBytes\": %llu,\n"
            "      \"entryCount\": %lld,\n"
            "      \"directoryCount\": %lld,\n"
            "      \"fileCount\": %lld,\n"
            "      \"errorCount\": %lld,\n"
            "      \"scanDurationSec\": %.1f\n",
            totalBytes.QuadPart, freeBytes.QuadPart,
            r->entryCount, r->directoryCount, r->fileCount,
            r->errorCount, r->durationSec);
        WriteFile(hFile, buf, n, &written, NULL);

        if (i < config->volumeCount - 1) {
            WriteFile(hFile, "    },\n", 6, &written, NULL);
        } else {
            WriteFile(hFile, "    }\n", 5, &written, NULL);
        }
    }

    WriteFile(hFile, "  ]\n", 4, &written, NULL);
    WriteFile(hFile, "}\n", 2, &written, NULL);

    CloseHandle(hFile);
    wprintf(L"Manifest:     %s\n", jsonPath);
}

// ============================================================================
// Main Entry Point
// ============================================================================

int wmain(int argc, wchar_t* argv[]) {
    SetConsoleOutputCP(CP_UTF8);
    setvbuf(stdout, NULL, _IONBF, 0);

    // Parse arguments
    ScanConfig config;
    if (!ParseArguments(argc, argv, &config)) {
        return 1;
    }

    if (config.showHelp) {
        PrintUsage();
        return 0;
    }

    // Enumerate volumes if --allVolumes
    if (config.allVolumes) {
        int count = EnumerateAllNtfsVolumes(config.volumes, (int)MAX_VOLUMES);
        if (count == 0) {
            wprintf(L"Error: No NTFS volumes found\n");
            return 1;
        }
        config.volumeCount = count;
    }

    // Build output paths
    if (config.outputPath[0] == L'\0') {
        BuildDefaultOutputPath(config.outputPath, MAX_PATH_LEN);
    }

    WCHAR errorLogPath[MAX_PATH_LEN];
    BuildErrorLogPath(config.outputPath, errorLogPath, MAX_PATH_LEN);

    // Print banner
    wprintf(L"============================================================\n");
    wprintf(L"MFTSCAN - NTFS Volume Scanner\n");
    wprintf(L"============================================================\n");
    wprintf(L"Volumes:    ");
    for (int i = 0; i < config.volumeCount; i++) {
        wprintf(L"%s%s", config.volumes[i].displayName, (i < config.volumeCount - 1) ? L", " : L"");
    }
    wprintf(L"\n");
    wprintf(L"Threads:    %lu\n", config.numThreads);

    if (config.minSizeBytes > 0) {
        WCHAR sizeStr[64];
        FormatSize(config.minSizeBytes, sizeStr, 64);
        wprintf(L"Min size:   %s (%llu bytes)\n", sizeStr, config.minSizeBytes);
    } else {
        wprintf(L"Min size:   (none - capturing all files)\n");
    }

    wprintf(L"Output:     %s\n", config.outputPath);
    wprintf(L"Error log:  %s\n", errorLogPath);
    wprintf(L"============================================================\n");

    // Open CSV writer
    BufferedWriter csv;
    if (!BufferedWriter_Init(&csv, config.outputPath, CSV_WRITE_BUF_SIZE, TRUE)) {
        wprintf(L"Error: Cannot create output file: %s\n", config.outputPath);
        return 1;
    }

    // Write CSV header
    const char* header = "Volume,FullPath,FileName,FileSize,CreatedTime,"
                         "ModifiedTime,AccessedTime,IsDirectory,Attributes\r\n";
    DWORD headerWritten;
    // Write header directly (not through buffered row counter)
    EnterCriticalSection(&csv.lock);
    WriteFile(csv.hFile, header, (DWORD)strlen(header), &headerWritten, NULL);
    LeaveCriticalSection(&csv.lock);

    // Open error log writer
    BufferedWriter errLog;
    if (!BufferedWriter_Init(&errLog, errorLogPath, ERR_WRITE_BUF_SIZE, FALSE)) {
        wprintf(L"Warning: Cannot create error log file: %s\n", errorLogPath);
        wprintf(L"Errors will only appear in console output.\n");
    }

    // Track overall timing
    LARGE_INTEGER overallStart, overallFreq;
    QueryPerformanceFrequency(&overallFreq);
    QueryPerformanceCounter(&overallStart);
    LONGLONG totalEntriesAllVolumes = 0;

    VolumeScanResult volumeResults[MAX_VOLUMES];
    memset(volumeResults, 0, sizeof(volumeResults));

    // Scan each volume
    for (int v = 0; v < config.volumeCount; v++) {
        ScanVolume(&config.volumes[v], &csv, &errLog,
                   config.minSizeBytes, config.numThreads, &volumeResults[v]);

        totalEntriesAllVolumes += volumeResults[v].entryCount;
    }

    // Flush and close writers
    BufferedWriter_Destroy(&csv);
    BufferedWriter_Destroy(&errLog);

    // Print overall summary
    double overallElapsed = GetElapsedSeconds(overallStart, overallFreq);
    SIZE_T memMB = GetMemoryUsageMB();

    // Write JSON manifest
    WriteJsonManifest(config.outputPath, errorLogPath, &config,
                      volumeResults, overallElapsed, totalEntriesAllVolumes);

    wprintf(L"\n============================================================\n");
    wprintf(L"SCAN COMPLETE\n");
    wprintf(L"============================================================\n");
    wprintf(L"Volumes scanned:  %d\n", config.volumeCount);
    wprintf(L"Total entries:    %lld\n", totalEntriesAllVolumes);
    wprintf(L"CSV rows:         %lld\n", csv.rowsWritten);
    wprintf(L"Total elapsed:    %.1f seconds\n", overallElapsed);

    double overallRate = (overallElapsed > 0) ?
        (double)totalEntriesAllVolumes / overallElapsed : 0;
    wprintf(L"Overall rate:     %.0f entries/sec\n", overallRate);
    wprintf(L"Memory used:      %zu MB\n", memMB);
    wprintf(L"Output file:      %s\n", config.outputPath);
    wprintf(L"Error log:        %s\n", errorLogPath);
    wprintf(L"============================================================\n");

    return 0;
}

