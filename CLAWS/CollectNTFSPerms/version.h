#pragma once

// Version information
#define VERSION_MAJOR 1
#define VERSION_MINOR 8
#define VERSION_PATCH 0

// Helper macros for string conversion
#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)

// Version string macros
#define VERSION_STRING TOSTRING(VERSION_MAJOR) "." TOSTRING(VERSION_MINOR) "." TOSTRING(VERSION_PATCH)

// Build date time
// Note: Resource compiler (RC.exe) doesn't support __DATE__ and __TIME__
#ifdef RC_INVOKED
    // For resource file: use static placeholder (user can manually update if needed)
    #ifndef BUILD_DATE_TIME
    #define BUILD_DATE_TIME "See executable runtime for actual build date"
    #endif
#else
    // For C++ code: use automatic compiler macros
    #ifndef BUILD_DATE_TIME
    #define BUILD_DATE_TIME __DATE__ " " __TIME__
    #endif
#endif

// C++ only code (not for resource compiler)
#ifndef RC_INVOKED

// Numeric version for easy comparison (0x000101 = 0.1.1)
#define VERSION_NUMBER ((VERSION_MAJOR << 16) | (VERSION_MINOR << 8) | VERSION_PATCH)

// Optional structure to reference version constants programmatically
struct VersionInfo {
    static constexpr int major = VERSION_MAJOR;
    static constexpr int minor = VERSION_MINOR;
    static constexpr int patch = VERSION_PATCH;
    static constexpr const char* version = VERSION_STRING;
    static constexpr int versionNumber = VERSION_NUMBER;
    static constexpr const char* buildDateTime = BUILD_DATE_TIME;
};

#endif // RC_INVOKED

