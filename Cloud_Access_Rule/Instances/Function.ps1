Function New-CloudInstance {
    <#
    .SYNOPSIS
    This function creates cloud instances via the SS&C Cloud API.

    .DESCRIPTION
    Creates cloud instances by invoking the SS&C Cloud API endpoint. Supports
    configuration via parameters or environment variables for improved security
    and flexibility.

    .PARAMETER Name
    The name of the instance to create.

    .PARAMETER SubprojectId
    The subproject ID where the instance will be created.

    .PARAMETER DeploymentZoneId
    The deployment zone ID for the instance.

    .PARAMETER CPU
    Number of CPU cores for the instance.

    .PARAMETER Memory
    Memory in GB for the instance.

    .PARAMETER ImageId
    The image ID to use for the instance.

    .PARAMETER SecurityGroupIds
    Array of security group IDs to attach to the instance.

    .PARAMETER APIKey
    The SS&C Cloud API Key. If not provided, checks environment variable
    'SSNC_API_KEY' or prompts for user input.

    .PARAMETER APIEndpoint
    The API endpoint URL. Defaults to production endpoint if not specified.

    .PARAMETER DomainDelegation
    Optional domain delegation for the instance.

    .PARAMETER SecondaryIpId
    Optional secondary IP ID.

    .PARAMETER CloudInitId
    Optional cloud-init ID.

    .PARAMETER UserInit
    Optional user initialization script.

    .PARAMETER DatabaseType
    Optional database type (e.g., 'mysql', 'postgresql').

    .PARAMETER RequestedAsOff
    Whether to request the instance as powered off. Defaults to $false.

    .PARAMETER PatchingGroup
    Optional patching group (e.g., '3rd-sat-10pm-5am').

    .PARAMETER BackupPolicy
    Optional backup policy (e.g., 'daily').

    .PARAMETER LicenseTypes
    Optional array of license types.

    .PARAMETER CreateVolumes
    Optional array of volumes to create. Each should have 'name' and 'size' properties.

    .PARAMETER AttachVolumeIds
    Optional array of existing volume IDs to attach.

    .PARAMETER AttachPoolMembers
    Optional array of load balancer pool members. Each should have 'loadbalancerId' and 'memberPort'.

    .PARAMETER DnsAliases
    Optional array of DNS aliases.

    .PARAMETER Tags
    Optional array of tags. Each should have 'name' and 'value' properties.

    .PARAMETER StorageConfiguration
    Optional storage configuration (e.g., 'DEFAULT').

    .PARAMETER MarkAsEnterpriseDatabase
    Whether to mark as enterprise database. Defaults to $false.

    .PARAMETER MarkAsEnterpriseCluster
    Whether to mark as enterprise cluster. Defaults to $false.

    .PARAMETER AntiAffinity
    Optional anti-affinity setting (e.g., 'APPLIED').

    .PARAMETER WorkloadType
    Optional workload type (e.g., 'CLOUD_DEFAULT').

    .PARAMETER Network
    Optional network CIDR (e.g., '192.0.2.0/24').

    .EXAMPLE
    $Param = @{
        name = "My Instance"
        subprojectId = "subproject-00000000-0000-0000-0000-0000000000000"
        deploymentZoneId = "deploymentzone-00000000-0000-0000-0000-0000000000000"
        cpu = 4
        memory = 16
        imageId = "image-00000000-0000-0000-0000-0000000000000"
        securityGroupIds = @("securitygroup-00000000-0000-0000-0000-0000000000000")
        backupPolicy = "daily"
    }
    New-CloudInstance @Param -Verbose

    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SubprojectId,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DeploymentZoneId,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][int]$CPU,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][int]$Memory,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ImageId,
        [Parameter(Mandatory=$false)][string[]]$SecurityGroupIds,
        [Parameter(Mandatory=$false)][string]$APIKey,
        [Parameter(Mandatory=$false)][string]$APIEndpoint = "https://portal.ssnc-corp.cloud/api/v2/compute/instances",
        [Parameter(Mandatory=$false)][string]$DomainDelegation,
        [Parameter(Mandatory=$false)][string]$SecondaryIpId,
        [Parameter(Mandatory=$false)][string]$CloudInitId,
        [Parameter(Mandatory=$false)][string]$UserInit,
        [Parameter(Mandatory=$false)][string]$DatabaseType,
        [Parameter(Mandatory=$false)][bool]$RequestedAsOff = $false,
        [Parameter(Mandatory=$false)][string]$PatchingGroup,
        [Parameter(Mandatory=$false)][string]$BackupPolicy,
        [Parameter(Mandatory=$false)][string[]]$LicenseTypes,
        [Parameter(Mandatory=$false)][object[]]$CreateVolumes,
        [Parameter(Mandatory=$false)][string[]]$AttachVolumeIds,
        [Parameter(Mandatory=$false)][object[]]$AttachPoolMembers,
        [Parameter(Mandatory=$false)][object[]]$DnsAliases,
        [Parameter(Mandatory=$false)][object[]]$Tags,
        [Parameter(Mandatory=$false)][string]$StorageConfiguration = "DEFAULT",
        [Parameter(Mandatory=$false)][bool]$MarkAsEnterpriseDatabase = $false,
        [Parameter(Mandatory=$false)][bool]$MarkAsEnterpriseCluster = $false,
        [Parameter(Mandatory=$false)][string]$AntiAffinity,
        [Parameter(Mandatory=$false)][string]$WorkloadType = "CLOUD_DEFAULT",
        [Parameter(Mandatory=$false)][string]$Network
    )

    Begin {
        Write-Verbose "Initializing New-CloudInstance function..."
        
        if ([string]::IsNullOrEmpty($APIKey)) {
            Write-Verbose "APIKey parameter not provided, checking environment variable..."
            $APIKey = $env:SSNC_API_KEY
            
            if ([string]::IsNullOrEmpty($APIKey)) {
                Write-Verbose "No environment variable found, prompting user for API Key..."
                $APIKey = Read-Host "Please enter your SS&C Cloud API Key" -AsSecureString
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($APIKey)
                $APIKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
        }
        
        if ([string]::IsNullOrEmpty($APIKey)) {
            throw "API Key is required. Set SSNC_API_KEY environment variable or provide APIKey parameter."
        }
        
        Write-Verbose "API Endpoint: $APIEndpoint"
    }

    Process {
        try {
            Write-Verbose "Building request headers..."
            $headers = @{
                "x-api-key" = $APIKey
                "Content-Type" = "application/json"
                "accept" = "application/json"
            }

            Write-Verbose "Creating JSON payload for instance: $Name"
            
            $jsonPayload = @{
                "name" = $Name
                "subprojectId" = $SubprojectId
                "deploymentZoneId" = $DeploymentZoneId
                "cpu" = $CPU
                "memory" = $Memory
                "imageId" = $ImageId
                "storageConfiguration" = $StorageConfiguration
                "requestedAsOff" = $RequestedAsOff
                "markAsEnterpriseDatabase" = $MarkAsEnterpriseDatabase
                "markAsEnterpriseCluster" = $MarkAsEnterpriseCluster
                "workloadType" = $WorkloadType
            }

            if (-not [string]::IsNullOrEmpty($DomainDelegation)) {
                $jsonPayload["domainDelegation"] = $DomainDelegation
            }
            if (-not [string]::IsNullOrEmpty($SecondaryIpId)) {
                $jsonPayload["secondaryIpId"] = $SecondaryIpId
            }
            if (-not [string]::IsNullOrEmpty($CloudInitId)) {
                $jsonPayload["cloudInitId"] = $CloudInitId
            }
            if (-not [string]::IsNullOrEmpty($UserInit)) {
                $jsonPayload["userInit"] = $UserInit
            }
            if (-not [string]::IsNullOrEmpty($DatabaseType)) {
                $jsonPayload["databaseType"] = $DatabaseType
            }
            if (-not [string]::IsNullOrEmpty($PatchingGroup)) {
                $jsonPayload["patchingGroup"] = $PatchingGroup
            }
            if (-not [string]::IsNullOrEmpty($BackupPolicy)) {
                $jsonPayload["backupPolicy"] = $BackupPolicy
            }
            if (-not [string]::IsNullOrEmpty($AntiAffinity)) {
                $jsonPayload["antiAffinity"] = $AntiAffinity
            }
            if (-not [string]::IsNullOrEmpty($Network)) {
                $jsonPayload["network"] = $Network
            }

            if ($null -ne $SecurityGroupIds -and $SecurityGroupIds.Count -gt 0) {
                $jsonPayload["securityGroupIds"] = $SecurityGroupIds
            }
            if ($null -ne $LicenseTypes -and $LicenseTypes.Count -gt 0) {
                $jsonPayload["licenseTypes"] = $LicenseTypes
            }
            if ($null -ne $CreateVolumes -and $CreateVolumes.Count -gt 0) {
                $jsonPayload["createVolumes"] = $CreateVolumes
            }
            if ($null -ne $AttachVolumeIds -and $AttachVolumeIds.Count -gt 0) {
                $jsonPayload["attachVolumeIds"] = $AttachVolumeIds
            }
            if ($null -ne $AttachPoolMembers -and $AttachPoolMembers.Count -gt 0) {
                $jsonPayload["attachPoolMembers"] = $AttachPoolMembers
            }
            if ($null -ne $DnsAliases -and $DnsAliases.Count -gt 0) {
                $jsonPayload["dnsAliases"] = $DnsAliases
            }
            if ($null -ne $Tags -and $Tags.Count -gt 0) {
                $jsonPayload["tags"] = $Tags
            }

            $jsondata = $jsonPayload | ConvertTo-Json -Depth 10

            Write-Verbose "Sending POST request to API endpoint..."
            Write-Verbose "Request body: $jsondata"

            try {
                $response = Invoke-RestMethod $APIEndpoint `
                    -Method 'Post' `
                    -Headers $headers `
                    -Body $jsondata `
                    -TimeoutSec 30 `
                    -ErrorAction Stop
            }
            catch {
                $errorResponse = $_.Exception.Response
                $statusCode = $errorResponse.StatusCode.value__
                
                try {
                    $stream = $errorResponse.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                    Write-Verbose "API Error Response Body: $responseBody"
                }
                catch {
                    $responseBody = "Could not read response body"
                }
                
                throw "API Error ($statusCode): $responseBody"
            }

            Write-Verbose "Response received: $(($response | ConvertTo-Json -Compress))"

            if ($null -eq $response) {
                throw "API returned null response. Please verify the request parameters."
            }

            if ($response.status -eq 'error' -or $response.error) {
                throw "API Error: $($response.error -join '; ')"
            }

            Write-Verbose "Instance created successfully."
            return $response.content
        }
        catch {
            Write-Error "Failed to create instance: $_"
            throw
        }
    }

    End {
        Write-Verbose "New-CloudInstance function completed."
    }
}

Function New-CloudInstanceBatch {
    <#
    .SYNOPSIS
    Imports cloud instance definitions from JSON and creates them.

    .DESCRIPTION
    Reads a JSON file containing one or more instance objects and invokes
    New-CloudInstance for each entry. This is useful for bulk imports and 
    repeatable configuration.

    .PARAMETER JsonPath
    Path to the JSON file containing the instance definitions.

    .PARAMETER APIKey
    Optional API key to use for all requests. If omitted, each New-CloudInstance 
    call will resolve the key from environment or prompt as configured.

    .PARAMETER APIEndpoint
    Optional API endpoint to use for all requests.

    .PARAMETER ContinueOnError
    If specified, the function continues processing remaining instances after a failure.

    .EXAMPLE
    New-CloudInstanceBatch -JsonPath "C:\instances\Instances.json" -Verbose

    .EXAMPLE
    New-CloudInstanceBatch -JsonPath "C:\instances\Instances.json" -ContinueOnError -Verbose

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$JsonPath,
        [Parameter(Mandatory=$false)][string]$APIKey,
        [Parameter(Mandatory=$false)][string]$APIEndpoint = "https://portal.ssnc-corp.cloud/api/v2/compute/instances",
        [Parameter(Mandatory=$false)][Switch]$ContinueOnError
    )

    Begin {
        if (-not (Test-Path -Path $JsonPath -PathType Leaf)) {
            throw "JSON file not found: $JsonPath"
        }

        Write-Verbose "Reading JSON file: $JsonPath"
        $rawJson = Get-Content -Path $JsonPath -Raw
        try {
            $parsedJson = $rawJson | ConvertFrom-Json
        }
        catch {
            throw "Failed to parse JSON file '$JsonPath': $_"
        }

        if ($null -eq $parsedJson) {
            throw "JSON file '$JsonPath' is empty or invalid."
        }

        if ($parsedJson.PSObject.Properties.Name -contains 'instances') {
            $instances = $parsedJson.instances
        }
        else {
            $instances = $parsedJson
        }

        if ($null -eq $instances) {
            throw "No instance objects found in JSON file '$JsonPath'."
        }

        if ($instances -is [System.Collections.IEnumerable] -and $instances -isnot [string]) {
            $instanceList = @($instances)
        }
        else {
            $instanceList = @($instances)
        }

        if ($instanceList.Count -eq 0) {
            throw "JSON file '$JsonPath' contains no instance entries."
        }

        Write-Verbose "Loaded $($instanceList.Count) instance(s) from JSON."
    }

    Process {
        foreach ($instance in $instanceList) {
            $instanceName = $instance.name
            if ([string]::IsNullOrEmpty($instanceName)) {
                $instanceName = "Unnamed instance"
            }

            Write-Verbose "Processing instance: $instanceName"

            $parameters = @{
                Name = $instance.name
                SubprojectId = $instance.subprojectId
                DeploymentZoneId = $instance.deploymentZoneId
                CPU = $instance.cpu
                Memory = $instance.memory
                ImageId = $instance.imageId
                APIKey = $APIKey
                APIEndpoint = $APIEndpoint
            }

            if ($null -ne $instance.domainDelegation) {
                $parameters["DomainDelegation"] = $instance.domainDelegation
            }
            if ($null -ne $instance.securityGroupIds) {
                $parameters["SecurityGroupIds"] = $instance.securityGroupIds
            }
            if ($null -ne $instance.secondaryIpId) {
                $parameters["SecondaryIpId"] = $instance.secondaryIpId
            }
            if ($null -ne $instance.cloudInitId) {
                $parameters["CloudInitId"] = $instance.cloudInitId
            }
            if ($null -ne $instance.userInit) {
                $parameters["UserInit"] = $instance.userInit
            }
            if ($null -ne $instance.databaseType) {
                $parameters["DatabaseType"] = $instance.databaseType
            }
            if ($null -ne $instance.requestedAsOff) {
                $parameters["RequestedAsOff"] = $instance.requestedAsOff
            }
            if ($null -ne $instance.patchingGroup) {
                $parameters["PatchingGroup"] = $instance.patchingGroup
            }
            if ($null -ne $instance.backupPolicy) {
                $parameters["BackupPolicy"] = $instance.backupPolicy
            }
            if ($null -ne $instance.licenseTypes) {
                $parameters["LicenseTypes"] = $instance.licenseTypes
            }
            if ($null -ne $instance.createVolumes) {
                $parameters["CreateVolumes"] = $instance.createVolumes
            }
            if ($null -ne $instance.attachVolumeIds) {
                $parameters["AttachVolumeIds"] = $instance.attachVolumeIds
            }
            if ($null -ne $instance.attachPoolMembers) {
                $parameters["AttachPoolMembers"] = $instance.attachPoolMembers
            }
            if ($null -ne $instance.dnsAliases) {
                $parameters["DnsAliases"] = $instance.dnsAliases
            }
            if ($null -ne $instance.tags) {
                $parameters["Tags"] = $instance.tags
            }
            if ($null -ne $instance.storageConfiguration) {
                $parameters["StorageConfiguration"] = $instance.storageConfiguration
            }
            if ($null -ne $instance.markAsEnterpriseDatabase) {
                $parameters["MarkAsEnterpriseDatabase"] = $instance.markAsEnterpriseDatabase
            }
            if ($null -ne $instance.markAsEnterpriseCluster) {
                $parameters["MarkAsEnterpriseCluster"] = $instance.markAsEnterpriseCluster
            }
            if ($null -ne $instance.antiAffinity) {
                $parameters["AntiAffinity"] = $instance.antiAffinity
            }
            if ($null -ne $instance.workloadType) {
                $parameters["WorkloadType"] = $instance.workloadType
            }
            if ($null -ne $instance.network) {
                $parameters["Network"] = $instance.network
            }

            if ($PSCmdlet.ShouldProcess($instanceName, 'Create cloud instance')) {
                try {
                    if ($PSBoundParameters.ContainsKey('Verbose')) {
                        New-CloudInstance @parameters -Verbose
                    }
                    else {
                        New-CloudInstance @parameters
                    }
                    Write-Verbose "Successfully created instance: $instanceName"
                }
                catch {
                    Write-Error "Failed to create instance '$instanceName': $_"
                    if (-not $ContinueOnError) {
                        throw
                    }
                }
            }
        }
    }

    End {
        Write-Verbose "New-CloudInstanceBatch completed."
    }
}
