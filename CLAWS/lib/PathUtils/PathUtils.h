#pragma once

/**
 * @file PathUtils.h
 * @brief Shared path utility functions for NTFS path handling.
 *
 * This module provides common path manipulation functions used by both
 * CollectNTFSPerms and TestNTFSPath projects. It consolidates path handling
 * logic to ensure consistent behavior across the solution.
 *
 * Features:
 * - Long path prefix handling (\\?\ and \\?\UNC\)
 * - UNC path detection and conversion
 * - UTF-8/Wide string conversion
 * - Path normalization for database storage
 * - Windows error message formatting
 *
 * @note All functions are C++17 compatible and use string_view where possible
 *       to minimize allocations.
 */

#include <string>
#include <string_view>
#include <windows.h>

namespace PathUtils {

// ============================================================================
// Path Prefix Constants
// ============================================================================

/// Long path prefix for local paths (e.g., \\?\C:\folder)
constexpr wchar_t LONG_PATH_PREFIX[] = L"\\\\?\\";

/// Long path prefix for UNC paths (e.g., \\?\UNC\server\share)
constexpr wchar_t LONG_UNC_PREFIX[] = L"\\\\?\\UNC\\";

/// Standard UNC prefix (e.g., \\server\share)
constexpr wchar_t UNC_PREFIX[] = L"\\\\";

/// Windows MAX_PATH limit
constexpr size_t MAX_PATH_LIMIT = 260;

// ============================================================================
// Path Conversion Functions
// ============================================================================

/**
 * @brief Converts a regular path to long path format (\\?\ prefix).
 *
 * Handles both local paths (C:\folder) and UNC paths (\\server\share).
 * If the path already has the long path prefix, returns it unchanged.
 *
 * @param path The input path to convert.
 * @return std::wstring The path with long path prefix.
 *
 * @example
 *   toLongPath(L"C:\\folder") -> L"\\\\?\\C:\\folder"
 *   toLongPath(L"\\\\server\\share") -> L"\\\\?\\UNC\\server\\share"
 *   toLongPath(L"\\\\?\\C:\\folder") -> L"\\\\?\\C:\\folder" (unchanged)
 */
std::wstring toLongPath(std::wstring_view path);

/**
 * @brief Converts a UNC path to long UNC path format (\\?\UNC\ prefix).
 *
 * Specifically handles UNC paths by replacing \\ with \\?\UNC\.
 * If the path already has the long UNC prefix, returns it unchanged.
 *
 * @param path The input UNC path to convert.
 * @return std::wstring The path with long UNC prefix.
 *
 * @example
 *   toLongUncPath(L"\\\\server\\share") -> L"\\\\?\\UNC\\server\\share"
 */
std::wstring toLongUncPath(std::wstring_view path);

/**
 * @brief Removes the long path prefix from a path if present.
 *
 * Normalizes paths for database storage by removing implementation-specific
 * prefixes. Handles both \\?\ and \\?\UNC\ prefixes.
 *
 * @param path The path that may have a long path prefix.
 * @return std::wstring The path with long path prefix removed.
 *
 * @example
 *   removeLongPathPrefix(L"\\\\?\\C:\\Windows") -> L"C:\\Windows"
 *   removeLongPathPrefix(L"\\\\?\\UNC\\server\\share") -> L"\\\\server\\share"
 *   removeLongPathPrefix(L"C:\\Windows") -> L"C:\\Windows" (unchanged)
 */
std::wstring removeLongPathPrefix(std::wstring_view path);

/**
 * @brief Normalizes a path for database storage.
 *
 * Applies long path prefix and converts to UTF-8 with forward slashes.
 *
 * @param path The path to normalize.
 * @return std::string The normalized path in UTF-8.
 */
std::string normalizePath(std::wstring_view path);

/**
 * @brief Trims trailing spaces and dots from a path.
 *
 * Windows APIs are inconsistent with trailing spaces/dots in paths.
 * This function removes them to ensure compatibility with security APIs.
 *
 * @param path The path to trim.
 * @return std::wstring The path with trailing spaces and dots removed.
 */
std::wstring trimPathEnd(std::wstring_view path);

// ============================================================================
// Path Detection Functions
// ============================================================================

/**
 * @brief Checks if a path is a UNC path (starts with \\).
 *
 * Returns false for paths that already have the long path prefix (\\?\).
 *
 * @param path The path to check.
 * @return true if the path is a UNC path (e.g., \\server\share).
 */
bool isUncPath(std::wstring_view path);

/**
 * @brief Checks if a path has the long path prefix (\\?\).
 *
 * @param path The path to check.
 * @return true if the path starts with \\?\.
 */
bool isLongPath(std::wstring_view path);

/**
 * @brief Checks if a path exceeds the Windows MAX_PATH limit.
 *
 * @param path The path to check.
 * @return true if path length > 260 characters.
 */
bool exceedsMaxPath(std::wstring_view path);

// ============================================================================
// String Encoding Functions
// ============================================================================

/**
 * @brief Converts a wide string path to UTF-8.
 *
 * @param path The wide string path to convert.
 * @return std::string The UTF-8 encoded path.
 */
std::string toUtf8(std::wstring_view path);

/**
 * @brief Converts a UTF-8 string path to wide string.
 *
 * @param path The UTF-8 encoded path to convert.
 * @return std::wstring The wide string path.
 */
std::wstring toWide(std::string_view path);

/**
 * @brief Converts an ANSI (CP_ACP) string to wide string.
 *
 * Used for legacy Windows API compatibility.
 *
 * @param ansi The ANSI string to convert.
 * @return std::wstring The wide string.
 */
std::wstring toWideFromAcp(std::string_view ansi);

// ============================================================================
// Error Handling Functions
// ============================================================================

/**
 * @brief Gets the last Windows error message as a narrow string.
 *
 * Calls GetLastError() and formats the result using FormatMessageA.
 *
 * @return std::string The formatted error message.
 */
std::string getLastErrorString();

/**
 * @brief Gets the last Windows error message as a wide string.
 *
 * Calls GetLastError() and formats the result using FormatMessageW.
 *
 * @return std::wstring The formatted error message.
 */
std::wstring getLastErrorStringW();

/**
 * @brief Formats a specific Windows error code as a string.
 *
 * @param errorCode The Windows error code to format.
 * @return std::wstring The formatted error message.
 */
std::wstring formatErrorCode(DWORD errorCode);

// ============================================================================
// Internal Helpers (exposed for testing)
// ============================================================================

namespace detail {

/**
 * @brief Checks if a wide string starts with a given prefix.
 *
 * Case-sensitive comparison.
 *
 * @param str The string to check.
 * @param prefix The prefix to look for.
 * @return true if str starts with prefix.
 */
bool startsWith(std::wstring_view str, std::wstring_view prefix);

/**
 * @brief Checks if a wide string starts with a given prefix (case-insensitive).
 *
 * @param str The string to check.
 * @param prefix The prefix to look for.
 * @return true if str starts with prefix (ignoring case).
 */
bool startsWithIgnoreCase(std::wstring_view str, std::wstring_view prefix);

} // namespace detail

} // namespace PathUtils
