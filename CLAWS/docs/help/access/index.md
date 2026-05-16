# Access & Permissions

CLAWS uses role-based access control (RBAC) to manage who can perform different actions in the application. Access is controlled through Active Directory security groups.

## Authentication Methods

The application supports two authentication methods:

| Method | Description |
|--------|-------------|
| **Windows Authentication** | Automatic sign-in using your Windows credentials (Kerberos/NTLM) |
| **LDAP Authentication** | Manual sign-in with username and password against Active Directory |

Your administrator determines which method is enabled for your environment.

## Permission Model

CLAWS uses a simplified permission model where **all authenticated users** have broad read and upload access:

```
All Authenticated Users
    ├── View all pages (except Admin)
    ├── Upload files (NTFS and AD)
    ├── Manage own uploads
    └── View all data (read-only)

NTFS Perms Admin (additional)
    └── Manage any NTFS upload/production data

AD Admin (additional)
    ├── Manage any AD upload/production data
    └── Edit Domain Master List

Site Admin (full access)
    └── Everything including Admin menu
```

## Available Roles

| Role | Purpose | Key Permissions |
|------|---------|-----------------|
| [Site Admin](roles.md#site-admin) | Full system access | All features including configuration |
| [NTFS Perms Admin](roles.md#ntfs-perms-admin) | NTFS data management | Manage any NTFS upload, delete NTFS production data |
| [AD Admin](roles.md#ad-admin) | AD data management | Manage any AD upload, delete AD production data, edit DML |
| [Authenticated User](roles.md#authenticated-users-no-special-role) | Basic access | Upload, view all data, manage own uploads |

## Quick Reference

### What role do I need?

| I want to... | Required Role |
|--------------|---------------|
| Upload NTFS permission collections | Any authenticated user |
| Upload AD Inventory collections | Any authenticated user |
| View any upload status or logs | Any authenticated user |
| View production NTFS or AD data | Any authenticated user |
| View the Domain Master List | Any authenticated user |
| Manage my own uploads | Any authenticated user |
| Manage ANY NTFS upload | **NTFS Perms Admin** or Site Admin |
| Delete NTFS production data | **NTFS Perms Admin** or Site Admin |
| Manage ANY AD upload | **AD Admin** or Site Admin |
| Delete AD production data | **AD Admin** or Site Admin |
| Edit the Domain Master List | **AD Admin** or Site Admin |
| Access Admin menu | **Site Admin** only |
| Configure application settings | **Site Admin** only |
| Manage all API keys | **Site Admin** only |

## Getting Access

See [Requesting Access](requesting-access.md) for information on how to request the appropriate role for your needs.

## In This Section

| Article | Description |
|---------|-------------|
| [Roles Reference](roles.md) | Detailed description of each role |
| [Requesting Access](requesting-access.md) | How to request access |
| [API Keys](api-keys.md) | Managing API keys for automation |
| [Service Accounts](service-accounts.md) | Configuring service accounts for IIS, SQL Server, and LDAP |
