// mftdirect.cpp - Direct MFT Parser for Space Utilization Reporting
//
// Reads raw NTFS volumes (\\.\C:) and parses MFT binary directly,
// producing identical CSV output to mftscan.exe. Requires administrator
// privileges but sees every file (zero access denied errors).
//
// Usage:
//   mftdirect.exe [options] [volume...]
//   mftdirect.exe C: D: --output results.csv
//   mftdirect.exe --allVolumes
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
static const size_t MAX_VOLUMES        = 64;
static const DWORD  MAX_THREADS        = 64;
static const size_t CSV_WRITE_BUF_SIZE = 4 * 1024 * 1024;
static const size_t ERR_WRITE_BUF_SIZE = 256 * 1024;
static const size_t MAX_ERROR_LOG      = 100;
static const size_t ROW_BUF_SIZE       = 200 * 1024;
static const DWORD  PROGRESS_INTERVAL  = 100000;
static const size_t MFT_READ_BUF_SIZE  = 1 * 1024 * 1024;
static const int    MAX_PATH_DEPTH     = 1000;
static const ULONGLONG SYSTEM_RECORD_LIMIT = 16;

static const char* TOOL_NAME    = "mftdirect";
static const char* TOOL_VERSION = "1.0";

struct VolumeInfo {
    WCHAR devicePath[128];      // "\\?\Volume{GUID}" or "\\.\C:" — for raw access
    WCHAR mountPath[MAX_PATH];  // "C:\" or "E:\Data2\DSS\" — with trailing backslash
    WCHAR displayName[MAX_PATH];// "C:" or "E:\Data2\DSS" — for CSV and console
};

struct VolumeScanResult {
    LONGLONG entryCount;
    LONGLONG directoryCount;
    LONGLONG fileCount;
    LONGLONG errorCount;
    double   durationSec;
};

// ============================================================================
// NTFS Constants
// ============================================================================

static const DWORD ATTR_STANDARD_INFORMATION = 0x10;
static const DWORD ATTR_ATTRIBUTE_LIST       = 0x20;
static const DWORD ATTR_FILE_NAME            = 0x30;
static const DWORD ATTR_DATA                 = 0x80;
static const DWORD ATTR_END_MARKER           = 0xFFFFFFFF;

static const USHORT MFT_RECORD_IN_USE      = 0x0001;
static const USHORT MFT_RECORD_IS_DIRECTORY = 0x0002;

static const UCHAR NS_POSIX    = 0;
static const UCHAR NS_WIN32    = 1;
static const UCHAR NS_DOS      = 2;
static const UCHAR NS_WIN32DOS = 3;

static const ULONGLONG MFT_RECORD_REF_MASK = 0x0000FFFFFFFFFFFFULL;

// ============================================================================
// Inline Byte-Offset Readers (unaligned access safe on x86/x64)
// ============================================================================

static inline USHORT ReadU16(const BYTE* p) { return *(const USHORT*)p; }
static inline ULONG  ReadU32(const BYTE* p) { return *(const ULONG*)p; }
static inline ULONGLONG ReadU64(const BYTE* p) { return *(const ULONGLONG*)p; }
static inline LONGLONG  ReadI64(const BYTE* p) { return *(const LONGLONG*)p; }

// ============================================================================
// Buffered File Writer (thread-safe, reused from mftscan)
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
    if (!w->buffer) return;
    DWORD written;
    EnterCriticalSection(&w->lock);

    if (len > w->bufferSize) {
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
// Statistics
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
// Utility Functions (reused from mftscan)
// ============================================================================

static const WCHAR* GetErrorDescription(DWORD errorCode) {
    switch (errorCode) {
        case ERROR_ACCESS_DENIED:     return L"Access denied";
        case ERROR_PATH_NOT_FOUND:    return L"Path not found";
        case ERROR_FILE_NOT_FOUND:    return L"File not found";
        case ERROR_SHARING_VIOLATION: return L"Sharing violation";
        case ERROR_INVALID_NAME:      return L"Invalid name";
        case ERROR_BUFFER_OVERFLOW:   return L"Path too long";
        case ERROR_DIRECTORY:         return L"Invalid directory";
        case ERROR_NOT_READY:         return L"Device not ready";
        case ERROR_INVALID_PARAMETER: return L"Invalid parameter";
        default:                      return L"Unknown error";
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

static void WriteErrorToLog(BufferedWriter* errLog, const WCHAR* path,
                            DWORD errorCode, const WCHAR* errorDesc) {
    SYSTEMTIME st;
    GetSystemTime(&st);

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
// Data Run List
// ============================================================================

struct DataRun {
    LONGLONG lcn;
    ULONGLONG length;
};

struct DataRunList {
    DataRun* runs;
    size_t count;
    size_t capacity;
};

static void DataRunList_Init(DataRunList* list) {
    list->capacity = 64;
    list->count = 0;
    list->runs = (DataRun*)HeapAlloc(GetProcessHeap(), 0, sizeof(DataRun) * list->capacity);
}

static void DataRunList_Add(DataRunList* list, LONGLONG lcn, ULONGLONG length) {
    if (list->count >= list->capacity) {
        size_t newCap = list->capacity * 2;
        DataRun* newRuns = (DataRun*)HeapAlloc(GetProcessHeap(), 0, sizeof(DataRun) * newCap);
        memcpy(newRuns, list->runs, sizeof(DataRun) * list->count);
        HeapFree(GetProcessHeap(), 0, list->runs);
        list->runs = newRuns;
        list->capacity = newCap;
    }
    list->runs[list->count].lcn = lcn;
    list->runs[list->count].length = length;
    list->count++;
}

static void DataRunList_Destroy(DataRunList* list) {
    if (list->runs) HeapFree(GetProcessHeap(), 0, list->runs);
    list->runs = NULL;
    list->count = 0;
    list->capacity = 0;
}

static ULONGLONG DataRunList_TotalBytes(DataRunList* list, DWORD bytesPerCluster) {
    ULONGLONG total = 0;
    for (size_t i = 0; i < list->count; i++)
        total += list->runs[i].length * bytesPerCluster;
    return total;
}

// ============================================================================
// Directory Hash Map (open-addressing, power-of-2 capacity)
// ============================================================================

struct DirEntry {
    ULONGLONG recordNum;     // 0 = empty slot
    ULONGLONG parentRecord;
    WCHAR* name;
    WCHAR* resolvedPath;     // NULL until resolved
    UCHAR nameSpace;
};

struct DirHashMap {
    DirEntry* entries;
    size_t capacity;
    size_t count;
    size_t mask;
};

static size_t DirHash(ULONGLONG key, size_t mask) {
    key *= 0x9E3779B97F4A7C15ULL;
    return (size_t)(key >> 32) & mask;
}

static void DirMap_Grow(DirHashMap* map);

static void DirMap_Init(DirHashMap* map, size_t initialCapacity) {
    size_t cap = 1;
    while (cap < initialCapacity) cap <<= 1;

    map->capacity = cap;
    map->mask = cap - 1;
    map->count = 0;
    map->entries = (DirEntry*)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                        sizeof(DirEntry) * cap);
}

static void DirMap_Destroy(DirHashMap* map) {
    for (size_t i = 0; i < map->capacity; i++) {
        if (map->entries[i].recordNum != 0) {
            if (map->entries[i].name) HeapFree(GetProcessHeap(), 0, map->entries[i].name);
            if (map->entries[i].resolvedPath) HeapFree(GetProcessHeap(), 0, map->entries[i].resolvedPath);
        }
    }
    HeapFree(GetProcessHeap(), 0, map->entries);
}

static int NamespacePriority(UCHAR ns) {
    switch (ns) {
        case NS_WIN32:    return 3;
        case NS_WIN32DOS: return 2;
        case NS_POSIX:    return 1;
        default:          return 0;
    }
}

static void DirMap_Insert(DirHashMap* map, ULONGLONG recordNum, ULONGLONG parentRecord,
                          const WCHAR* name, UCHAR nameSpace) {
    if (nameSpace == NS_DOS) return;

    if (map->count * 10 >= map->capacity * 7) {
        DirMap_Grow(map);
    }

    size_t idx = DirHash(recordNum, map->mask);
    while (map->entries[idx].recordNum != 0) {
        if (map->entries[idx].recordNum == recordNum) {
            if (NamespacePriority(nameSpace) > NamespacePriority(map->entries[idx].nameSpace)) {
                HeapFree(GetProcessHeap(), 0, map->entries[idx].name);
                size_t nameLen = wcslen(name) + 1;
                map->entries[idx].name = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, nameLen * sizeof(WCHAR));
                wcscpy(map->entries[idx].name, name);
                map->entries[idx].parentRecord = parentRecord;
                map->entries[idx].nameSpace = nameSpace;
            }
            return;
        }
        idx = (idx + 1) & map->mask;
    }

    map->entries[idx].recordNum = recordNum;
    map->entries[idx].parentRecord = parentRecord;
    size_t nameLen = wcslen(name) + 1;
    map->entries[idx].name = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, nameLen * sizeof(WCHAR));
    wcscpy(map->entries[idx].name, name);
    map->entries[idx].resolvedPath = NULL;
    map->entries[idx].nameSpace = nameSpace;
    map->count++;
}

static DirEntry* DirMap_Find(DirHashMap* map, ULONGLONG recordNum) {
    size_t idx = DirHash(recordNum, map->mask);
    while (map->entries[idx].recordNum != 0) {
        if (map->entries[idx].recordNum == recordNum) {
            return &map->entries[idx];
        }
        idx = (idx + 1) & map->mask;
    }
    return NULL;
}

static void DirMap_Grow(DirHashMap* map) {
    size_t oldCap = map->capacity;
    DirEntry* oldEntries = map->entries;

    size_t newCap = oldCap * 2;
    map->capacity = newCap;
    map->mask = newCap - 1;
    map->count = 0;
    map->entries = (DirEntry*)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
                                        sizeof(DirEntry) * newCap);

    for (size_t i = 0; i < oldCap; i++) {
        if (oldEntries[i].recordNum != 0) {
            size_t idx = DirHash(oldEntries[i].recordNum, map->mask);
            while (map->entries[idx].recordNum != 0) {
                idx = (idx + 1) & map->mask;
            }
            map->entries[idx] = oldEntries[i];
            map->count++;
        }
    }

    HeapFree(GetProcessHeap(), 0, oldEntries);
}

// ============================================================================
// NTFS Parsing: Update Sequence Fixup
// ============================================================================

static BOOL ApplyFixup(BYTE* record, DWORD recordSize, DWORD bytesPerSector) {
    if (record[0] != 'F' || record[1] != 'I' || record[2] != 'L' || record[3] != 'E')
        return FALSE;

    USHORT usOffset = ReadU16(record + 0x04);
    USHORT usSize   = ReadU16(record + 0x06);

    if (usSize < 2 || usOffset + (DWORD)usSize * 2 > recordSize)
        return FALSE;

    BYTE* usArray = record + usOffset;
    USHORT checkValue = ReadU16(usArray);

    DWORD sectorsPerRecord = recordSize / bytesPerSector;
    DWORD entriesToProcess = usSize - 1;
    if (entriesToProcess > sectorsPerRecord)
        entriesToProcess = sectorsPerRecord;

    for (DWORD i = 0; i < entriesToProcess; i++) {
        BYTE* sectorEnd = record + (i + 1) * bytesPerSector - 2;
        if (ReadU16(sectorEnd) != checkValue)
            return FALSE;
        USHORT replacement = ReadU16(usArray + 2 + i * 2);
        sectorEnd[0] = (BYTE)(replacement & 0xFF);
        sectorEnd[1] = (BYTE)(replacement >> 8);
    }
    return TRUE;
}

// ============================================================================
// NTFS Parsing: Data Run Decoding
// ============================================================================

static BOOL DecodeDataRuns(const BYTE* data, size_t maxLen, DataRunList* out) {
    size_t offset = 0;
    LONGLONG prevLcn = 0;

    while (offset < maxLen) {
        BYTE header = data[offset];
        if (header == 0) break;

        BYTE lengthSize = header & 0x0F;
        BYTE offsetSize = (header >> 4) & 0x0F;
        offset++;

        if (lengthSize == 0 || lengthSize > 8) break;
        if (offset + lengthSize + offsetSize > maxLen) break;

        // Read run length (unsigned)
        ULONGLONG runLength = 0;
        for (BYTE i = 0; i < lengthSize; i++)
            runLength |= ((ULONGLONG)data[offset + i]) << (i * 8);
        offset += lengthSize;

        if (offsetSize == 0) {
            // Sparse run - skip
            continue;
        }

        // Read run offset (signed, relative to previous LCN)
        LONGLONG runOffset = 0;
        for (BYTE i = 0; i < offsetSize; i++)
            runOffset |= ((LONGLONG)data[offset + i]) << (i * 8);
        // Sign-extend
        if (data[offset + offsetSize - 1] & 0x80) {
            for (BYTE i = offsetSize; i < 8; i++)
                runOffset |= ((LONGLONG)0xFF) << (i * 8);
        }
        offset += offsetSize;

        LONGLONG absoluteLcn = prevLcn + runOffset;
        prevLcn = absoluteLcn;

        DataRunList_Add(out, absoluteLcn, runLength);
    }
    return out->count > 0;
}

// ============================================================================
// Volume Reading Helpers
// ============================================================================

static BOOL ReadMftRecordByNumber(HANDLE hVolume, DataRunList* runs,
                                  ULONGLONG recordNum, BYTE* buffer,
                                  DWORD bytesPerMftRecord, DWORD bytesPerCluster) {
    ULONGLONG logicalOffset = recordNum * bytesPerMftRecord;
    ULONGLONG runStartOffset = 0;

    for (size_t i = 0; i < runs->count; i++) {
        ULONGLONG runBytes = runs->runs[i].length * bytesPerCluster;

        if (logicalOffset < runStartOffset + runBytes) {
            ULONGLONG offsetInRun = logicalOffset - runStartOffset;
            LONGLONG physicalOffset = runs->runs[i].lcn * bytesPerCluster + (LONGLONG)offsetInRun;

            LARGE_INTEGER seekPos;
            seekPos.QuadPart = physicalOffset;
            if (!SetFilePointerEx(hVolume, seekPos, NULL, FILE_BEGIN))
                return FALSE;

            DWORD actualRead = 0;
            if (!ReadFile(hVolume, buffer, bytesPerMftRecord, &actualRead, NULL))
                return FALSE;
            return actualRead >= bytesPerMftRecord;
        }

        runStartOffset += runBytes;
    }

    return FALSE;
}

// ============================================================================
// Boot Sector Parsing
// ============================================================================

static BOOL ParseBootSector(HANDLE hVolume, DWORD* outBytesPerSector,
                            DWORD* outBytesPerCluster, DWORD* outBytesPerMftRecord,
                            LONGLONG* outMftStartLcn) {
    BYTE* bootBuf = (BYTE*)VirtualAlloc(NULL, 4096, MEM_COMMIT, PAGE_READWRITE);
    if (!bootBuf) return FALSE;

    LARGE_INTEGER seekPos;
    seekPos.QuadPart = 0;
    SetFilePointerEx(hVolume, seekPos, NULL, FILE_BEGIN);

    DWORD actualRead = 0;
    if (!ReadFile(hVolume, bootBuf, 4096, &actualRead, NULL) || actualRead < 512) {
        VirtualFree(bootBuf, 0, MEM_RELEASE);
        return FALSE;
    }

    if (memcmp(bootBuf + 3, "NTFS    ", 8) != 0) {
        VirtualFree(bootBuf, 0, MEM_RELEASE);
        return FALSE;
    }

    *outBytesPerSector = ReadU16(bootBuf + 0x0B);
    UCHAR sectorsPerCluster = bootBuf[0x0D];
    *outBytesPerCluster = (*outBytesPerSector) * sectorsPerCluster;
    *outMftStartLcn = ReadI64(bootBuf + 0x30);

    signed char clustersPerRecord = (signed char)bootBuf[0x40];
    if (clustersPerRecord > 0) {
        *outBytesPerMftRecord = (DWORD)(clustersPerRecord * (*outBytesPerCluster));
    } else {
        *outBytesPerMftRecord = 1u << (DWORD)(-clustersPerRecord);
    }

    VirtualFree(bootBuf, 0, MEM_RELEASE);
    return TRUE;
}

// ============================================================================
// Build MFT Data Run List from Record 0 (with $ATTRIBUTE_LIST support)
// ============================================================================

static BOOL BuildMftDataRunList(HANDLE hVolume, LONGLONG mftStartLcn,
                                DWORD bytesPerCluster, DWORD bytesPerMftRecord,
                                DWORD bytesPerSector, DataRunList* outRuns,
                                ULONGLONG* outDataRealSize) {
    BYTE* recordBuf = (BYTE*)VirtualAlloc(NULL, bytesPerMftRecord, MEM_COMMIT, PAGE_READWRITE);
    if (!recordBuf) return FALSE;

    // Read MFT record 0 at known physical location
    LONGLONG mftByteOffset = mftStartLcn * bytesPerCluster;
    LARGE_INTEGER seekPos;
    seekPos.QuadPart = mftByteOffset;
    if (!SetFilePointerEx(hVolume, seekPos, NULL, FILE_BEGIN)) {
        VirtualFree(recordBuf, 0, MEM_RELEASE);
        return FALSE;
    }

    DWORD actualRead = 0;
    if (!ReadFile(hVolume, recordBuf, bytesPerMftRecord, &actualRead, NULL) ||
        actualRead < bytesPerMftRecord) {
        VirtualFree(recordBuf, 0, MEM_RELEASE);
        return FALSE;
    }

    if (!ApplyFixup(recordBuf, bytesPerMftRecord, bytesPerSector)) {
        VirtualFree(recordBuf, 0, MEM_RELEASE);
        return FALSE;
    }

    // Parse attributes in record 0
    DataRunList_Init(outRuns);
    *outDataRealSize = 0;
    BOOL foundData = FALSE;

    // Track $ATTRIBUTE_LIST location
    BOOL hasAttrList = FALSE;
    BOOL attrListNonResident = FALSE;
    DWORD attrListOffset = 0;  // Offset within recordBuf

    USHORT firstAttrOffset = ReadU16(recordBuf + 0x14);
    DWORD offset = firstAttrOffset;

    while (offset + 24 <= bytesPerMftRecord) {
        DWORD attrType = ReadU32(recordBuf + offset);
        if (attrType == ATTR_END_MARKER || attrType == 0) break;

        DWORD attrLength = ReadU32(recordBuf + offset + 4);
        if (attrLength < 16 || offset + attrLength > bytesPerMftRecord) break;

        UCHAR nonResident = recordBuf[offset + 8];
        UCHAR nameLength = recordBuf[offset + 9];

        if (attrType == ATTR_DATA && nameLength == 0 && !foundData) {
            if (nonResident) {
                USHORT dataRunsOff = ReadU16(recordBuf + offset + 0x20);
                *outDataRealSize = ReadU64(recordBuf + offset + 0x30);
                DecodeDataRuns(recordBuf + offset + dataRunsOff,
                               attrLength - dataRunsOff, outRuns);
                foundData = TRUE;
            }
        }
        else if (attrType == ATTR_ATTRIBUTE_LIST) {
            hasAttrList = TRUE;
            attrListNonResident = nonResident != 0;
            attrListOffset = offset;
        }

        offset += attrLength;
    }

    // Process $ATTRIBUTE_LIST for additional $DATA extents
    if (hasAttrList && foundData) {
        BYTE* alData = NULL;
        ULONG alSize = 0;

        if (!attrListNonResident) {
            ULONG valLen = ReadU32(recordBuf + attrListOffset + 0x10);
            USHORT valOff = ReadU16(recordBuf + attrListOffset + 0x14);
            alSize = valLen;
            alData = (BYTE*)HeapAlloc(GetProcessHeap(), 0, alSize);
            if (alData) memcpy(alData, recordBuf + attrListOffset + valOff, alSize);
        } else {
            // Non-resident attribute list
            USHORT alRunsOff = ReadU16(recordBuf + attrListOffset + 0x20);
            ULONGLONG alRealSize = ReadU64(recordBuf + attrListOffset + 0x30);
            ULONG alAttrLen = ReadU32(recordBuf + attrListOffset + 4);

            DataRunList alRuns;
            DataRunList_Init(&alRuns);
            DecodeDataRuns(recordBuf + attrListOffset + alRunsOff,
                           alAttrLen - alRunsOff, &alRuns);

            alSize = (ULONG)alRealSize;
            ULONGLONG totalClusterBytes = DataRunList_TotalBytes(&alRuns, bytesPerCluster);
            BYTE* clusterBuf = (BYTE*)VirtualAlloc(NULL, (SIZE_T)totalClusterBytes,
                                                    MEM_COMMIT, PAGE_READWRITE);
            if (clusterBuf) {
                size_t bytesReadTotal = 0;
                for (size_t i = 0; i < alRuns.count; i++) {
                    LONGLONG physOff = alRuns.runs[i].lcn * bytesPerCluster;
                    DWORD runBytes = (DWORD)(alRuns.runs[i].length * bytesPerCluster);

                    seekPos.QuadPart = physOff;
                    SetFilePointerEx(hVolume, seekPos, NULL, FILE_BEGIN);
                    DWORD rd = 0;
                    ReadFile(hVolume, clusterBuf + bytesReadTotal, runBytes, &rd, NULL);
                    bytesReadTotal += rd;
                }

                alData = (BYTE*)HeapAlloc(GetProcessHeap(), 0, alSize);
                if (alData) memcpy(alData, clusterBuf, alSize);
                VirtualFree(clusterBuf, 0, MEM_RELEASE);
            }

            DataRunList_Destroy(&alRuns);
        }

        // Parse attribute list entries for additional $DATA extents
        if (alData) {
            BYTE* extRecord = (BYTE*)VirtualAlloc(NULL, bytesPerMftRecord,
                                                   MEM_COMMIT, PAGE_READWRITE);
            ULONG alOffset = 0;
            while (alOffset + 26 <= alSize) {
                DWORD entryType = ReadU32(alData + alOffset);
                USHORT entryLength = ReadU16(alData + alOffset + 4);
                if (entryLength < 26 || alOffset + entryLength > alSize) break;

                ULONGLONG baseRecord = ReadU64(alData + alOffset + 16) & MFT_RECORD_REF_MASK;
                LONGLONG startVcn = ReadI64(alData + alOffset + 8);

                if (entryType == ATTR_DATA && baseRecord != 0 && startVcn > 0 && extRecord) {
                    // Read extension record
                    if (ReadMftRecordByNumber(hVolume, outRuns, baseRecord, extRecord,
                                             bytesPerMftRecord, bytesPerCluster)) {
                        if (ApplyFixup(extRecord, bytesPerMftRecord, bytesPerSector)) {
                            USHORT extFirstAttr = ReadU16(extRecord + 0x14);
                            DWORD extOff = extFirstAttr;

                            while (extOff + 24 <= bytesPerMftRecord) {
                                DWORD extType = ReadU32(extRecord + extOff);
                                if (extType == ATTR_END_MARKER || extType == 0) break;

                                DWORD extLen = ReadU32(extRecord + extOff + 4);
                                if (extLen < 16 || extOff + extLen > bytesPerMftRecord) break;

                                if (extType == ATTR_DATA) {
                                    UCHAR extNR = extRecord[extOff + 8];
                                    UCHAR extNL = extRecord[extOff + 9];
                                    if (extNR && extNL == 0) {
                                        USHORT extRunsOff = ReadU16(extRecord + extOff + 0x20);
                                        DecodeDataRuns(extRecord + extOff + extRunsOff,
                                                       extLen - extRunsOff, outRuns);
                                    }
                                }

                                extOff += extLen;
                            }
                        }
                    }
                }

                alOffset += entryLength;
            }
            if (extRecord) VirtualFree(extRecord, 0, MEM_RELEASE);
            HeapFree(GetProcessHeap(), 0, alData);
        }
    }

    VirtualFree(recordBuf, 0, MEM_RELEASE);
    return outRuns->count > 0;
}

// ============================================================================
// Sequential MFT Record Reading
// ============================================================================

typedef BOOL (*MftRecordCallback)(ULONGLONG recordNum, BYTE* record,
                                  DWORD recordSize, void* context);

static BOOL ReadAllMftRecords(HANDLE hVolume, DataRunList* runs,
                              DWORD bytesPerCluster, DWORD bytesPerMftRecord,
                              ULONGLONG totalRecords,
                              MftRecordCallback callback, void* context) {
    BYTE* readBuf = (BYTE*)VirtualAlloc(NULL, MFT_READ_BUF_SIZE,
                                         MEM_COMMIT, PAGE_READWRITE);
    if (!readBuf) return FALSE;

    ULONGLONG currentRecord = 0;

    for (size_t runIdx = 0; runIdx < runs->count && currentRecord < totalRecords; runIdx++) {
        LONGLONG runStartByte = runs->runs[runIdx].lcn * bytesPerCluster;
        ULONGLONG runTotalBytes = runs->runs[runIdx].length * bytesPerCluster;
        ULONGLONG runBytesRead = 0;

        while (runBytesRead < runTotalBytes && currentRecord < totalRecords) {
            ULONGLONG remaining = runTotalBytes - runBytesRead;
            DWORD toRead = (DWORD)min((ULONGLONG)MFT_READ_BUF_SIZE, remaining);
            // Round down to record boundary
            toRead = (toRead / bytesPerMftRecord) * bytesPerMftRecord;
            if (toRead == 0) break;

            LARGE_INTEGER seekPos;
            seekPos.QuadPart = runStartByte + (LONGLONG)runBytesRead;
            if (!SetFilePointerEx(hVolume, seekPos, NULL, FILE_BEGIN))
                break;

            DWORD actualRead = 0;
            if (!ReadFile(hVolume, readBuf, toRead, &actualRead, NULL) || actualRead == 0)
                break;

            DWORD offset = 0;
            while (offset + bytesPerMftRecord <= actualRead && currentRecord < totalRecords) {
                BYTE* rec = readBuf + offset;

                if (!callback(currentRecord, rec, bytesPerMftRecord, context)) {
                    VirtualFree(readBuf, 0, MEM_RELEASE);
                    return FALSE;
                }

                offset += bytesPerMftRecord;
                currentRecord++;
            }

            runBytesRead += actualRead;
        }
    }

    VirtualFree(readBuf, 0, MEM_RELEASE);
    return TRUE;
}

// ============================================================================
// Pass 1: Index Directories
// ============================================================================

struct Pass1Context {
    DirHashMap* dirMap;
    DWORD bytesPerSector;
    ULONGLONG recordsProcessed;
    ULONGLONG dirsFound;
    LARGE_INTEGER startTime;
    LARGE_INTEGER freq;
};

static BOOL Pass1Callback(ULONGLONG recordNum, BYTE* record,
                          DWORD recordSize, void* ctx) {
    Pass1Context* p = (Pass1Context*)ctx;
    p->recordsProcessed++;

    if (p->recordsProcessed % PROGRESS_INTERVAL == 0) {
        double elapsed = GetElapsedSeconds(p->startTime, p->freq);
        SIZE_T memMB = GetMemoryUsageMB();
        wprintf(L"  Pass 1: %llu records, %llu dirs (%zu MB, %.0f/sec)    \r",
                p->recordsProcessed, p->dirsFound, memMB,
                elapsed > 0 ? (double)p->recordsProcessed / elapsed : 0);
    }

    if (record[0] != 'F' || record[1] != 'I' || record[2] != 'L' || record[3] != 'E')
        return TRUE;

    if (!ApplyFixup(record, recordSize, p->bytesPerSector))
        return TRUE;

    USHORT flags = ReadU16(record + 0x16);
    if (!(flags & MFT_RECORD_IN_USE)) return TRUE;
    if (!(flags & MFT_RECORD_IS_DIRECTORY)) return TRUE;

    // Skip extension records
    ULONGLONG baseRef = ReadU64(record + 0x20) & MFT_RECORD_REF_MASK;
    if (baseRef != 0) return TRUE;

    // Find best $FILE_NAME
    USHORT firstAttrOffset = ReadU16(record + 0x14);
    DWORD offset = firstAttrOffset;

    WCHAR bestName[256];
    bestName[0] = L'\0';
    ULONGLONG bestParent = 0;
    UCHAR bestNS = NS_DOS;
    int bestPriority = -1;

    while (offset + 24 <= recordSize) {
        DWORD attrType = ReadU32(record + offset);
        if (attrType == ATTR_END_MARKER || attrType == 0) break;

        DWORD attrLength = ReadU32(record + offset + 4);
        if (attrLength < 16 || offset + attrLength > recordSize) break;

        if (attrType == ATTR_FILE_NAME && record[offset + 8] == 0) {
            ULONG valueLength = ReadU32(record + offset + 0x10);
            USHORT valueOffset = ReadU16(record + offset + 0x14);

            if (offset + valueOffset + 0x42 <= recordSize && valueLength >= 0x42) {
                const BYTE* fn = record + offset + valueOffset;
                ULONGLONG parentRef = ReadU64(fn) & MFT_RECORD_REF_MASK;
                UCHAR nameLen = fn[0x40];
                UCHAR ns = fn[0x41];

                int priority = NamespacePriority(ns);
                if (priority > bestPriority && nameLen > 0 && nameLen < 255 && ns != NS_DOS) {
                    bestPriority = priority;
                    bestParent = parentRef;
                    bestNS = ns;
                    memcpy(bestName, fn + 0x42, nameLen * sizeof(WCHAR));
                    bestName[nameLen] = L'\0';
                }
            }
        }

        offset += attrLength;
    }

    if (bestPriority >= 0) {
        DirMap_Insert(p->dirMap, recordNum, bestParent, bestName, bestNS);
        p->dirsFound++;
    }

    return TRUE;
}

// ============================================================================
// Path Resolution
// ============================================================================

static void ResolveSinglePath(DirHashMap* map, DirEntry* entry, const WCHAR* volumePrefix) {
    if (entry->resolvedPath) return;

    ULONGLONG stack[MAX_PATH_DEPTH];
    int depth = 0;

    ULONGLONG current = entry->recordNum;
    while (depth < MAX_PATH_DEPTH) {
        DirEntry* dir = DirMap_Find(map, current);
        if (!dir) break;
        if (dir->resolvedPath) break;

        stack[depth++] = current;

        if (current == dir->parentRecord) break;  // Root (self-ref)
        current = dir->parentRecord;
    }

    if (depth == 0) return;

    // Determine base path
    WCHAR basePath[MAX_PATH_LEN];
    ULONGLONG topRecord = stack[depth - 1];
    DirEntry* topDir = DirMap_Find(map, topRecord);

    if (topDir && topDir->recordNum == topDir->parentRecord) {
        // Root directory
        wcscpy(basePath, volumePrefix);
        size_t len = wcslen(basePath) + 1;
        topDir->resolvedPath = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, len * sizeof(WCHAR));
        wcscpy(topDir->resolvedPath, basePath);
        depth--;
    } else {
        DirEntry* ancestorDir = DirMap_Find(map, current);
        if (ancestorDir && ancestorDir->resolvedPath) {
            wcscpy(basePath, ancestorDir->resolvedPath);
        } else {
            swprintf(basePath, MAX_PATH_LEN, L"%s$ORPHAN", volumePrefix);
        }
    }

    // Resolve remaining stack entries top-down
    for (int i = depth - 1; i >= 0; i--) {
        DirEntry* dir = DirMap_Find(map, stack[i]);
        if (!dir || dir->resolvedPath) continue;

        size_t baseLen = wcslen(basePath);
        if (baseLen > 0 && basePath[baseLen - 1] != L'\\') {
            wcscat(basePath, L"\\");
        }
        wcscat(basePath, dir->name);

        size_t resolvedLen = wcslen(basePath) + 1;
        dir->resolvedPath = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, resolvedLen * sizeof(WCHAR));
        wcscpy(dir->resolvedPath, basePath);
    }
}

static void ResolveAllPaths(DirHashMap* map, const WCHAR* volumePrefix) {
    for (size_t i = 0; i < map->capacity; i++) {
        if (map->entries[i].recordNum != 0 && !map->entries[i].resolvedPath) {
            ResolveSinglePath(map, &map->entries[i], volumePrefix);
        }
    }
}

// ============================================================================
// Pass 2: Emit CSV
// ============================================================================

struct Pass2Context {
    DirHashMap* dirMap;
    BufferedWriter* csv;
    BufferedWriter* errLog;
    ScanStats* stats;
    const char* volumeUtf8;
    ULONGLONG minSizeBytes;
    DWORD bytesPerSector;
    ULONGLONG recordsProcessed;
    LARGE_INTEGER startTime;
    LARGE_INTEGER freq;
    // Pre-allocated buffers
    char* rowBuffer;
    char* utf8Path;
    char* utf8Name;
    char* quotedPath;
    char* quotedName;
    WCHAR* fullPath;
};

static BOOL Pass2Callback(ULONGLONG recordNum, BYTE* record,
                          DWORD recordSize, void* ctx) {
    Pass2Context* p = (Pass2Context*)ctx;
    p->recordsProcessed++;

    if (p->recordsProcessed % PROGRESS_INTERVAL == 0) {
        double elapsed = GetElapsedSeconds(p->startTime, p->freq);
        wprintf(L"  Pass 2: %llu records, %lld entries (%.0f/sec)    \r",
                p->recordsProcessed, p->stats->totalEntries,
                elapsed > 0 ? (double)p->recordsProcessed / elapsed : 0);
    }

    if (record[0] != 'F' || record[1] != 'I' || record[2] != 'L' || record[3] != 'E')
        return TRUE;

    if (!ApplyFixup(record, recordSize, p->bytesPerSector))
        return TRUE;

    USHORT flags = ReadU16(record + 0x16);
    if (!(flags & MFT_RECORD_IN_USE)) return TRUE;

    ULONGLONG baseRef = ReadU64(record + 0x20) & MFT_RECORD_REF_MASK;
    if (baseRef != 0) return TRUE;

    if (recordNum < SYSTEM_RECORD_LIMIT) return TRUE;

    BOOL isDir = (flags & MFT_RECORD_IS_DIRECTORY) != 0;

    // Parse $STANDARD_INFORMATION for timestamps and attributes
    FILETIME siCreated = {0,0}, siModified = {0,0}, siAccessed = {0,0};
    DWORD siAttributes = 0;
    BOOL hasStdInfo = FALSE;

    // Parse $DATA for file size
    ULONGLONG dataSize = 0;
    BOOL hasData = FALSE;

    USHORT firstAttrOffset = ReadU16(record + 0x14);
    DWORD offset = firstAttrOffset;

    while (offset + 24 <= recordSize) {
        DWORD attrType = ReadU32(record + offset);
        if (attrType == ATTR_END_MARKER || attrType == 0) break;

        DWORD attrLength = ReadU32(record + offset + 4);
        if (attrLength < 16 || offset + attrLength > recordSize) break;

        UCHAR nonResident = record[offset + 8];
        UCHAR nameLength = record[offset + 9];

        if (attrType == ATTR_STANDARD_INFORMATION && !hasStdInfo && !nonResident) {
            USHORT valOff = ReadU16(record + offset + 0x14);
            ULONG valLen = ReadU32(record + offset + 0x10);
            if (valLen >= 0x24 && offset + valOff + 0x24 <= recordSize) {
                const BYTE* si = record + offset + valOff;
                memcpy(&siCreated, si + 0x00, sizeof(FILETIME));
                memcpy(&siModified, si + 0x08, sizeof(FILETIME));
                memcpy(&siAccessed, si + 0x18, sizeof(FILETIME));
                siAttributes = ReadU32(si + 0x20);
                hasStdInfo = TRUE;
            }
        }
        else if (attrType == ATTR_DATA && !hasData && nameLength == 0) {
            if (nonResident) {
                if (offset + 0x38 <= recordSize) {
                    dataSize = ReadU64(record + offset + 0x30);
                }
            } else {
                dataSize = ReadU32(record + offset + 0x10);
            }
            hasData = TRUE;
        }

        offset += attrLength;
    }

    // Iterate $FILE_NAME attributes and output one row per non-DOS name
    offset = firstAttrOffset;
    while (offset + 24 <= recordSize) {
        DWORD attrType = ReadU32(record + offset);
        if (attrType == ATTR_END_MARKER || attrType == 0) break;

        DWORD attrLength = ReadU32(record + offset + 4);
        if (attrLength < 16 || offset + attrLength > recordSize) break;

        if (attrType == ATTR_FILE_NAME && record[offset + 8] == 0) {
            ULONG valLen = ReadU32(record + offset + 0x10);
            USHORT valOff = ReadU16(record + offset + 0x14);

            if (valLen >= 0x42 && offset + valOff + 0x42 <= recordSize) {
                const BYTE* fn = record + offset + valOff;
                ULONGLONG parentRef = ReadU64(fn) & MFT_RECORD_REF_MASK;
                UCHAR fnNameLen = fn[0x40];
                UCHAR ns = fn[0x41];

                if (ns != NS_DOS && fnNameLen > 0 && fnNameLen < 255) {
                    WCHAR fileName[256];
                    memcpy(fileName, fn + 0x42, fnNameLen * sizeof(WCHAR));
                    fileName[fnNameLen] = L'\0';

                    // Look up parent path
                    const WCHAR* parentPath = L"$ORPHAN";
                    DirEntry* parentDir = DirMap_Find(p->dirMap, parentRef);
                    if (parentDir && parentDir->resolvedPath) {
                        parentPath = parentDir->resolvedPath;
                    }

                    // Build full path
                    size_t parentLen = wcslen(parentPath);
                    size_t fnWideLen = wcslen(fileName);
                    if (parentLen + 1 + fnWideLen < MAX_PATH_LEN) {
                        wcscpy(p->fullPath, parentPath);
                        if (parentLen > 0 && parentPath[parentLen - 1] != L'\\') {
                            wcscat(p->fullPath, L"\\");
                        }
                        wcscat(p->fullPath, fileName);
                    } else {
                        wcscpy(p->fullPath, L"\\\\?\\PATH_TOO_LONG");
                    }

                    // Apply minSize filter (files only)
                    if (!isDir && p->minSizeBytes > 0 && dataSize < p->minSizeBytes) {
                        offset += attrLength;
                        continue;
                    }

                    // Convert timestamps
                    char createdStr[32], modifiedStr[32], accessedStr[32];
                    FileTimeToIso8601(&siCreated, createdStr, sizeof(createdStr));
                    FileTimeToIso8601(&siModified, modifiedStr, sizeof(modifiedStr));
                    FileTimeToIso8601(&siAccessed, accessedStr, sizeof(accessedStr));

                    // Convert to UTF-8
                    WideCharToMultiByte(CP_UTF8, 0, p->fullPath, -1,
                                        p->utf8Path, (int)(MAX_PATH_LEN * 3), NULL, NULL);
                    WideCharToMultiByte(CP_UTF8, 0, fileName, -1,
                                        p->utf8Name, 2048, NULL, NULL);

                    // CSV-quote
                    int qpLen = CsvQuoteUtf8(p->quotedPath, MAX_PATH_LEN * 6, p->utf8Path);
                    int qnLen = CsvQuoteUtf8(p->quotedName, 4096, p->utf8Name);

                    // Build CSV row
                    int pos = 0;
                    char* row = p->rowBuffer;

                    // Volume
                    int vlLen = (int)strlen(p->volumeUtf8);
                    memcpy(row + pos, p->volumeUtf8, vlLen); pos += vlLen;
                    row[pos++] = ',';

                    // FullPath
                    memcpy(row + pos, p->quotedPath, qpLen); pos += qpLen;
                    row[pos++] = ',';

                    // FileName
                    memcpy(row + pos, p->quotedName, qnLen); pos += qnLen;
                    row[pos++] = ',';

                    // FileSize (empty for directories)
                    if (!isDir) {
                        pos += snprintf(row + pos, ROW_BUF_SIZE - pos, "%llu", dataSize);
                    }
                    row[pos++] = ',';

                    // CreatedTime
                    int cl = (int)strlen(createdStr);
                    memcpy(row + pos, createdStr, cl); pos += cl;
                    row[pos++] = ',';

                    // ModifiedTime
                    int ml = (int)strlen(modifiedStr);
                    memcpy(row + pos, modifiedStr, ml); pos += ml;
                    row[pos++] = ',';

                    // AccessedTime
                    int al = (int)strlen(accessedStr);
                    memcpy(row + pos, accessedStr, al); pos += al;
                    row[pos++] = ',';

                    // IsDirectory
                    row[pos++] = isDir ? '1' : '0';
                    row[pos++] = ',';

                    // Attributes
                    pos += snprintf(row + pos, ROW_BUF_SIZE - pos, "%lu", siAttributes);

                    // CRLF
                    row[pos++] = '\r';
                    row[pos++] = '\n';

                    BufferedWriter_Write(p->csv, row, (size_t)pos);

                    InterlockedIncrement64(&p->stats->totalEntries);
                    if (isDir) {
                        InterlockedIncrement64(&p->stats->dirCount);
                    } else {
                        InterlockedIncrement64(&p->stats->fileCount);
                    }
                }
            }
        }

        offset += attrLength;
    }

    return TRUE;
}

// ============================================================================
// Scan a Single Volume (Direct MFT Parsing)
// ============================================================================

static int ScanVolumeDirect(const VolumeInfo* vol, BufferedWriter* csv,
                            BufferedWriter* errLog, ULONGLONG minSizeBytes,
                            VolumeScanResult* outResult) {

    wprintf(L"\nScanning: %s (direct MFT parsing)\n", vol->displayName);
    wprintf(L"------------------------------------------------------------\n");

    LARGE_INTEGER startTime, freq;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&startTime);

    // Convert display name to UTF-8 for CSV Volume column
    char volumeUtf8[MAX_PATH * 3];
    WideCharToMultiByte(CP_UTF8, 0, vol->displayName, -1,
                        volumeUtf8, sizeof(volumeUtf8), NULL, NULL);

    // Open raw volume
    HANDLE hVolume = CreateFileW(vol->devicePath, GENERIC_READ,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  NULL, OPEN_EXISTING, 0, NULL);
    if (hVolume == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        wprintf(L"  Error: Cannot open volume %s (error %lu)\n", vol->devicePath, err);
        if (err == ERROR_ACCESS_DENIED) {
            wprintf(L"  Hint: Run as Administrator\n");
        }
        return 1;
    }

    // Parse boot sector
    DWORD bytesPerSector, bytesPerCluster, bytesPerMftRecord;
    LONGLONG mftStartLcn;

    if (!ParseBootSector(hVolume, &bytesPerSector, &bytesPerCluster,
                          &bytesPerMftRecord, &mftStartLcn)) {
        wprintf(L"  Error: Failed to parse NTFS boot sector on %s\n", vol->displayName);
        CloseHandle(hVolume);
        return 1;
    }

    wprintf(L"  Sector size:     %lu bytes\n", bytesPerSector);
    wprintf(L"  Cluster size:    %lu bytes\n", bytesPerCluster);
    wprintf(L"  MFT record size: %lu bytes\n", bytesPerMftRecord);
    wprintf(L"  MFT start LCN:   %lld\n", mftStartLcn);

    // Build MFT data run list
    DataRunList mftRuns;
    ULONGLONG dataRealSize = 0;

    if (!BuildMftDataRunList(hVolume, mftStartLcn, bytesPerCluster,
                              bytesPerMftRecord, bytesPerSector,
                              &mftRuns, &dataRealSize)) {
        wprintf(L"  Error: Failed to build MFT data run list on %s\n", vol->displayName);
        CloseHandle(hVolume);
        return 1;
    }

    ULONGLONG totalRecords = dataRealSize / bytesPerMftRecord;
    wprintf(L"  MFT size:        ");
    WCHAR sizeStr[64];
    FormatSize(dataRealSize, sizeStr, 64);
    wprintf(L"%s (%llu records in %zu extents)\n", sizeStr, totalRecords, mftRuns.count);

    // Build volume prefix for path resolution: "\\?\C:\" or "\\?\E:\Data2\DSS\"
    WCHAR volumePrefix[MAX_PATH + 8];
    swprintf(volumePrefix, MAX_PATH + 8, L"\\\\?\\%s", vol->mountPath);

    // ---- Pass 1: Index Directories ----
    wprintf(L"\n  Pass 1: Indexing directories...\n");

    DirHashMap dirMap;
    DirMap_Init(&dirMap, 65536);

    Pass1Context p1;
    p1.dirMap = &dirMap;
    p1.bytesPerSector = bytesPerSector;
    p1.recordsProcessed = 0;
    p1.dirsFound = 0;
    QueryPerformanceCounter(&p1.startTime);
    p1.freq = freq;

    ReadAllMftRecords(hVolume, &mftRuns, bytesPerCluster, bytesPerMftRecord,
                      totalRecords, Pass1Callback, &p1);

    double pass1Elapsed = GetElapsedSeconds(p1.startTime, freq);
    wprintf(L"  Pass 1 done: %llu records, %llu directories (%.1f sec)       \n",
            p1.recordsProcessed, p1.dirsFound, pass1Elapsed);

    // Resolve directory paths
    wprintf(L"  Resolving directory paths...\n");
    ResolveAllPaths(&dirMap, volumePrefix);
    wprintf(L"  Path resolution complete (%zu MB RAM)\n", GetMemoryUsageMB());

    // ---- Pass 2: Emit CSV ----
    wprintf(L"\n  Pass 2: Writing CSV...\n");

    ScanStats stats;
    Stats_Init(&stats);

    Pass2Context p2;
    memset(&p2, 0, sizeof(p2));
    p2.dirMap = &dirMap;
    p2.csv = csv;
    p2.errLog = errLog;
    p2.stats = &stats;
    p2.volumeUtf8 = volumeUtf8;
    p2.minSizeBytes = minSizeBytes;
    p2.bytesPerSector = bytesPerSector;
    p2.recordsProcessed = 0;
    QueryPerformanceCounter(&p2.startTime);
    p2.freq = freq;

    // Allocate pass 2 buffers
    p2.rowBuffer  = (char*)HeapAlloc(GetProcessHeap(), 0, ROW_BUF_SIZE);
    p2.utf8Path   = (char*)HeapAlloc(GetProcessHeap(), 0, MAX_PATH_LEN * 3);
    p2.utf8Name   = (char*)HeapAlloc(GetProcessHeap(), 0, 2048);
    p2.quotedPath = (char*)HeapAlloc(GetProcessHeap(), 0, MAX_PATH_LEN * 6);
    p2.quotedName = (char*)HeapAlloc(GetProcessHeap(), 0, 4096);
    p2.fullPath   = (WCHAR*)HeapAlloc(GetProcessHeap(), 0, MAX_PATH_LEN * sizeof(WCHAR));

    if (!p2.rowBuffer || !p2.utf8Path || !p2.utf8Name ||
        !p2.quotedPath || !p2.quotedName || !p2.fullPath) {
        wprintf(L"  Error: Failed to allocate pass 2 buffers\n");
    } else {
        ReadAllMftRecords(hVolume, &mftRuns, bytesPerCluster, bytesPerMftRecord,
                          totalRecords, Pass2Callback, &p2);
    }

    double pass2Elapsed = GetElapsedSeconds(p2.startTime, freq);
    double totalElapsed = GetElapsedSeconds(startTime, freq);

    // Free pass 2 buffers
    if (p2.rowBuffer)  HeapFree(GetProcessHeap(), 0, p2.rowBuffer);
    if (p2.utf8Path)   HeapFree(GetProcessHeap(), 0, p2.utf8Path);
    if (p2.utf8Name)   HeapFree(GetProcessHeap(), 0, p2.utf8Name);
    if (p2.quotedPath) HeapFree(GetProcessHeap(), 0, p2.quotedPath);
    if (p2.quotedName) HeapFree(GetProcessHeap(), 0, p2.quotedName);
    if (p2.fullPath)   HeapFree(GetProcessHeap(), 0, p2.fullPath);

    // Print volume summary
    wprintf(L"\n  Volume:               %s\n", vol->displayName);
    wprintf(L"  MFT records:          %llu\n", totalRecords);
    wprintf(L"  Directories indexed:  %llu\n", p1.dirsFound);
    wprintf(L"  Total entries:        %lld\n", stats.totalEntries);
    wprintf(L"    - Directories:      %lld\n", stats.dirCount);
    wprintf(L"    - Files:            %lld\n", stats.fileCount);
    wprintf(L"    - Errors:           %lld\n", stats.errors);
    wprintf(L"  Pass 1 (index):       %.1f seconds\n", pass1Elapsed);
    wprintf(L"  Pass 2 (CSV):         %.1f seconds\n", pass2Elapsed);
    wprintf(L"  Total elapsed:        %.1f seconds\n", totalElapsed);

    double rate = (totalElapsed > 0) ? (double)stats.totalEntries / totalElapsed : 0;
    wprintf(L"  Rate:                 %.0f entries/sec\n", rate);

    PrintErrors(&stats);

    if (outResult) {
        outResult->entryCount     = stats.totalEntries;
        outResult->directoryCount = stats.dirCount;
        outResult->fileCount      = stats.fileCount;
        outResult->errorCount     = stats.errors;
        outResult->durationSec    = totalElapsed;
    }

    CloseHandle(hVolume);
    DirMap_Destroy(&dirMap);
    DataRunList_Destroy(&mftRuns);
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

        // Check filesystem type — requires trailing backslash (volumeGuid has it)
        WCHAR fsName[64];
        DWORD driveType = GetDriveTypeW(volumeGuid);
        if (driveType != DRIVE_FIXED) continue;

        if (!GetVolumeInformationW(volumeGuid, NULL, 0, NULL, NULL, NULL, fsName, 64))
            continue;
        if (_wcsicmp(fsName, L"NTFS") != 0) continue;

        // Get mount path(s) for this volume
        WCHAR pathNames[4096];
        DWORD returnLen = 0;
        if (!GetVolumePathNamesForVolumeNameW(volumeGuid, pathNames, 4096, &returnLen))
            continue;

        // pathNames is a double-null-terminated list of null-separated mount paths.
        // Pick primary: prefer drive letter (len<=3) over longer mount paths.
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

        if (!bestPath || bestPath[0] == L'\0') continue;  // No mount path — skip

        // Device path: volume GUID without trailing backslash
        wcscpy(volumes[count].devicePath, volumeGuid);
        size_t guidLen = wcslen(volumes[count].devicePath);
        if (guidLen > 0 && volumes[count].devicePath[guidLen - 1] == L'\\') {
            volumes[count].devicePath[guidLen - 1] = L'\0';
        }

        // Mount path: with trailing backslash
        wcscpy(volumes[count].mountPath, bestPath);
        size_t mountLen = wcslen(volumes[count].mountPath);
        if (mountLen > 0 && volumes[count].mountPath[mountLen - 1] != L'\\') {
            wcscat(volumes[count].mountPath, L"\\");
        }

        // Display name: mount path without trailing backslash
        wcscpy(volumes[count].displayName, bestPath);
        size_t dispLen = wcslen(volumes[count].displayName);
        if (dispLen > 1 && volumes[count].displayName[dispLen - 1] == L'\\') {
            volumes[count].displayName[dispLen - 1] = L'\0';
        }

        count++;
    } while (FindNextVolumeW(hFind, volumeGuid, 128));

    FindVolumeClose(hFind);
    return count;
}

// ============================================================================
// Scan Configuration & CLI
// ============================================================================

struct ScanConfig {
    VolumeInfo volumes[MAX_VOLUMES];
    int volumeCount;
    WCHAR outputPath[MAX_PATH_LEN];
    DWORD numThreads;       // Accepted for CLI compat, ignored
    ULONGLONG minSizeBytes;
    BOOL allVolumes;
    BOOL showHelp;
};

static void PrintUsage(void) {
    wprintf(L"mftdirect - Direct MFT Parser for Space Utilization Reporting\n\n");
    wprintf(L"Usage:\n");
    wprintf(L"  mftdirect.exe [options] [volume...]\n\n");
    wprintf(L"  ** Requires Administrator privileges **\n\n");
    wprintf(L"Volumes:\n");
    wprintf(L"  C: D: E:              Scan specific drive-letter volumes\n");
    wprintf(L"  --allVolumes          Scan all local NTFS volumes (incl. mount points)\n\n");
    wprintf(L"Options:\n");
    wprintf(L"  --output <path>       Output CSV file path\n");
    wprintf(L"                        (default: mftdirect_YYYYMMDD_HHMMSS.csv)\n");
    wprintf(L"  --threads <n>         Accepted for compatibility (ignored)\n");
    wprintf(L"  --minSize <bytes>     Minimum file size filter (default: 0, no filter)\n");
    wprintf(L"  --help                Show this help message\n\n");
    wprintf(L"Output:\n");
    wprintf(L"  <output>.csv          Combined CSV with Volume column\n");
    wprintf(L"  <output>_errors.log   Separate error log\n\n");
    wprintf(L"Examples:\n");
    wprintf(L"  mftdirect.exe C:\n");
    wprintf(L"  mftdirect.exe C: D: --output results.csv\n");
    wprintf(L"  mftdirect.exe --allVolumes\n");
    wprintf(L"  mftdirect.exe D: --minSize 1048576\n");
}

static BOOL ParseArguments(int argc, wchar_t* argv[], ScanConfig* config) {
    memset(config, 0, sizeof(ScanConfig));
    config->numThreads = 1;
    config->minSizeBytes = 0;
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
                i++;  // Accept and ignore
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

    if (!config->showHelp && !config->allVolumes && config->volumeCount == 0) {
        wprintf(L"Error: Specify at least one volume (e.g., C:) or use --allVolumes\n\n");
        PrintUsage();
        return FALSE;
    }

    return TRUE;
}

static void BuildDefaultOutputPath(WCHAR* path, size_t pathSize) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    swprintf(path, pathSize, L"mftdirect_%04d%02d%02d_%02d%02d%02d.csv",
             st.wYear, st.wMonth, st.wDay,
             st.wHour, st.wMinute, st.wSecond);
}

static void BuildErrorLogPath(const WCHAR* csvPath, WCHAR* errPath, size_t errPathSize) {
    wcscpy_s(errPath, errPathSize, csvPath);
    size_t len = wcslen(errPath);

    if (len >= 4 && _wcsicmp(errPath + len - 4, L".csv") == 0) {
        wcscpy(errPath + len - 4, L"_errors.log");
    } else {
        wcscat_s(errPath, errPathSize, L"_errors.log");
    }
}

// ============================================================================
// JSON Manifest Writer
// ============================================================================

// Write a JSON-escaped version of a UTF-8 string to the file handle
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

    // Build JSON path: replace .csv with .json
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

    // Get server name
    WCHAR serverNameW[256];
    DWORD serverNameLen = 256;
    GetComputerNameW(serverNameW, &serverNameLen);
    char serverName[256];
    WideCharToMultiByte(CP_UTF8, 0, serverNameW, -1, serverName, sizeof(serverName), NULL, NULL);

    // Get username (DOMAIN\user)
    WCHAR domainW[256], userW[256];
    DWORD userLen = 256;
    GetEnvironmentVariableW(L"USERDOMAIN", domainW, 256);
    GetUserNameW(userW, &userLen);
    char collectedBy[512];
    char domainUtf8[256], userUtf8[256];
    WideCharToMultiByte(CP_UTF8, 0, domainW, -1, domainUtf8, sizeof(domainUtf8), NULL, NULL);
    WideCharToMultiByte(CP_UTF8, 0, userW, -1, userUtf8, sizeof(userUtf8), NULL, NULL);
    snprintf(collectedBy, sizeof(collectedBy), "%s\\%s", domainUtf8, userUtf8);

    // Get UTC timestamp
    SYSTEMTIME st;
    GetSystemTime(&st);
    char timestamp[32];
    snprintf(timestamp, sizeof(timestamp), "%04d-%02d-%02dT%02d:%02d:%02dZ",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

    // Extract filenames from paths (find last backslash)
    const WCHAR* csvFile = wcsrchr(csvPath, L'\\');
    csvFile = csvFile ? csvFile + 1 : csvPath;
    char csvFileUtf8[MAX_PATH];
    WideCharToMultiByte(CP_UTF8, 0, csvFile, -1, csvFileUtf8, sizeof(csvFileUtf8), NULL, NULL);

    const WCHAR* errFile = wcsrchr(errorLogPath, L'\\');
    errFile = errFile ? errFile + 1 : errorLogPath;
    char errFileUtf8[MAX_PATH];
    WideCharToMultiByte(CP_UTF8, 0, errFile, -1, errFileUtf8, sizeof(errFileUtf8), NULL, NULL);

    // Write JSON
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

        // Get volume label and filesystem type
        WCHAR volumeLabelW[256] = {0};
        WCHAR fsNameW[64] = {0};
        GetVolumeInformationW(vol->mountPath, volumeLabelW, 256,
                              NULL, NULL, NULL, fsNameW, 64);

        char volumeLabel[256], fsName[64];
        WideCharToMultiByte(CP_UTF8, 0, volumeLabelW, -1, volumeLabel, sizeof(volumeLabel), NULL, NULL);
        WideCharToMultiByte(CP_UTF8, 0, fsNameW, -1, fsName, sizeof(fsName), NULL, NULL);

        // Get volume capacity
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

    ScanConfig config;
    if (!ParseArguments(argc, argv, &config)) {
        return 1;
    }

    if (config.showHelp) {
        PrintUsage();
        return 0;
    }

    if (config.allVolumes) {
        int count = EnumerateAllNtfsVolumes(config.volumes, (int)MAX_VOLUMES);
        if (count == 0) {
            wprintf(L"Error: No NTFS volumes found\n");
            return 1;
        }
        config.volumeCount = count;
    }

    if (config.outputPath[0] == L'\0') {
        BuildDefaultOutputPath(config.outputPath, MAX_PATH_LEN);
    }

    WCHAR errorLogPath[MAX_PATH_LEN];
    BuildErrorLogPath(config.outputPath, errorLogPath, MAX_PATH_LEN);

    // Print banner
    wprintf(L"============================================================\n");
    wprintf(L"MFTDIRECT - Direct MFT Parser\n");
    wprintf(L"============================================================\n");
    wprintf(L"Volumes:    ");
    for (int i = 0; i < config.volumeCount; i++) {
        wprintf(L"%s%s", config.volumes[i].displayName, (i < config.volumeCount - 1) ? L", " : L"");
    }
    wprintf(L"\n");
    wprintf(L"Mode:       Direct MFT binary parsing (single-threaded)\n");

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
    EnterCriticalSection(&csv.lock);
    WriteFile(csv.hFile, header, (DWORD)strlen(header), &headerWritten, NULL);
    LeaveCriticalSection(&csv.lock);

    // Open error log writer
    BufferedWriter errLog;
    if (!BufferedWriter_Init(&errLog, errorLogPath, ERR_WRITE_BUF_SIZE, FALSE)) {
        wprintf(L"Warning: Cannot create error log file: %s\n", errorLogPath);
        wprintf(L"Errors will only appear in console output.\n");
    }

    LARGE_INTEGER overallStart, overallFreq;
    QueryPerformanceFrequency(&overallFreq);
    QueryPerformanceCounter(&overallStart);
    LONGLONG totalEntriesAllVolumes = 0;

    VolumeScanResult volumeResults[MAX_VOLUMES];
    memset(volumeResults, 0, sizeof(volumeResults));

    for (int v = 0; v < config.volumeCount; v++) {
        ScanVolumeDirect(&config.volumes[v], &csv, &errLog,
                         config.minSizeBytes, &volumeResults[v]);

        totalEntriesAllVolumes += volumeResults[v].entryCount;
    }

    BufferedWriter_Destroy(&csv);
    BufferedWriter_Destroy(&errLog);

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
