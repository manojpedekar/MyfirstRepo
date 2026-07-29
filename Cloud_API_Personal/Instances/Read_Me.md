# Cloud Instance Creation Guide

This folder contains PowerShell functions and configuration files for creating cloud instances via the SS&C Cloud API.

## Quick Start

1. Set your API key as an environment variable:
   ```powershell
   $env:SSNC_API_KEY = "your-api-key"
   ```

2. Dot-source the Function.ps1 file:
   ```powershell
   . .\Function.ps1
   ```

3. Create a single instance:
   ```powershell
   $Param = @{
       name = "My Instance"
       subprojectId = "subproject-00000000-0000-0000-0000-0000000000000"
       deploymentZoneId = "deploymentzone-00000000-0000-0000-0000-0000000000000"
       cpu = 4
       memory = 16
       imageId = "image-00000000-0000-0000-0000-0000000000000"
       securityGroupIds = @("securitygroup-00000000-0000-0000-0000-0000000000000")
   }
   New-CloudInstance @Param -Verbose
   ```

4. Or create multiple instances from JSON file:
   ```powershell
   New-CloudInstanceBatch -JsonPath "C:\path\to\Instances.json" -Verbose
   ```

## Environment Setup

### Option 1: Environment Variable (Recommended)
```powershell
$env:SSNC_API_KEY = "your-api-key"
```

### Option 2: Provide API Key as Parameter
```powershell
New-CloudInstanceBatch -JsonPath "C:\path\to\Instances.json" -APIKey "your-api-key" -Verbose
```

### Option 3: Prompt for API Key
If no API key is provided or found in environment, you'll be prompted to enter it.

## Functions

### New-CloudInstance
Creates a single cloud instance with the specified parameters.

**Parameters:**
- `Name` (required): Instance name
- `SubprojectId` (required): Subproject ID
- `DeploymentZoneId` (required): Deployment zone ID
- `CPU` (required): Number of CPU cores
- `Memory` (required): Memory in GB
- `ImageId` (required): Image ID to use
- `SecurityGroupIds` (optional): Array of security group IDs
- `BackupPolicy` (optional): Backup policy (e.g., 'daily', 'weekly')
- `PatchingGroup` (optional): Patching schedule
- `DatabaseType` (optional): Database type (e.g., 'mysql', 'postgresql')
- `DomainDelegation` (optional): Domain delegation
- `CreateVolumes` (optional): Array of volumes to create
- `Tags` (optional): Array of tags with name/value pairs
- `APIKey` (optional): API key (uses environment variable if not provided)

**Example:**
```powershell
$Param = @{
    name = "Production Web Server"
    subprojectId = "subproject-00000000-0000-0000-0000-0000000000001"
    deploymentZoneId = "deploymentzone-00000000-0000-0000-0000-0000000000001"
    cpu = 4
    memory = 16
    imageId = "image-00000000-0000-0000-0000-0000000000001"
    securityGroupIds = @("securitygroup-web-00000000-0000-0000-0000-0000000000001")
    backupPolicy = "daily"
    patchingGroup = "3rd-sat-10pm-5am"
    tags = @(
        @{ name = "Environment"; value = "Production" },
        @{ name = "Team"; value = "DevOps" }
    )
}
New-CloudInstance @Param -Verbose
```

### New-CloudInstanceBatch
Creates multiple cloud instances from a JSON configuration file.

**Parameters:**
- `JsonPath` (required): Path to JSON file with instance definitions
- `APIKey` (optional): API key for all requests
- `APIEndpoint` (optional): Custom API endpoint
- `ContinueOnError` (optional): Continue processing if an instance fails

**JSON File Format:**
```json
{
  "instances": [
    {
      "name": "Instance 1",
      "subprojectId": "...",
      "deploymentZoneId": "...",
      "cpu": 4,
      "memory": 16,
      "imageId": "...",
      "securityGroupIds": ["..."],
      "backupPolicy": "daily"
    }
  ]
}
```

**Examples:**
```powershell
New-CloudInstanceBatch -JsonPath "C:\instances\Instances.json" -Verbose

New-CloudInstanceBatch -JsonPath "C:\instances\Instances.json" -ContinueOnError -Verbose

New-CloudInstanceBatch -JsonPath "C:\instances\Instances.json" -APIKey "your-api-key" -Verbose
```

## Files

- **Function.ps1**: Contains `New-CloudInstance` and `New-CloudInstanceBatch` PowerShell functions
- **Instances.json**: Example configuration file with sample instances
- **Read_Me.md**: This file

## Common Use Cases

### Create a Web Server
```powershell
$Param = @{
    name = "Web Server"
    subprojectId = "subproject-xxx"
    deploymentZoneId = "deploymentzone-xxx"
    cpu = 4
    memory = 16
    imageId = "image-xxx"
    securityGroupIds = @("securitygroup-web-xxx")
    backupPolicy = "daily"
}
New-CloudInstance @Param -Verbose
```

### Create a Database Server with Volumes
```powershell
$Param = @{
    name = "Database Server"
    subprojectId = "subproject-xxx"
    deploymentZoneId = "deploymentzone-xxx"
    cpu = 8
    memory = 32
    imageId = "image-xxx"
    databaseType = "mysql"
    securityGroupIds = @("securitygroup-db-xxx")
    createVolumes = @(
        @{ name = "data"; size = 100 },
        @{ name = "logs"; size = 50 }
    )
    markAsEnterpriseDatabase = $true
    backupPolicy = "daily"
}
New-CloudInstance @Param -Verbose
```

### Create Multiple Instances from JSON
1. Prepare an Instances.json file with your configuration
2. Run: `New-CloudInstanceBatch -JsonPath "C:\path\to\Instances.json" -Verbose`

## Troubleshooting

### API Key Not Found
Ensure you have set the `SSNC_API_KEY` environment variable or provide it as a parameter.

### JSON Parse Error
Verify your JSON file is valid. Check for missing commas, quotes, or brackets.

### Instance Creation Failed
Check the verbose output for API error details. Common issues:
- Invalid subproject/deployment zone IDs
- Security group IDs don't exist
- Insufficient resources in deployment zone

Use `-Verbose` flag for detailed error messages:
```powershell
New-CloudInstanceBatch -JsonPath "C:\path\to\Instances.json" -Verbose
```

## Advanced Options

### Skip Powering On
```powershell
$Param = @{
    name = "Instance"
    requestedAsOff = $true
    # ... other parameters
}
New-CloudInstance @Param -Verbose
```

### Add DNS Aliases
```powershell
$Param = @{
    name = "Instance"
    dnsAliases = @(
        @{
            hostname = "myapp"
            domain = ".ssnc-corp.cloud"
        }
    )
    # ... other parameters
}
New-CloudInstance @Param -Verbose
```

### Attach Load Balancer
```powershell
$Param = @{
    name = "Instance"
    attachPoolMembers = @(
        @{
            loadbalancerId = "tier-xxx"
            memberPort = 8080
        }
    )
    # ... other parameters
}
New-CloudInstance @Param -Verbose
```

## Additional Resources

- API Endpoint: `/api/v2/compute/instances`
- Default Endpoint: `https://portal.ssnc-corp.cloud/api/v2/compute/instances`
- For network access rules, see the parent Cloud_Access_Rule folder
