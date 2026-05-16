#pragma once

#include <string>
#include "../../sqlite/sqlite3.h"
#include <stdexcept>

class Statement {
public:
    Statement(sqlite3* db, const char* sql) : m_stmt(nullptr), m_db(db) {
        int result = sqlite3_prepare_v2(db, sql, -1, &m_stmt, nullptr);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to prepare statement: " + 
                std::string(sqlite3_errmsg(db)));
        }
    }

    ~Statement() {
        if (m_stmt) {
            sqlite3_finalize(m_stmt);
        }
    }

    // Prevent copying
    Statement(const Statement&) = delete;
    Statement& operator=(const Statement&) = delete;

    void Reset() {
        sqlite3_reset(m_stmt);
        sqlite3_clear_bindings(m_stmt);
    }

    int Step() {
        return sqlite3_step(m_stmt);
    }

    // Add column access methods
    int GetColumnInt(int column) {
        return sqlite3_column_int(m_stmt, column);
    }

    int64_t GetColumnInt64(int column) {
        return sqlite3_column_int64(m_stmt, column);
    }

    double GetColumnDouble(int column) {
        return sqlite3_column_double(m_stmt, column);
    }

    const char* GetColumnText(int column) {
        // FIX FC-020: Check for nullptr from sqlite3_column_text() to prevent crashes
        const unsigned char* result = sqlite3_column_text(m_stmt, column);
        return result ? reinterpret_cast<const char*>(result) : "";
    }

    const void* GetColumnBlob(int column) {
        return sqlite3_column_blob(m_stmt, column);
    }

    int GetColumnBytes(int column) {
        return sqlite3_column_bytes(m_stmt, column);
    }

    int GetColumnType(int column) {
        return sqlite3_column_type(m_stmt, column);
    }

    // Binding methods
    void Bind(int position, int value) {
        int result = sqlite3_bind_int(m_stmt, position, value);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to bind int: " + 
                std::string(sqlite3_errmsg(m_db)));
        }
    }

    void Bind(int position, int64_t value) {
        int result = sqlite3_bind_int64(m_stmt, position, value);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to bind int64: " + 
                std::string(sqlite3_errmsg(m_db)));
        }
    }

    void Bind(int position, double value) {
        int result = sqlite3_bind_double(m_stmt, position, value);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to bind double: " + 
                std::string(sqlite3_errmsg(m_db)));
        }
    }

    void Bind(int position, const std::string& value) {
        int result = sqlite3_bind_text(m_stmt, position, value.c_str(), -1, SQLITE_TRANSIENT);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to bind text: " + 
                std::string(sqlite3_errmsg(m_db)));
        }
    }

    void Bind(int position, const char* value) {
        int result = sqlite3_bind_text(m_stmt, position, value, -1, SQLITE_TRANSIENT);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to bind text: " + 
                std::string(sqlite3_errmsg(m_db)));
        }
    }

    void BindNull(int position) {
        int result = sqlite3_bind_null(m_stmt, position);
        if (result != SQLITE_OK) {
            throw std::runtime_error("Failed to bind null: " + 
                std::string(sqlite3_errmsg(m_db)));
        }
    }

    // Add a method to get the internal statement pointer
    sqlite3_stmt* GetStmtPtr() const {
        return m_stmt;
    }

    // Add a get() method to return the internal sqlite3_stmt* pointer
    sqlite3_stmt* get() const {
        return m_stmt;
    }

    int ColumnInt(int column) {
        return sqlite3_column_int(m_stmt, column);
    }

private:
    sqlite3_stmt* m_stmt;
    sqlite3* m_db;
};
