#pragma once

#include "../../sqlite/sqlite3.h"
#include <stdexcept>
#include <string>

class Transaction {
public:
    Transaction(sqlite3* db) : m_db(db), m_committed(false) {
        char* errorMsg = nullptr;
        int result = sqlite3_exec(m_db, "BEGIN TRANSACTION", nullptr, nullptr, &errorMsg);
        if (result != SQLITE_OK) {
            std::string error = "Failed to begin transaction: ";
            if (errorMsg) {
                error += errorMsg;
                sqlite3_free(errorMsg);
            } else {
                error += "unknown error";
            }
            throw std::runtime_error(error);
        }
    }

    ~Transaction() {
        if (!m_committed) {
            try {
                Rollback();
            } catch (...) {
                // Ignore exceptions in destructor
            }
        }
    }

    // Prevent copying
    Transaction(const Transaction&) = delete;
    Transaction& operator=(const Transaction&) = delete;

    void Commit() {
        if (m_committed) {
            throw std::runtime_error("Transaction already committed");
        }

        char* errorMsg = nullptr;
        int result = sqlite3_exec(m_db, "COMMIT", nullptr, nullptr, &errorMsg);
        if (result != SQLITE_OK) {
            std::string error = "Failed to commit transaction: ";
            if (errorMsg) {
                error += errorMsg;
                sqlite3_free(errorMsg);
            } else {
                error += "unknown error";
            }
            throw std::runtime_error(error);
        }

        m_committed = true;
    }

    void Rollback() {
        if (m_committed) {
            throw std::runtime_error("Cannot rollback committed transaction");
        }

        char* errorMsg = nullptr;
        int result = sqlite3_exec(m_db, "ROLLBACK", nullptr, nullptr, &errorMsg);
        if (result != SQLITE_OK) {
            std::string error = "Failed to rollback transaction: ";
            if (errorMsg) {
                error += errorMsg;
                sqlite3_free(errorMsg);
            } else {
                error += "unknown error";
            }
            throw std::runtime_error(error);
        }

        m_committed = true;  // Mark as committed to prevent rollback in destructor
    }

private:
    sqlite3* m_db;
    bool m_committed;
};