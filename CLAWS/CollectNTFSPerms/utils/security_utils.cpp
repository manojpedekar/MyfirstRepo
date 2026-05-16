#include "../utils/security_utils.h"
#include <algorithm>
#include <regex>     // ← for std::wregex / std::regex_search
#include <cwctype>   // ← for ::towlower

namespace SecurityUtils {
    bool isValidPath(const std::wstring& path) {
        if (path.empty()) return false;

        // Check for invalid characters, but allow drive letter colon
        const std::wregex invalidChars(L"[<>\"|?*]");
        if (std::regex_search(path, invalidChars)) return false;

        // Check for path traversal
        if (isPathTraversal(path)) return false;

        // Try to get file attributes
        DWORD attrs = GetFileAttributesW(path.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES) {
            DWORD error = GetLastError();
            // Allow access denied errors - we'll handle them during scanning
            if (error == ERROR_ACCESS_DENIED) {
                return true;
            }
            return false;
        }

        // Check if it's a directory
        return (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
    }
    bool isPathTraversal(const std::wstring& path) {
        static const std::wregex traversalPattern(
            LR"((\.\.[\\/])|([\\/]\.\.))",
            std::regex_constants::icase
        );
        return std::regex_search(path, traversalPattern);
    }
    /**
     * FC-028 FIX: Smart path sanitization with drive letter preservation
     *
     * Properly sanitizes Windows paths by:
     * 1. Removing path traversal sequences (..\ and /..)
     * 2. Preserving valid drive letter colons (C:, D:, etc.)
     * 3. Removing invalid filename characters
     *
     * @param path The path to sanitize
     * @return Sanitized path with drive letter colon preserved
     */
    std::wstring sanitizePath(const std::wstring& path) {
        if (path.empty()) return L"";

        std::wstring sanitized = path;

        // Step 1: Remove path traversal sequences (..\\ and /../)
        // This regex matches .. followed by \ or /, or \ or / followed by ..
        static const std::wregex traversalPattern(
            LR"(\.\.[\\/]|[\\/]\.\.)",
            std::regex_constants::icase
        );
        sanitized = std::regex_replace(sanitized, traversalPattern, L"");

        // Step 2: Preserve drive letter colon (if present)
        bool hasDriveLetter = false;
        if (sanitized.length() >= 2 &&
            std::iswalpha(sanitized[0]) &&
            sanitized[1] == L':') {
            hasDriveLetter = true;
            // Temporarily replace drive letter colon with placeholder
            // Using non-printable character \x01 (SOH - Start of Heading)
            sanitized[1] = L'\x01';
        }

        // Step 3: Remove invalid Windows filename characters
        // Invalid chars: < > : " | ? *
        // Note: Colon was already preserved above if it was a drive letter
        sanitized = std::regex_replace(sanitized, std::wregex(L"[<>:\"|?*]"), L"");

        // Step 4: Restore drive letter colon
        if (hasDriveLetter && sanitized.length() >= 2 && sanitized[1] == L'\x01') {
            sanitized[1] = L':';
        }

        return sanitized;
    }
    bool isValidComputerName(const std::string& name) {
        if (name.empty() || name.length() > 15) return false;
        const std::regex invalidChars("[^a-zA-Z0-9-]");
        return !std::regex_search(name, invalidChars);
    }
    std::string sanitizeComputerName(const std::string& name) {
        std::string sanitized = name;
        sanitized = std::regex_replace(sanitized, std::regex("[^a-zA-Z0-9-]"), "");
        if (sanitized.length() > 15) {
            sanitized = sanitized.substr(0, 15);
        }
        return sanitized;
    }
    bool isValidDomainName(const std::string& domain) {
        if (domain.empty() || domain.length() > 255) return false;
        const std::regex invalidChars("[^a-zA-Z0-9.-]");
        return !std::regex_search(domain, invalidChars);
    }
    std::string sanitizeDomainName(const std::string& domain) {
        std::string sanitized = domain;
        sanitized = std::regex_replace(sanitized, std::regex("[^a-zA-Z0-9.-]"), "");
        if (sanitized.length() > 255) {
            sanitized = sanitized.substr(0, 255);
        }
        return sanitized;
    }
    bool isValidPermission(const std::wstring& permission) {
        if (permission.empty()) return false;
        const std::wregex validPattern(L"^[A-Za-z0-9\\s,()-]+$");
        return std::regex_match(permission, validPattern);
    }
    bool isSafePermission(const std::wstring& permission) {
        if (!isValidPermission(permission)) return false;
        std::wstring lowerPermission = permission;
        std::transform(lowerPermission.begin(), lowerPermission.end(), lowerPermission.begin(), ::towlower);
        return lowerPermission.find(L"full control") == std::wstring::npos &&
               lowerPermission.find(L"take ownership") == std::wstring::npos;
    }
} 