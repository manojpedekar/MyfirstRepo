#pragma once

/**
 * @file folderutils.h
 * @brief Backward-compatible wrapper for PathUtils library.
 *
 * This header provides the FolderUtils namespace that delegates to the
 * shared PathUtils library. Existing code can continue using FolderUtils::
 * without modification.
 *
 * For new code, consider using PathUtils directly:
 *   #include <PathUtils.h>
 *   #include <PathValidator.h>
 */

#include <string>
#include <string_view>
#include <windows.h>

// Include the shared PathUtils library
#include <PathUtils.h>

namespace FolderUtils {

/**
 * @brief Converts a regular path to a long path format.
 *
 * Delegates to PathUtils::toLongPath().
 *
 * @param path The input path to convert.
 * @return std::wstring The path in long path format (\\?\ prefix).
 */
inline std::wstring toLongPath(std::wstring_view path) {
    return PathUtils::toLongPath(path);
}

/**
 * @brief Converts a regular path to a long UNC path format.
 *
 * Delegates to PathUtils::toLongUncPath().
 *
 * @param path The input UNC path to convert.
 * @return std::wstring The path in long UNC path format (\\?\UNC\ prefix).
 */
inline std::wstring toLongUncPath(std::wstring_view path) {
    return PathUtils::toLongUncPath(path);
}

/**
 * @brief Removes the long path prefix from a path if present.
 *
 * Delegates to PathUtils::removeLongPathPrefix().
 *
 * @param path The path that may have a long path prefix.
 * @return std::wstring The path with long path prefix removed.
 */
inline std::wstring removeLongPathPrefix(std::wstring_view path) {
    return PathUtils::removeLongPathPrefix(path);
}

/**
 * @brief Converts a wide string path to UTF-8.
 *
 * Delegates to PathUtils::toUtf8().
 *
 * @param path The wide string path to convert.
 * @return std::string The UTF-8 encoded path.
 */
inline std::string toUtf8(std::wstring_view path) {
    return PathUtils::toUtf8(path);
}

/**
 * @brief Converts a UTF-8 string path to wide string.
 *
 * Delegates to PathUtils::toWide().
 *
 * @param path The UTF-8 encoded path to convert.
 * @return std::wstring The wide string path.
 */
inline std::wstring toWide(std::string_view path) {
    return PathUtils::toWide(path);
}

/**
 * @brief Converts a ANSI (CP_ACP) string to wide string.
 *
 * Delegates to PathUtils::toWideFromAcp().
 *
 * @param ansi The ANSI string to convert.
 * @return std::wstring The wide string.
 */
inline std::wstring toWideFromAcp(std::string_view ansi) {
    return PathUtils::toWideFromAcp(ansi);
}

/**
 * @brief Gets the last Windows error message as a string.
 *
 * Delegates to PathUtils::getLastErrorString().
 *
 * @return std::string The formatted error message.
 */
inline std::string getLastErrorString() {
    return PathUtils::getLastErrorString();
}

/**
 * @brief Checks if a path is a UNC path.
 *
 * Delegates to PathUtils::isUncPath().
 *
 * @param path The path to check.
 * @return true if the path is a UNC path, false otherwise.
 */
inline bool isUncPath(std::wstring_view path) {
    return PathUtils::isUncPath(path);
}

/**
 * @brief Normalizes a path for database storage.
 *
 * Delegates to PathUtils::normalizePath().
 *
 * @param path The path to normalize.
 * @return std::string The normalized path in UTF-8.
 */
inline std::string normalizePath(std::wstring_view path) {
    return PathUtils::normalizePath(path);
}

/**
 * @brief Trims trailing spaces and dots from a path component.
 *
 * Delegates to PathUtils::trimPathEnd().
 *
 * @param path The path to trim.
 * @return std::wstring The path with trailing spaces and dots removed.
 */
inline std::wstring TrimPathEnd(std::wstring_view path) {
    return PathUtils::trimPathEnd(path);
}

/**
 * @brief Checks if a path is a volume mount point (not a symlink).
 *
 * Mount points have FILE_ATTRIBUTE_REPARSE_POINT with IO_REPARSE_TAG_MOUNT_POINT.
 * This is used to detect volumes mounted as folders (e.g., C:\Mount\DataDrive\)
 * which should be skipped during --allfixeddisks scanning to avoid duplicates.
 *
 * @param path The path to check.
 * @return true if the path is a volume mount point, false otherwise.
 */
inline bool IsMountPoint(const std::wstring& path) {
    std::wstring longPath = toLongPath(path);

    // First check if it's a reparse point via attributes
    DWORD attrs = GetFileAttributesW(longPath.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        return false;
    }

    if (!(attrs & FILE_ATTRIBUTE_REPARSE_POINT)) {
        return false;
    }

    // Open the directory to get the reparse tag
    HANDLE hDir = CreateFileW(
        longPath.c_str(),
        FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
        nullptr
    );

    if (hDir == INVALID_HANDLE_VALUE) {
        return false;
    }

    // Get the reparse point data
    BYTE buffer[MAXIMUM_REPARSE_DATA_BUFFER_SIZE];
    DWORD bytesReturned;
    BOOL result = DeviceIoControl(
        hDir,
        FSCTL_GET_REPARSE_POINT,
        nullptr, 0,
        buffer, sizeof(buffer),
        &bytesReturned,
        nullptr
    );
    CloseHandle(hDir);

    if (!result) {
        return false;
    }

    // Check the reparse tag
    // Mount points use IO_REPARSE_TAG_MOUNT_POINT (0xA0000003)
    // Symlinks use IO_REPARSE_TAG_SYMLINK (0xA000000C)
    // The ReparseTag is the first DWORD in the reparse data buffer
    DWORD reparseTag = *reinterpret_cast<DWORD*>(buffer);
    return reparseTag == IO_REPARSE_TAG_MOUNT_POINT;
}

} // namespace FolderUtils
