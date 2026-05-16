# API Keys

API keys allow automated processes to authenticate with NTFSPermsUploader without user interaction. This is essential for scheduled collection uploads.

## Overview

API keys provide:
- **Non-interactive authentication** for scripts and scheduled tasks
- **Per-user tracking** of automated uploads
- **Revocable access** without changing passwords
- **Scoped permissions** based on the key owner's role

## Managing Your API Keys

### Accessing API Key Management

1. Sign in to NTFSPermsUploader
2. Click your username in the top-right corner
3. Select **My API Keys**

### Creating an API Key

1. Go to **My API Keys**
2. Click **Create New Key**
3. Enter a descriptive name (e.g., "FileServer01 Upload Script")
4. Click **Create**
5. **Important:** Copy the key immediately - it will only be displayed once

```
Your new API key: ak_7f8a9b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u
```

### API Key Security

**Critical:** API keys are displayed only once at creation. Store them securely:

- Save in a secure credential manager (Windows Credential Manager, Azure Key Vault)
- Never commit keys to source control
- Never share keys via email or chat
- Rotate keys periodically

### Revoking an API Key

If a key is compromised or no longer needed:

1. Go to **My API Keys**
2. Find the key in the list
3. Click **Revoke**
4. Confirm the revocation

Revoked keys are immediately invalidated.

## Using API Keys

### HTTP Header Authentication

Include the API key in the `X-API-Key` header:

```powershell
$headers = @{
    "X-API-Key" = "ak_7f8a9b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u"
}

Invoke-RestMethod -Uri "https://ntfsperms.example.com/api/upload" `
    -Method POST `
    -Headers $headers `
    -InFile "collection.db"
```

### PowerShell Example

```powershell
# Upload NTFS collection using API key
$apiKey = Get-Content "C:\Secure\ntfsperms-apikey.txt"
$uploadUrl = "https://ntfsperms.example.com/api/upload/ntfs"
$collectionFile = "C:\Collections\NTFSPerms_SERVER01_20240115.db"

$response = Invoke-RestMethod -Uri $uploadUrl `
    -Method POST `
    -Headers @{ "X-API-Key" = $apiKey } `
    -ContentType "application/octet-stream" `
    -InFile $collectionFile

Write-Host "Upload ID: $($response.uploadId)"
```

### Storing Keys Securely

#### Windows Credential Manager

```powershell
# Store key
cmdkey /generic:NTFSPermsUploader /user:apikey /pass:ak_your_key_here

# Retrieve key in script
$cred = cmdkey /list:NTFSPermsUploader
```

#### Encrypted File

```powershell
# Store key (one-time setup)
$key = Read-Host "Enter API Key" -AsSecureString
$key | ConvertFrom-SecureString | Set-Content "C:\Secure\apikey.txt"

# Retrieve key in script
$secureKey = Get-Content "C:\Secure\apikey.txt" | ConvertTo-SecureString
$apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
)
```

## API Key Permissions

API keys inherit the permissions of their owner:

| Owner's Role | API Key Can... |
|--------------|----------------|
| NTFS Uploader | Upload NTFS collections only |
| AD Uploader | Upload AD collections only |
| Operator | Upload any type, manage collections |
| Administrator | Full API access |

If your role changes, your API keys' effective permissions change too.

## Best Practices

### Naming Conventions

Use descriptive names that identify:
- The server or service using the key
- The purpose of the automation

Examples:
- `FileServer01-DailyUpload`
- `DC01-ADInventory-Weekly`
- `Automation-AllServers-NTFSPerms`

### Key Rotation

Rotate API keys periodically:

1. Create a new key with the same purpose
2. Update your automation to use the new key
3. Verify the automation works
4. Revoke the old key

Recommended rotation schedule:
- **Minimum:** Annually
- **Recommended:** Every 6 months
- **High security:** Quarterly

### One Key Per Automation

Create separate keys for different automations:
- Easier to track which automation uploads what
- Revoke specific access without affecting others
- Clearer audit trail

### Monitor Key Usage

Administrators can view:
- When each key was last used
- Upload history per key
- Failed authentication attempts

## Troubleshooting

### "Invalid API Key" Error

1. Verify the key is copied correctly (no extra spaces)
2. Check if the key has been revoked
3. Ensure the key owner still has appropriate access

### "Forbidden" Error

The API key is valid but lacks permission:
1. Check the key owner's role
2. Verify the owner is in the appropriate AD group
3. Request additional access if needed

### Key Not Working After Role Change

If your AD group membership changed:
1. The API key inherits your new (reduced) permissions
2. Create a new key if you've gained permissions
3. Old keys won't automatically gain new permissions

## Administrator Functions

Administrators can manage all API keys:

1. Go to **Admin** > **API Keys**
2. View all active keys across all users
3. Revoke any key if needed
4. See usage statistics and last-used dates

### Bulk Key Management

For security incidents, administrators can:
- Revoke all keys for a specific user
- Revoke all keys (emergency lockout)
- Export key audit logs

---

*For API endpoint documentation, see [API Upload](../uploading/api-upload.md).*
