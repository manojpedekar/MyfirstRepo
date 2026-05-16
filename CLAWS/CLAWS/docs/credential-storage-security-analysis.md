# Credential Storage Security Analysis

## Overview

This document analyzes how credentials are stored in the `appsettings.local.json` configuration file, comparing the security implementations for different credential types.

## Summary of Findings

| Credential Type | Storage Method | Encrypted | Security Level |
|-----------------|---------------|-----------|----------------|
| SQL Server Password | Windows DPAPI (LocalMachine) | Yes | **High** |
| Cloud Integration Password | ASP.NET Core Data Protection | Yes | **High** |
| LDAP Authentication | N/A (Windows Auth) | N/A | **High** |

## Implementation Details

### 1. SQL Server Credentials - DPAPI Encryption

**Location:** `ConfigurationFileService.cs`, `Program.cs`, `AppSettings.cs`

**Encryption Method:** Windows Data Protection API (DPAPI) with `LocalMachine` scope

**How it works:**

1. **Saving credentials** (`AdminController.SaveSqlServerConfig`):
   - Plain text password is extracted from the form
   - Password is encrypted using `ProtectedData.Protect()` with `LocalMachine` scope
   - Encrypted password (base64) is stored in `EncryptedPassword` field
   - Legacy `Password` field is cleared

2. **Loading credentials** (`Program.cs` at startup):
   - Configuration is bound from `appsettings.local.json`
   - If `EncryptedPassword` is present, it's decrypted using `ProtectedData.Unprotect()`
   - Decrypted password is stored in `SqlServerSettings.Password` (in memory only)
   - Application uses decrypted password for all database connections

**Config file structure:**
```json
{
  "AppSettings": {
    "SqlServer": {
      "Server": "sql-server.example.com",
      "Database": "NTFSPerms",
      "UseWindowsAuth": false,
      "Username": "app_user",
      "EncryptedPassword": "AQAAANCMnd8BFdERjHoAwE/Cl+sB..."
    }
  }
}
```

**Key characteristics:**
- Machine-specific encryption (cannot be decrypted on another machine)
- No external key storage required (keys are derived from machine identity)
- Survives application restarts
- Does NOT survive machine migration (password must be re-entered)

**Backward Compatibility:**
- Legacy plain text `Password` field is still supported for migration
- On save, if legacy password exists, it's automatically encrypted
- Warning is logged when using legacy plain text password

---

### 2. Cloud Integration Credentials - Data Protection API

**Location:** `ConfigurationFileService.cs`

**Encryption Method:** ASP.NET Core Data Protection API with database-backed keys

**How it works:**

1. **Saving credentials** (`SaveCloudIntegrationConfigAsync`):
   - Password is encrypted using `IDataProtector.Protect()`
   - Keys are stored in `[app].[DataProtectionKeys]` table
   - Encrypted password is stored in `EncryptedServiceAccountPassword` field

2. **Loading credentials** (`DecryptCloudIntegrationPassword`):
   - Encrypted password is decrypted using `IDataProtector.Unprotect()`
   - Requires database connection (keys stored in database)

**Config file structure:**
```json
{
  "AppSettings": {
    "CloudIntegration": {
      "ServiceAccountUsername": "svc_cloudintegration",
      "EncryptedServiceAccountPassword": "CfDJ8N...=="
    }
  }
}
```

**Key characteristics:**
- Keys stored in SQL Server database
- Supports key rotation
- Works across load-balanced servers (shared keys)
- Requires database connection for decryption

---

### 3. LDAP Authentication Credentials

**Implementation:** No credentials stored - uses Windows authentication pass-through

**How it works:**
- LDAP binds use the current user's Windows credentials
- No password storage required in configuration

---

## Why Different Approaches?

### SQL Server - DPAPI (Bootstrap Problem Solution)

The SQL Server password **cannot** use the same Data Protection approach as Cloud Integration because:

1. Data Protection keys are stored in the database
2. To decrypt the password, you need database access
3. To access the database, you need the decrypted password
4. **Circular dependency** - chicken and egg problem

**Solution:** Use Windows DPAPI which stores keys locally on the machine, requiring no database access.

### Cloud Integration - Data Protection API

Cloud Integration credentials **can** use Data Protection because:

1. Database connection is already established (using SQL Server credentials)
2. Data Protection keys can be retrieved from `[app].[DataProtectionKeys]`
3. No bootstrap problem

---

## Security Considerations

### DPAPI (SQL Server)

**Pros:**
- No external key management required
- Machine-specific (encrypted data is useless if stolen)
- Simple implementation

**Cons:**
- Machine-bound (cannot migrate encrypted config to another server)
- LocalMachine scope means any process on the machine can decrypt
- No key rotation mechanism

**Mitigation:**
- Use Windows Authentication when possible (no password to store)
- Restrict file system access to the config file
- Use service accounts with minimal privileges

### Data Protection API (Cloud Integration)

**Pros:**
- Supports key rotation
- Keys can be shared across servers
- Integration with Azure Key Vault possible

**Cons:**
- Requires database connection to decrypt
- Key loss means all encrypted data is unrecoverable
- More complex key management

**Mitigation:**
- Regular database backups including `[app].[DataProtectionKeys]`
- Consider Azure Key Vault for production environments

---

## Migration Notes

### Existing Plain Text SQL Passwords

If you have an existing `appsettings.local.json` with a plain text `Password` field:

1. The application will log a warning about using legacy plain text password
2. Simply re-save the SQL Server configuration through the Admin UI
3. The password will be automatically encrypted with DPAPI
4. The plain text `Password` field will be removed from the config file

### Server Migration

When migrating to a new server:

1. **SQL Server password** must be re-entered (DPAPI is machine-specific)
2. **Cloud Integration password** will work if database is accessible (keys in database)

---

## Code Locations

| Component | File | Method/Class |
|-----------|------|--------------|
| DPAPI Encrypt | `ConfigurationFileService.cs` | `EncryptWithDpapi()` |
| DPAPI Decrypt | `ConfigurationFileService.cs` | `DecryptWithDpapi()` |
| Startup Decrypt | `Program.cs` | Lines 32-49 |
| SQL Config Save | `AdminController.cs` | `SaveSqlServerConfig()` |
| Data Protection Encrypt | `ConfigurationFileService.cs` | `SaveCloudIntegrationConfigAsync()` |
| Data Protection Decrypt | `ConfigurationFileService.cs` | `DecryptCloudIntegrationPassword()` |
