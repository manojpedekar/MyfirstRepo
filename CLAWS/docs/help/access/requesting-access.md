# Requesting Access

This guide explains how to request access to CLAWS based on your needs.

## Before You Request

1. **Identify Your Need** - Determine what you need to do in the application
2. **Understand the Permission Model** - Most users only need basic authenticated access
3. **Request Only What You Need** - Follow the principle of least privilege

## Do You Need a Special Role?

**Most users don't need a special role!** All authenticated users can:
- Upload NTFS and AD collection files
- View all uploads and their status
- View all production data (read-only)
- View the Domain Master List (read-only)
- Manage their own uploads

You only need a special role if you need to:
- Manage (delete/re-queue) **other users'** uploads
- Delete production data from the database
- Edit the Domain Master List
- Access the Admin menu

## Access Request Process

### Step 1: Determine Required Role

| I need to... | Request this role |
|--------------|-------------------|
| Upload data and view results | No special role needed (just authenticate) |
| Manage any NTFS upload or delete NTFS production data | **NTFS Perms Admin** |
| Manage any AD upload or delete AD production data | **AD Admin** |
| Edit the Domain Master List | **AD Admin** |
| Administer the application | **Site Admin** |

### Step 2: Submit Access Request

Access is controlled through Active Directory security groups. To request access:

#### Option A: ServiceNow (Recommended)

1. Go to your organization's ServiceNow portal
2. Search for "CLAWS" or "NTFS Permissions"
3. Select the appropriate access request catalog item
4. Fill in the required information:
   - Justification for access
   - Role requested
   - Manager approval
5. Submit the request

#### Option B: Email Request

Send an email to your IT Security team or the application administrators with:

- **Subject:** CLAWS Access Request
- **Your Name and Employee ID**
- **Role Requested** (NTFS Perms Admin, AD Admin, or Site Admin)
- **Business Justification** - Why you need elevated permissions beyond basic access
- **Manager Approval** - CC your manager or attach approval email

### Step 3: Approval Process

1. Your request is reviewed by the application administrators
2. For elevated roles (Site Admin), additional approval may be required
3. Once approved, you'll be added to the appropriate AD group
4. Access is typically granted within 1-2 business days

## Role-Specific Requirements

### NTFS Perms Admin Access

**Who should request:**
- Storage team leads who need to manage collections from multiple file servers
- Data stewards responsible for NTFS permission data quality

**Requirements:**
- Valid business need to manage other users' NTFS uploads
- Need to delete NTFS production data
- Manager approval

**Group:** `CLAWS-NTFSAdmins` (or your organization's equivalent)

### AD Admin Access

**Who should request:**
- AD team leads who need to manage collections from multiple domains
- Identity management personnel responsible for the Domain Master List

**Requirements:**
- Valid business need to manage other users' AD uploads
- Need to edit the Domain Master List
- Manager approval

**Group:** `CLAWS-ADAdmins` (or your organization's equivalent)

### Site Admin Access

**Who should request:**
- Application owners
- IT Security leads
- Platform administrators

**Requirements:**
- Deep understanding of the application
- Responsibility for application configuration and security
- Multiple levels of approval (manager, security, IT leadership)

**Group:** `CLAWS-Admins` (or your organization's equivalent)

## Service Account Access

For automated processes (scheduled tasks, scripts), service accounts work with the same permission model:

### Service Account Setup

1. Create or identify an existing service account
2. Service accounts can upload data without any special role
3. If the automation needs to manage other uploads or delete production data, add the service account to the appropriate AD group

### Service Account Best Practices

- Use dedicated service accounts (not personal accounts)
- Service accounts typically only need basic authenticated access
- Document the automation purpose
- Review access periodically

## Access Review

Access to elevated roles is reviewed periodically:

- **NTFS Perms Admin:** Reviewed semi-annually
- **AD Admin:** Reviewed semi-annually
- **Site Admin:** Reviewed annually

If you no longer need elevated access, please request removal to maintain security.

## Troubleshooting Access Issues

### "Access Denied" or "Forbidden" Error

If you receive an error when trying to perform an action:

1. **Check if you need a special role:** Most view/upload operations work for all authenticated users
2. **Verify Group Membership:** For elevated actions, check if you're in the appropriate AD group:
   ```powershell
   # Check your group membership
   whoami /groups | findstr "CLAWS"
   ```
3. **Sign Out and Back In:** Group membership changes require a new login session
4. **Check with IT:** If you believe you should have access, contact your IT team

### Can't See Delete Buttons

Delete buttons for production data are only visible to users with the appropriate role:

| Missing Button | Required Role |
|----------------|---------------|
| Delete NTFS production collection | NTFS Perms Admin or Site Admin |
| Delete AD production collection | AD Admin or Site Admin |
| Edit/Delete DML entry | AD Admin or Site Admin |

### Recently Added to Group but No Access

AD group membership changes may take time to propagate:

1. Sign out completely
2. Wait 5-10 minutes for AD replication
3. Sign back in
4. If still not working, verify the group membership was applied

## Contact

For access-related questions:

- **Email:** GlobalWindowsServers@sscinc.com
- **ServiceNow:** Search "CLAWS Support"

---

*See [Roles Reference](roles.md) for detailed information about each role's permissions.*
