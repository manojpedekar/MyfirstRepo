/**
 * @file PathUtils.cpp
 * @brief Implementation of shared path utility functions.
 */

#include "PathUtils.h"
#include <algorithm>
#include <cwctype>

namespace PathUtils {

// ============================================================================
// Internal Helpers
// ============================================================================

namespace detail {

bool startsWith(std::wstring_view str, std::wstring_view prefix) {
    return str.size() >= prefix.size() &&
           std::equal(prefix.begin(), prefix.end(), str.begin());
}

bool startsWithIgnoreCase(std::wstring_view str, std::wstring_view prefix) {
    if (str.size() < prefix.size()) return false;

    for (size_t i = 0; i < prefix.size(); ++i) {
        if (std::towlower(str[i]) != std::towlower(prefix[i])) {
            return false;
        }
    }
    return true;
}

} // namespace detail

// ============================================================================
// Path Conversion Functions
// ============================================================================

std::wstring toLongPath(std::wstring_view path) {
    if (path.empty()) return std::wstring(path);

    // Check if path already has the long path prefix
    if (detail::startsWith(path, LONG_PATH_PREFIX)) {
        return std::wstring(path);
    }

    // Check if it's a UNC path
    if (isUncPath(path)) {
        return toLongUncPath(path);
    }

    // Convert to absolute path using GetFullPathNameW
    // Note: string_view is not null-terminated, so we need a temp string
    std::wstring pathStr(path);
    DWORD required = GetFullPathNameW(pathStr.c_str(), 0, nullptr, nullptr);
    if (required == 0) {
        return pathStr;
    }

    std::wstring fullPath(required, L'\0');
    DWORD copied = GetFullPathNameW(pathStr.c_str(), required, &fullPath[0], nullptr);
    if (copied == 0 || copied >= required) {
        return pathStr;
    }

    // Remove trailing nulls and add prefix
    fullPath.resize(wcslen(fullPath.c_str()));
    return LONG_PATH_PREFIX + fullPath;
}

std::wstring toLongUncPath(std::wstring_view path) {
    if (path.empty()) return std::wstring(path);

    // Already has long UNC prefix
    if (detail::startsWith(path, LONG_UNC_PREFIX)) {
        return std::wstring(path);
    }

    std::wstring cleanPath(path);

    // Remove leading backslashes and add UNC prefix
    while (detail::startsWith(cleanPath, UNC_PREFIX)) {
        cleanPath = cleanPath.substr(2);
    }

    return std::wstring(LONG_UNC_PREFIX) + cleanPath;
}

std::wstring removeLongPathPrefix(std::wstring_view path) {
    if (path.empty()) return std::wstring(path);

    // Check for \\?\UNC\ prefix (8 characters)
    if (detail::startsWith(path, LONG_UNC_PREFIX)) {
        // Convert \\?\UNC\server\share -> \\server\share
        return std::wstring(UNC_PREFIX) + std::wstring(path.substr(8));
    }

    // Check for \\?\ prefix (4 characters)
    if (detail::startsWith(path, LONG_PATH_PREFIX)) {
        // Convert \\?\C:\Windows -> C:\Windows
        return std::wstring(path.substr(4));
    }

    // No prefix, return as-is
    return std::wstring(path);
}

std::string normalizePath(std::wstring_view path) {
    std::wstring longPath = toLongPath(path);
    std::string utf8Path = toUtf8(longPath);
    std::replace(utf8Path.begin(), utf8Path.end(), '\\', '/');
    return utf8Path;
}

std::wstring trimPathEnd(std::wstring_view path) {
    if (path.empty()) return std::wstring(path);

    // Find the last character that is not a space or dot
    size_t endPos = path.find_last_not_of(L" .");

    // If the entire string is spaces/dots, return empty
    if (endPos == std::wstring_view::npos) {
        return L"";
    }

    // Return substring up to and including the last non-space/dot character
    return std::wstring(path.substr(0, endPos + 1));
}

// ============================================================================
// Path Detection Functions
// ============================================================================

bool isUncPath(std::wstring_view path) {
    return detail::startsWith(path, UNC_PREFIX) &&
           !detail::startsWith(path, LONG_PATH_PREFIX);
}

bool isLongPath(std::wstring_view path) {
    return detail::startsWith(path, LONG_PATH_PREFIX);
}

bool exceedsMaxPath(std::wstring_view path) {
    return path.size() > MAX_PATH_LIMIT;
}

// ============================================================================
// String Encoding Functions
// ============================================================================

std::string toUtf8(std::wstring_view path) {
    if (path.empty()) return {};

    // string_view is not null-terminated, so create a temp string
    std::wstring pathStr(path);
    int size = WideCharToMultiByte(CP_UTF8, 0, pathStr.c_str(), -1,
                                   nullptr, 0, nullptr, nullptr);
    if (size <= 0) return {};

    std::string result(size - 1, 0); // exclude null terminator
    WideCharToMultiByte(CP_UTF8, 0, pathStr.c_str(), -1,
                        &result[0], size, nullptr, nullptr);
    return result;
}

std::wstring toWide(std::string_view path) {
    if (path.empty()) return {};

    // string_view is not null-terminated, so create a temp string
    std::string pathStr(path);
    int size = MultiByteToWideChar(CP_UTF8, 0, pathStr.c_str(), -1, nullptr, 0);
    if (size <= 0) return {};

    std::wstring result(size - 1, 0);
    MultiByteToWideChar(CP_UTF8, 0, pathStr.c_str(), -1, &result[0], size);
    return result;
}

std::wstring toWideFromAcp(std::string_view ansi) {
    if (ansi.empty()) return {};

    // string_view is not null-terminated, so create a temp string
    std::string ansiStr(ansi);
    int size = MultiByteToWideChar(CP_ACP, 0, ansiStr.c_str(), -1, nullptr, 0);
    if (size <= 0) return {};

    std::wstring result(size - 1, 0);
    MultiByteToWideChar(CP_ACP, 0, ansiStr.c_str(), -1, &result[0], size);
    return result;
}

// ============================================================================
// Error Handling Functions
// ============================================================================

std::string getLastErrorString() {
    DWORD error = GetLastError();
    if (error == 0) return "No error";

    LPSTR messageBuffer = nullptr;
    size_t size = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        error,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPSTR>(&messageBuffer),
        0,
        nullptr
    );

    // Check if FormatMessageA failed
    if (size == 0 || messageBuffer == nullptr) {
        return "Error code: " + std::to_string(error);
    }

    std::string message(messageBuffer, size);
    LocalFree(messageBuffer);

    // Remove trailing newlines
    while (!message.empty() && (message.back() == '\n' || message.back() == '\r')) {
        message.pop_back();
    }

    return message;
}

std::wstring getLastErrorStringW() {
    return formatErrorCode(GetLastError());
}

std::wstring formatErrorCode(DWORD errorCode) {
    if (errorCode == 0) return L"No error";

    LPWSTR messageBuffer = nullptr;
    size_t size = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        errorCode,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPWSTR>(&messageBuffer),
        0,
        nullptr
    );

    // Check if FormatMessageW failed
    if (size == 0 || messageBuffer == nullptr) {
        return L"Error code: " + std::to_wstring(errorCode);
    }

    std::wstring message(messageBuffer, size);
    LocalFree(messageBuffer);

    // Remove trailing newlines
    while (!message.empty() && (message.back() == L'\n' || message.back() == L'\r')) {
        message.pop_back();
    }

    return message;
}

} // namespace PathUtils
