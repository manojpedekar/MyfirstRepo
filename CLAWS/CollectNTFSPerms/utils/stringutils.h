#pragma once
#include <string>

// Helper function to safely convert wstring to string
inline std::string WideToNarrow(const std::wstring& wide) {
    if (wide.empty()) return "";
    
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) return "";
    
    std::string narrow(size - 1, 0);
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, &narrow[0], size, nullptr, nullptr);
    return narrow;
} 