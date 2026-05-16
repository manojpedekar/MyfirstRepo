# Service Account Configuration Guide

This guide explains the service accounts required for CLAWS and how to configure them for each function.

## Overview

CLAWS requires service accounts for three main purposes:

| Service Account | Purpose | Required? |
|-----------------|---------|-----------|
| IIS Application Pool | Runs the web application and background jobs | **Yes** |
| SQL Server Access | Database connectivity | **Yes** |
| Cloud Integration LDAP | Validates cloud integration URLs | Optional |

---

## IIS Application Pool Service Account

The IIS Application Pool identity runs the CLAWS web application and all background jobs (Hangfire). This is the most critical service account.

### Choosing an Identity

You have three options:

| Option | Identity | Recommendation |
|--------|----------|----------------|
| **ApplicationPoolIdentity** | `IIS AppPool\{SiteName}` | Good for simple deployments |
| **NetworkService** | `NT AUTHORITY\NETWORK SERVICE` | Use when SQL Server is on a different server |
| **Domain Service Account** | `DOMAIN\svc-claws` | Recommended for enterprise environments |

### Creating a Domain Service Account

For enterprise deployments, create a dedicated service account:

```powershell
# Create the service account in Active Directory
New-ADUser -Name "svc-claws" `
    -SamAccountName "svc-claws" `
    -UserPrincipalName "svc-claws@yourdomain.com" `
    -Description "CLAWS Application Service Account" `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled $true `
    -AccountPassword (Read-Host -AsSecureString "Enter Password")

# Add to IIS_IUSRS group on the web server (optional)
Add-ADGroupMember -Identity "IIS_IUSRS" -Members "svc-claws"
```

### Configuring During Installation

Specify the service account when running the installation script:

```powershell
.\Install-CLAWS.ps1 -SiteName "CLAWS" `
    -InstallPath "D:\Apps\CLAWS" `
    -AppPoolIdentity "DOMAIN\svc-claws" `
    -Credential (Get-Credential -UserName "DOMAIN\svc-claws" -Message "Enter service account password")
```

### File System Permissions Required

The service account needs the following permissions:

| Path | Permission | Purpose |
|------|------------|---------|
| `{InstallPath}` | Read & Execute | Application binaries |
| `{InstallPath}\ImportData` | Modify | Upload processing |
| `{InstallPath}\ImportData\Uploads` | Modify | Incoming uploaded files |
| `{InstallPath}\ImportData\Extraction` | Modify | ZIP extraction workspace |
| `{InstallPath}\ImportData\Completed` | Modify | Successful imports archive |
| `{InstallPath}\ImportData\Errors` | Modify | Failed imports archive |
| `{InstallPath}\Logs` | Modify | Application log files |

The installation script automatically configures these permissions. To manually configure:

```powershell
$servicAccount = "DOMAIN\svc-claws"
$paths = @(
    "D:\Apps\CLAWS\ImportData",
    "D:\Apps\CLAWS\Logs"
)

foreach ($path in $paths) {
    $acl = Get-Acl $path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $serviceAccount,
        "Modify",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}
```

---

## SQL Server Database Access

CLAWS supports two methods for database authentication.

### Option 1: Windows Authentication (Recommended)

The IIS Application Pool service account authenticates directly to SQL Server using Windows Authentication.

**Advantages:**
- No passwords stored in configuration files
- Centralized credential management through Active Directory
- Audit trail through Windows security logs

**Configuration in appsettings.json:**
```json
{
  "AppSettings": {
    "SqlServer": {
      "Server": "sqlserver.yourdomain.com",
      "Database": "CLAWS",
      "UseWindowsAuth": true
    }
  }
}
```

**SQL Server Permissions Required:**

```sql
-- Create login for the service account
CREATE LOGIN [DOMAIN\svc-claws] FROM WINDOWS;
GO

-- Create user in the database
USE [CLAWS];
GO
CREATE USER [svc-claws] FOR LOGIN [DOMAIN\svc-claws];
GO

-- Grant required permissions
-- Option A: db_owner (simplest, but more permissive)
ALTER ROLE [db_owner] ADD MEMBER [svc-claws];
GO

-- Option B: Specific permissions (more secure)
-- DDL permissions (required for Hangfire table creation on first run)
GRANT CREATE TABLE TO [svc-claws];
GRANT ALTER ON SCHEMA::HangFire TO [svc-claws];

-- Application schema
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::app TO [svc-claws];
GRANT EXECUTE ON SCHEMA::app TO [svc-claws];

-- Hangfire background jobs
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::HangFire TO [svc-claws];

-- NTFS Permissions data (production and staging)
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::fsapp TO [svc-claws];
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::fssimport TO [svc-claws];

-- AD Inventory data (production and staging)
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ADData TO [svc-claws];
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::ADImport TO [svc-claws];

-- Domain Master List
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::DML TO [svc-claws];
GO
```

### Option 2: SQL Server Authentication

Use a dedicated SQL Server login instead of Windows Authentication.

**When to use:**
- Service account cannot authenticate to SQL Server (network/domain trust issues)
- SQL Server is in a different domain or workgroup
- Cloud-hosted SQL Server without Windows Authentication support

**Configuration in appsettings.json:**
```json
{
  "AppSettings": {
    "SqlServer": {
      "Server": "sqlserver.yourdomain.com",
      "Database": "CLAWS",
      "UseWindowsAuth": false,
      "Username": "claws_app",
      "EncryptedPassword": "<base64-encoded-dpapi-encrypted-password>"
    }
  }
}
```

**Important:** The password is encrypted using DPAPI with LocalMachine scope. The application decrypts it at startup. If you move the application to a different server, you must re-encrypt the password on that server.

**Creating the SQL Login:**

```sql
-- Create SQL Server login
CREATE LOGIN [claws_app] WITH PASSWORD = 'YourSecurePassword123!';
GO

-- Create user in the database
USE [CLAWS];
GO
CREATE USER [claws_app] FOR LOGIN [claws_app];
GO

-- Grant permissions (same as Windows Auth)
ALTER ROLE [db_owner] ADD MEMBER [claws_app];
GO
```

**Setting the Encrypted Password:**

Use the Admin > Configuration page in the CLAWS web interface to set the password, which will automatically encrypt it. Alternatively, use PowerShell:

```powershell
# Encrypt password using DPAPI (run on the CLAWS server)
$password = "YourSecurePassword123!"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($password)
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $bytes,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
$base64 = [Convert]::ToBase64String($encrypted)
Write-Host "EncryptedPassword: $base64"
```

### Database Schemas Used

CLAWS uses the following database schemas:

| Schema | Purpose |
|--------|---------|
| `app` | Application tables (Uploads, ApiKeys, Configurations, Logs, DataProtectionKeys, ImportStatistics) |
| `HangFire` | Background job storage and scheduling (tables created automatically on first run) |
| `fsapp` | NTFS Permissions production data (merged/finalized collections) |
| `fssimport` | NTFS Permissions staging data (pending merge) |
| `ADData` | AD Inventory production data (merged/finalized collections) |
| `ADImport` | AD Inventory staging data (pending merge) |
| `DML` | Domain Master List (DomainMasterList, DomainNotes, lookup tables) |

**Note:** The `HangFire` schema and its tables are created automatically by the application on first startup if they don't exist. This requires the service account to have CREATE TABLE permissions.

---

## Cloud Integration LDAP Service Account

If you enable Cloud Integration validation, CLAWS queries Active Directory to validate cloud integration URLs for domains in the Domain Master List.

### Purpose

The Cloud Integration Validation job runs daily (default: 4 AM) and:
1. Connects to a specified LDAP server
2. Searches for organizational units with the `xldapURL` attribute
3. Updates domain records with their cloud integration status

### Service Account Requirements

Create a dedicated service account with minimal permissions:

```powershell
# Create service account for LDAP queries
New-ADUser -Name "svc-claws-ldap" `
    -SamAccountName "svc-claws-ldap" `
    -Description "CLAWS Cloud Integration LDAP Query Account" `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -Enabled $true `
    -AccountPassword (Read-Host -AsSecureString "Enter Password")
```

**Required Permissions:**
- Read access to the Cloud Integration OU (e.g., `OU=DirectoryList,OU=CloudUI,OU=Domain Delegation,DC=ssnc-corp,DC=global`)
- Read `organizationalUnit` objects
- Read `xldapURL` attribute

### Configuration in appsettings.json

```json
{
  "AppSettings": {
    "CloudIntegration": {
      "Enabled": true,
      "LdapServer": "dc01.yourdomain.com",
      "LdapPort": 636,
      "LdapUseSsl": true,
      "LdapSearchBase": "OU=DirectoryList,OU=CloudUI,OU=Domain Delegation,DC=yourdomain,DC=com",
      "ServiceAccountUsername": "svc-claws-ldap",
      "ServiceAccountDomain": "YOURDOMAIN",
      "EncryptedServiceAccountPassword": "<encrypted-password>",
      "ValidationSchedule": "0 4 * * *"
    }
  }
}
```

**Setting the Encrypted Password:**

Use the Admin > Configuration page in the CLAWS web interface, or configure via the API.

---

## Summary: Service Account Checklist

### For IIS Application Pool Service Account

- [ ] Create domain service account (or use ApplicationPoolIdentity)
- [ ] Grant Modify permission on `{InstallPath}\ImportData`
- [ ] Grant Modify permission on `{InstallPath}\Logs`
- [ ] Grant Read & Execute on `{InstallPath}` (application binaries)
- [ ] Create SQL Server login (if using Windows Auth)
- [ ] Grant database permissions (db_owner or specific permissions)
- [ ] Configure app pool to run as the service account

### For SQL Server (if using SQL Authentication)

- [ ] Create SQL Server login
- [ ] Create database user
- [ ] Grant database permissions
- [ ] Encrypt and store password in appsettings.json

### For Cloud Integration LDAP (if enabled)

- [ ] Create dedicated LDAP query account
- [ ] Grant read access to Cloud Integration OU
- [ ] Configure in appsettings.json
- [ ] Encrypt and store password

---

## Troubleshooting

### "Login failed for user" Errors

**Windows Authentication:**
1. Verify the service account has a SQL Server login
2. Check that the login is mapped to a user in the database
3. Verify the service account's domain membership

**SQL Authentication:**
1. Verify the SQL login exists and is enabled
2. Check the password is correct and not expired
3. Verify the encrypted password was created on the same server

### "Access Denied" to ImportData Folder

1. Verify the service account has Modify permission on the folder
2. Check that permissions are inherited by subfolders
3. Run the installation script with `-AppPoolIdentity` to reconfigure permissions

### Cloud Integration Validation Fails

1. Verify the LDAP service account credentials are correct
2. Test LDAP connectivity from the CLAWS server:
   ```powershell
   Test-NetConnection -ComputerName dc01.yourdomain.com -Port 636
   ```
3. Verify the service account has read access to the search base OU
4. Check the application logs for detailed error messages

### DPAPI Decryption Fails After Server Migration

DPAPI-encrypted passwords are tied to the machine. After migrating to a new server:
1. Re-enter the SQL Server password in Admin > Configuration
2. Re-enter the Cloud Integration service account password
3. The application will re-encrypt with the new machine's DPAPI keys

---

## Security Best Practices

1. **Use dedicated service accounts** - Don't use personal accounts or shared accounts
2. **Apply least privilege** - Grant only the permissions each account needs
3. **Use Windows Authentication when possible** - Avoids storing passwords in config files
4. **Rotate service account passwords regularly** - Follow your organization's password policy
5. **Monitor service account usage** - Enable auditing for service account logins
6. **Document service accounts** - Maintain documentation of all service accounts and their purposes
7. **Use managed service accounts (gMSA)** - Consider using Group Managed Service Accounts for automatic password management

---

*See [Roles Reference](roles.md) for information about user authorization roles.*
