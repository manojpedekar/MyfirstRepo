#pragma once

#include <windows.h>

/**
 * @file raii_wrappers.h
 * @brief Common RAII wrappers for Windows resources
 *
 * This file provides RAII (Resource Acquisition Is Initialization) wrappers
 * for common Windows resources to ensure proper cleanup and exception safety.
 */

namespace Common {

/**
 * @brief RAII wrapper for Windows HANDLE objects
 *
 * Automatically closes the handle when the object goes out of scope.
 * Supports move semantics but disallows copying.
 */
struct DeviceHandle {
    HANDLE h{ INVALID_HANDLE_VALUE };

    /**
     * @brief Constructs a DeviceHandle from a Windows HANDLE
     * @param handle The Windows HANDLE to wrap
     */
    explicit DeviceHandle(HANDLE handle) : h(handle) {}

    /**
     * @brief Destructor - automatically closes the handle if valid
     */
    ~DeviceHandle() noexcept {
        if (h != INVALID_HANDLE_VALUE) {
            CloseHandle(h);
        }
    }

    // Delete copy constructor and copy assignment
    DeviceHandle(const DeviceHandle&) = delete;
    DeviceHandle& operator=(const DeviceHandle&) = delete;

    /**
     * @brief Move constructor - transfers ownership of the handle
     * @param other The DeviceHandle to move from
     */
    DeviceHandle(DeviceHandle&& other) noexcept : h(other.h) {
        other.h = INVALID_HANDLE_VALUE;
    }

    /**
     * @brief Move assignment operator - transfers ownership of the handle
     * @param other The DeviceHandle to move from
     * @return Reference to this object
     */
    DeviceHandle& operator=(DeviceHandle&& other) noexcept {
        if (this != &other) {
            if (h != INVALID_HANDLE_VALUE) {
                CloseHandle(h);
            }
            h = other.h;
            other.h = INVALID_HANDLE_VALUE;
        }
        return *this;
    }

    /**
     * @brief Gets the raw HANDLE
     * @return The wrapped Windows HANDLE
     */
    HANDLE get() const { return h; }

    /**
     * @brief Checks if the handle is valid
     * @return true if handle is valid, false otherwise
     */
    bool is_valid() const { return h != INVALID_HANDLE_VALUE; }

    /**
     * @brief Conversion operator to HANDLE
     * @return The wrapped Windows HANDLE
     */
    operator HANDLE() const { return h; }
};

} // namespace Common
