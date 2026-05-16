# NTFSPermsUploader

A web application for uploading, validating, and importing zipped SQLite databases produced by CollectNTFSPerms into a central SQL Server database.

## Overview

NTFSPermsUploader provides:
- **Web UI** for uploading ZIP files containing SQLite databases
- **REST API** for automated upload workflows
- **Real-time progress updates** via SignalR
- **Background processing** with Hangfire for large imports
- **Windows Authentication** with Active Directory group-based authorization
- **API key authentication** for programmatic access

## Prerequisites

- Windows Server 2022
- IIS with ASP.NET Core Module v2
- .NET 8 Hosting Bundle
- SQL Server 2019+ (for data storage)

## Quick Start

### 1. Install IIS Features

```powershell
Install-WindowsFeature Web-Server, Web-WebServer, Web-Common-Http, Web-Security, Web-Filtering, Web-App-Dev, Web-Net-Ext45, Web-Asp-Net45, Web-ISAPI-Ext, Web-ISAPI-Filter -IncludeManagementTools
```

### 2. Install .NET 8 Hosting Bundle

Download from: https://dotnet.microsoft.com/download/dotnet/8.0

### 3. Deploy the Application

```powershell
# Build the project
dotnet publish src/NTFSPermsUploader.Web -c Release -o publish

# Run the installation script
cd deploy
.\Install-NTFSPermsUploader.ps1 -SiteName "NTFSPermsUploader" -Port 443 -CertThumbprint "<your-cert-thumbprint>"
```

### 4. Configure the Application

1. Navigate to https://your-server/Admin/Configuration
2. Configure SQL Server connection
3. Configure AD authorization groups (recommended)
4. Configure storage paths (recommended for production)

## Configuration

All configuration is managed through the admin web interface. Settings are stored in the database with sensitive values encrypted using ASP.NET Core Data Protection.

### Key Settings

| Category | Setting | Description | Default |
|----------|---------|-------------|---------|
| SQL Server | Server | SQL Server hostname/instance | Required |
| SQL Server | Database | Target database name | Required |
| Authorization | Admin Group | AD group for full access | Empty (open access) |
| Authorization | Upload Group | AD group for upload access | Empty (all users) |
| Storage | Import Base Path | Base path for file operations | {App}\ImportData |
| Upload Limits | Max Upload Size | Maximum ZIP file size | 3 GB |
| Cleanup | Completed Retention | Days to keep completed files | 7 |

## API Usage

### Authentication

All API endpoints (except health checks) require an API key:

```bash
curl -H "X-API-Key: your-api-key" https://server/api/v1/uploads
```

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/v1/upload | Upload a ZIP file |
| GET | /api/v1/upload/{id}/status | Get upload status |
| GET | /api/v1/upload/{id}/logs | Get upload logs |
| DELETE | /api/v1/upload/{id} | Cancel/delete upload |
| GET | /api/v1/uploads | List uploads (paginated) |
| GET | /api/v1/health | Health check |
| GET | /api/v1/health/ready | Readiness check |

### Upload Example

```bash
curl -X POST \
  -H "X-API-Key: your-api-key" \
  -F "file=@database.zip" \
  https://server/api/v1/upload
```

Response:
```json
{
  "success": true,
  "data": {
    "uploadId": "guid",
    "status": "Queued",
    "message": "File validated successfully. Import queued.",
    "queuePosition": 1
  },
  "timestamp": "2025-01-15T10:30:00Z"
}
```

## ZIP File Requirements

- **Single file only**: ZIP must contain exactly one file
- **No directories**: No folder entries allowed
- **SQLite database**: Must be a valid SQLite database
- **Version requirements**: Must meet minimum schema and app version

## Architecture

```
NTFSPermsUploader/
├── src/
│   ├── NTFSPermsUploader.Web/     # ASP.NET Core MVC
│   ├── NTFSPermsUploader.Core/    # Business logic
│   ├── NTFSPermsUploader.Data/    # Data access
│   └── NTFSPermsUploader.Jobs/    # Background jobs
├── tests/
│   ├── NTFSPermsUploader.Tests.Unit/
│   └── NTFSPermsUploader.Tests.Integration/
├── deploy/                         # PowerShell scripts
└── docs/                           # Documentation
```

## Troubleshooting

### Upload Fails with "Insufficient Disk Space"

Ensure the import volume has at least 50 GB free space (configurable).

### Import Hangs at High Percentage

Large tables (Folders, ACE) can take significant time. Check Hangfire dashboard for job status.

### "Database Not Configured" Warning

Navigate to Admin > Configuration and enter SQL Server connection details.

### API Returns 401 Unauthorized

1. Verify API key is valid and not expired
2. Check that the X-API-Key header is included
3. Ensure the API key is enabled in admin panel

## Security Considerations

- Always use HTTPS in production
- Configure authorization groups to restrict access
- Regularly rotate API keys
- Store import data on a dedicated volume
- Monitor disk space alerts

## License

See LICENSE file in root directory.
