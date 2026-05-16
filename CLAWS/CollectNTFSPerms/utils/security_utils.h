#pragma once
#include <string>
#include <filesystem>
#include <regex>
#include <windows.h>

namespace SecurityUtils {
    // Path validation
    bool isValidPath(const std::wstring& path);
    bool isPathTraversal(const std::wstring& path);
    std::wstring sanitizePath(const std::wstring& path);
    
    // Computer name validation
    bool isValidComputerName(const std::string& name);
    std::string sanitizeComputerName(const std::string& name);
    
    // Domain name validation
    bool isValidDomainName(const std::string& domain);
    std::string sanitizeDomainName(const std::string& domain);
    
    // NTFS permission validation
    bool isValidPermission(const std::wstring& permission);
    bool isSafePermission(const std::wstring& permission);
} 