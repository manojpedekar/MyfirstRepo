# Roles Reference

This page provides detailed information about each role in CLAWS, including their permissions and typical use cases.

## Permission Model Overview

CLAWS uses a simplified 3-role authorization model:

| Role | Primary Purpose |
|------|-----------------|
| **Site Admin** | Full administrative access to all features |
| **NTFS Perms Admin** | Manage NTFS uploads and production data |
| **AD Admin** | Manage AD uploads, production data, and Domain Master List |

**Important:** All authenticated users (regardless of role assignment) can:
- View all pages except the Admin menu
- Upload both NTFS and AD data files
- View all uploads, status, and logs
- Manage their own uploads (cancel, delete, re-queue)
- Generate and manage their own API keys

---

## Site Admin

**Purpose:** Full administrative access to all application features.

### Permissions

Site Admins can:
- Access all features available to other roles
- Access the Admin menu
- Configure application settings (database, LDAP, storage)
- Manage authorization group assignments
- Create and manage banner messages
- View and manage all API keys (not just their own)
- Access Hangfire dashboard for job management
- Delete any upload (NTFS or AD)
- Delete any production collection (NTFS or AD)
- Edit the Domain Master List
- View detailed system logs
- Manage orphaned data cleanup

### Typical Users

- IT Security team leads
- Application owners
- System administrators responsible for the platform

### AD Group Configuration

Configured via `Authorization:SiteAdminGroup` in appsettings.json:
```json
{
  "Authorization": {
    "SiteAdminGroup": "DOMAIN\\CLAWS-Admins"
  }
}
```

---

## NTFS Perms Admin

**Purpose:** Manage NTFS permission uploads and production data without full administrative access.

### Permissions

NTFS Perms Admins can (in addition to authenticated user access):
- Delete any NTFS permission upload (not just their own)
- Re-queue or validate any NTFS permission upload
- Delete NTFS production collections from the database

### Cannot

- Access the Admin menu
- Configure application settings
- Manage other users' API keys
- Delete AD uploads or production data
- Edit the Domain Master List (unless also in AD Admin group)

### Typical Users

- File server administrators
- Storage team leads
- Data stewards for NTFS permission data

### AD Group Configuration

Configured via `Authorization:NtfsPermsAdminGroup` in appsettings.json:
```json
{
  "Authorization": {
    "NtfsPermsAdminGroup": "DOMAIN\\CLAWS-NTFSAdmins"
  }
}
```

---

## AD Admin

**Purpose:** Manage AD Inventory uploads, production data, and the Domain Master List.

### Permissions

AD Admins can (in addition to authenticated user access):
- Delete any AD Inventory upload (not just their own)
- Re-queue or validate any AD Inventory upload
- Delete AD production collections from the database
- Create, edit, and delete Domain Master List entries
- Add notes to Domain Master List entries

### Cannot

- Access the Admin menu
- Configure application settings
- Manage other users' API keys
- Delete NTFS uploads or production data

### Typical Users

- Active Directory administrators
- Identity management team leads
- Domain architects

### AD Group Configuration

Configured via `Authorization:AdAdminGroup` in appsettings.json:
```json
{
  "Authorization": {
    "AdAdminGroup": "DOMAIN\\CLAWS-ADAdmins"
  }
}
```

---

## Authenticated Users (No Special Role)

**Purpose:** Basic access for anyone who can authenticate.

### Permissions

Any authenticated user can:
- Upload NTFS permission collection files
- Upload AD Inventory collection files
- View the status of all uploads (not just their own)
- View upload details and collection logs
- Cancel, delete, or re-queue their own uploads
- View production NTFS Permissions data (read-only)
- View production AD Inventory data (read-only)
- View the Domain Master List (read-only)
- View the Topology page
- Generate and manage their own API keys
- Access the Help section

### Cannot

- Access the Admin menu
- Delete other users' uploads
- Delete production data
- Edit the Domain Master List

### Typical Users

- File server administrators uploading collections
- AD administrators uploading collections
- Security analysts viewing data (read-only)
- Auditors reviewing collections

---

## Multiple Role Membership

Users can belong to multiple authorization groups. Permissions are **additive**:

| Membership | Effective Permissions |
|------------|----------------------|
| NTFS Perms Admin + AD Admin | Manage both NTFS and AD uploads/data, edit DML |
| NTFS Perms Admin only | Manage NTFS uploads/data only |
| AD Admin only | Manage AD uploads/data and DML |
| Site Admin | All permissions (membership in other groups not required) |

---

## Permission Matrix

| Action | Authenticated | NTFS Perms Admin | AD Admin | Site Admin |
|--------|---------------|------------------|----------|------------|
| View Home page | Yes | Yes | Yes | Yes |
| Upload files | Yes | Yes | Yes | Yes |
| View all uploads | Yes | Yes | Yes | Yes |
| Manage own uploads | Yes | Yes | Yes | Yes |
| Manage any NTFS upload | No | **Yes** | No | Yes |
| Manage any AD upload | No | No | **Yes** | Yes |
| View NTFS production data | Yes | Yes | Yes | Yes |
| View AD production data | Yes | Yes | Yes | Yes |
| Delete NTFS production | No | **Yes** | No | Yes |
| Delete AD production | No | No | **Yes** | Yes |
| View DML | Yes | Yes | Yes | Yes |
| Edit DML | No | No | **Yes** | Yes |
| View Topology | Yes | Yes | Yes | Yes |
| Access Admin menu | No | No | No | **Yes** |
| Manage all API keys | No | No | No | **Yes** |
| Configure settings | No | No | No | **Yes** |

---

## Unconfigured Groups

When authorization groups are not configured:

| Scenario | Behavior |
|----------|----------|
| No groups configured | All authenticated users have full access (warning displayed) |
| SiteAdminGroup not set | No users have admin access (except Keymaster in LDAP mode) |
| NtfsPermsAdminGroup not set | Only Site Admins can manage NTFS uploads/production data |
| AdAdminGroup not set | Only Site Admins can manage AD uploads/production data and edit DML |

**Security Recommendation:** Configure at least `SiteAdminGroup` to establish administrative access control.

---

## Verifying Your Access

To see what access you have:

1. Sign in to CLAWS
2. Look at the navigation menu - the Admin menu only appears for Site Admins
3. Try to perform an action - if denied, you'll see a "Forbidden" or "Access Denied" message

### Navigation Visibility

| Menu Item | Visible To |
|-----------|------------|
| Home | All authenticated users |
| Upload | All authenticated users |
| Status | All authenticated users |
| NTFS Permissions | All authenticated users |
| AD Inventory | All authenticated users |
| Topology | All authenticated users |
| DML | All authenticated users |
| Admin | **Site Admin only** |
| Help | All users (including unauthenticated) |

### Action Button Visibility

Some action buttons are hidden based on your permissions:

| Button | Visible To |
|--------|------------|
| Delete NTFS production collection | NTFS Perms Admin, Site Admin |
| Delete AD production collection | AD Admin, Site Admin |
| Add/Edit/Delete DML entry | AD Admin, Site Admin |
