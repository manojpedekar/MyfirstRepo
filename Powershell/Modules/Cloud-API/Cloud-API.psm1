<#
.NOTES
	===========================================================================
	 Created with: 	Visual Studio Code
	 Updated on:   	9/19/2025
	 Created by:   	tnewnham
	 Organization: 	SS&C
	 Filename:      Cloud-API.psm1
	===========================================================================

.DESCRIPTION
This module is a set of functions to interact with the SS&C Cloud API. Each function below performs one task as simply as possible.

Please read the DESCRIPTION of each function for further information.

THIS MODULE IS STILL A WORK IN PROGRESS. SOME FUNCTIONS MAY NOT WORK. SOME MAY WORK BUT REQUIRE DATA FROM OTHER FUNCTIONS.

#>

### Get API Key
### Decrypt API Key from encrypted file, or request key if not available. 

function Unprotect-String {
    param (
    [string]$StringtoDecrypt,
    [switch]$Computer
    )

    if ($Computer) {
        $key = "LocalMachine"
    } else {
        $key = "CurrentUser"
    }
    $data = [Convert]::FromBase64String($StringtoDecrypt)
    $data = [System.Security.Cryptography.ProtectedData]::Unprotect($data, $null, [System.Security.Cryptography.DataProtectionScope]::$key)
    [System.Text.Encoding]::UTF8.GetString($data)
}

$KeyFilePath = "C:\Users\$($env:Username)\cloudapi.key" 

if ((Test-Path $KeyFilePath) -eq $True) {
    $APIKey = Unprotect-String (Get-Content $KeyFilePath)
} else {
    $APIKey = Read-Host "To use this module, provide your Cloud API key"
}

### Instance Functions

Function Get-Instance {
    <#
    .SYNOPSIS
    This module is used to get instance information from the SS&C Cloud locations. You can get all instances for an entire 'deployment-zone' or just a single instance. See SYNTAX for all options.

        NOTES: Requesting single instance information will return more detailed results than getting them at the sub-project level or higher. Recommended to get at sub-project level as a set $variable, then Get-Instance -instanceId $variable.id, for example to get deeper details.

    .EXAMPLE
    Get-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000"

    .EXAMPLE
    Get-Instance -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000"

    .EXAMPLE
    # Existence check - returns $true / $false
    Get-Instance -instanceId "i-..." -CheckOnly
    #>

    Param
    (
        [string]$instanceId,
        [string]$projectId,
        [string]$accountId,
        [string]$subprojectId,
        [string]$deploymentZoneId,
        [string]$tierId,
        [switch]$CheckOnly
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances?sort=name%2Casc"

    If ($instanceId) { $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)" }
    #If ($instanceId) { $request = $request + "&instance=" + $instanceId }
    If ($accountId) { $request = $request + "&accountId=" + $accountId }
    If ($projectId) { $request = $request + "&projectId=" + $projectId }
    If ($subprojectId) { $request = $request + "&subprojectId=" + $subprojectId + "&sort=asc"}
    If ($deploymentZoneId) { $request = $request + "&deploymentZoneId=" + $deploymentZoneId }
    If ($tierId) { $request = $request + "&tierId=" + $tierId }

    if ($CheckOnly) {
        try {
            $null = Invoke-RestMethod $request -Method 'GET' -Headers $headers
            return $true
        } catch {
            return $false
        }
    }

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers

    Return $response.content
}

Function Get-InstanceMetadata {
    <#
    .SYNOPSIS
    This function retrieves the specified instances metadata from the cloud. This information includes details like last patch date, dns aliases, etc. 

    .EXAMPLE
    Get-InstanceMetadata -instanceId "i-00000000-0000-0000-0000-0000000000000"
  
    #>
  
    Param
    (
        [string]$instanceId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.msp.ssncad.global/api/v2/compute/instances/$($instanceId)/meta"
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function Start-Instance {
    <#
	.SYNOPSIS
	This function is used to start a instance in a stopped state. 

    .EXAMPLE
    Start-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$instanceId
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)/power?action=START"

    $response = Invoke-RestMethod $request -Method 'Put' -Headers $headers

    Return $response.content

}

Function Stop-Instance {
    <#
	.SYNOPSIS
	This function is used to gracefully stop a instance in a running state.

    .EXAMPLE
    Stop-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$instanceId
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)/power?action=STOPGUEST"

    $response = Invoke-RestMethod $request -Method 'Put' -Headers $headers

    Return $response.content

}

Function Restart-Instance {
    <#
	.SYNOPSIS
	This performs a stop then start action on one or many instances.

    .EXAMPLE
    Restart-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$instanceId
    )

    $InsatnceDetails = Get-Instance -instanceId $instanceId

    if (($InsatnceDetails.state) -eq "available") { 
        Write-Host "Restarting machine '$($InsatnceDetails.name)' with ID $($InsatnceDetails.id)." -ForegroundColor Yellow
        Stop-Instance -instanceId $InsatnceDetails.id | Out-Null
        while (($InsatnceDetails = Get-Instance -instanceId $instanceId).state -ne "off") {
            Write-Host "The instance is shutting down..."
            Start-Sleep -Seconds 3
        } 
        Write-Host "Instance is shut down, waiting 30 seconds for the cloud task to complete before starting up."  -ForegroundColor Yellow
        Start-sleep -Seconds 30
        #Get-job status from cloud and wait until complete to proceed. 
        Start-Instance -instanceId $InsatnceDetails.id | Out-Null
        while (($InsatnceDetails = Get-Instance -instanceId $instanceId).state -ne "available") {
            Write-Host "The instance is booting up"
            Start-Sleep -Seconds 3
        } 
        ## Health check, tnc/etc. 
        Write-Host "Instance '$($InsatnceDetails.name)' with ID $($InsatnceDetails.id) is now available." -ForegroundColor Green
    } elseif ($InsatnceDetails.state -eq 'off') {
        Write-Host  "The instance '$($InsatnceDetails.name)' with ID $($InsatnceDetails.id) is currently powered off, would you like to power it on? y/N" -ForegroundColor Yellow
        $userInput = Read-Host "y/N"
        switch ($userInput) {
            y { 
                Start-Instance -instanceId $InsatnceDetails.id | Out-Null
                while (($InsatnceDetails = Get-Instance -instanceId $instanceId).state -ne "available") {
                    Write-Host "The instance is booting up"
                    Start-Sleep -Seconds 3
                } 
                Write-Host "Instance '$($InsatnceDetails.name)' with ID $($InsatnceDetails.id) is now available." -ForegroundColor Green
            }
            N {
                Write-Host "You have selected 'N', no action will be taken." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Instance '$($InsatnceDetails.name)' with ID $($InsatnceDetails.id) is in an unconditioned state. Validate and modify 'Restart-Instance'."
    }
}

Function Reset-Instance {
    <#
	.SYNOPSIS
	This function will hard reset an instance.

    .EXAMPLE
    Reset-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$instanceId
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)/power?action=RESET"

    $response = Invoke-RestMethod $request -Method 'Put' -Headers $headers

    Return $response.content

}

Function Invoke-InstancePower {
    <#
    .SYNOPSIS
    Sends an arbitrary power action to an instance. Wraps the /power endpoint
    so callers can pick any of START, STOP, RESET, RESETGUEST, STOPGUEST in
    one call. For the common cases prefer Start-Instance, Stop-Instance,
    Reset-Instance, or Restart-Instance.

    .EXAMPLE
    Invoke-InstancePower -instanceId "i-..." -Action STOPGUEST

    .EXAMPLE
    Invoke-InstancePower -instanceId "i-..." -Action RESETGUEST
    #>

    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$instanceId,
        [Parameter(Mandatory=$true)][ValidateSet('START','STOP','RESET','RESETGUEST','STOPGUEST')][string]$Action
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)/power?action=$($Action)"

    $response = Invoke-RestMethod $request -Method 'Put' -Headers $headers

    Return $response.content
}

Function New-Instance {
    <#
	.SYNOPSIS
	Creates a new instance in the cloud.

    .EXAMPLE
    $param = @{
        subprojectId = "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        name = "demo"
        cpu = "2"
        memory = "4"
        securitygroupIds = "securitygroup-6bc70d2c-3e1e-4e59-9e1f-bb1a74d5711b"
        site = "na-central-kc"
    }
    New-Instance @Param

    #>

    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$subprojectId,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$name,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$cpu,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$memory,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$securitygroupIds,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$site,
        [ValidateNotNullOrEmpty()][string]$domainDelegation = "cloudad.ssncad.global",
        [ValidateNotNullOrEmpty()][string]$imageId = "ssnc-cloud-w2k25-base",
        [string]$patchingGroup,
        [string]$backupPolicy,
        [string]$network
    )

    #Info Gathering
    if (!$patchingGroup) { $patchingGroup = (Get-SubProject -subprojectId $subprojectId).defaultPatchingGroup }
    # 

    #API Payload
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances"

    $jsondata = @{
        "subprojectId"                   = $subprojectId
        "name"                           = $name
        "domainDelegation"               = $domainDelegation
        "cpu"                            = $cpu
        "memory"                         = $memory
        "imageId"                        = $imageId
        "securitygroupIds"               = $securitygroupIds
        "site"                           = $site
        "network"                  = $network

    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'POST' -Headers $headers -Body $jsondata

    Return $response.content

}

Function Remove-Instance {
    <#
	.SYNOPSIS
	Removes a single specified instance ID and prompt for removal. The -Confirm switch prevents user input.

    .EXAMPLE
    Remove-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000"

    .EXAMPLE
    Remove-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000" -Confirm
    #>

    Param
    (
        [string]$instanceId,
        [switch]$Confirm
    )

    #API Payload
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)"


    #User Confirmation
    #Danny recommends: Get instance then use NAME not ID.
    if (!$Confirm) {
        Write-Host "Are you sure you wish to delete instance '$($instanceId)'? This action cannot be undone! y/N" -ForegroundColor Yellow
        $UserInput = Read-Host
        switch ($UserInput) {
            y {
                $response = Invoke-RestMethod $request -Method 'Delete' -Headers $headers
            }
            N {
                Write-Host "You have chosen to abort the instance deletion." -ForegroundColor Yellow
                Return
            }
        }
    } else {
        $response = Invoke-RestMethod $request -Method 'Delete' -Headers $headers
    }

    Return $response.content

}

Function Set-Instance {
    <#
	.SYNOPSIS
	This function is used to modify properties of an instance.

    .EXAMPLE
    Set-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000" -cpu "8" -memory "16"

    .EXAMPLE
    Set-Instance -instanceId "i-00000000-0000-0000-0000-0000000000000" -name "NewServerName"
    #>

    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$instanceId,
        [string]$name,
        [int]$cpu,
        [int]$memory,
        [string]$patchingGroup,
        [string]$backupPolicy,
        [string]$markAsEnterpriseDatabase,
        [string]$markAsEnterpriseCluster
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances/$($instanceId)"

    $tobechanged = Get-Instance -instanceId $instanceId

    if (!$name) {$name = $tobechanged.name}
    if (!$cpu) {$cpu = $tobechanged.cpu}
    if (!$memory) {$memory = $tobechanged.memory}
    if (!$patchingGroup) {$patchingGroup = $tobechanged.patchingGroup}
    if (!$backupPolicy) {$backupPolicy = $tobechanged.backupPolicy}
    if (!$markAsEnterpriseDatabase) {$markAsEnterpriseDatabase = $tobechanged.enterpriseDatabase}
    if (!$markAsEnterpriseCluster) {$markAsEnterpriseCluster = $tobechanged.enterpriseCluster}

    $jsondata = @{
        "name"                           = $name
        "cpu"                            = $cpu
        "memory"                         = $memory
        "patchingGroup"                  = $patchingGroup
        "backupPolicy"                   = $backupPolicy
        "markAsEnterpriseDatabase"       = $markAsEnterpriseDatabase
        "markAsEnterpriseCluster"        = $markAsEnterpriseCluster
        "antiAffinity"                   = "ERRORED"

    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'Put' -Headers $headers -Body $jsondata

    Return $response.content
}


### Network Functions

Function Get-NetAccess {
    <#
    .SYNOPSIS
    This function will grab information about a specified 'networkaccess' Id.

    .EXAMPLE
    Get-NetAccess -Id "networkaccess-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$Id
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/accesses/$($Id)"
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}


Function New-NetAccess {
    <#
	.SYNOPSIS
	This function is used to create access rules.

    .EXAMPLE
    $Param = @{
        name = "New Access Rule on 443/tcp"
        source = "securitygroup-6bc70d2c-3e1e-4e59-9e1f-bb1a74d5711b"
        sourcetenant = "ssnc"
        destination = securitygroup-8d38b3ea-c46f-434e-8c83-20e111b5d395
        destinationTenant = "ssnc"
        protocol = "tcp"
        ports = "443"
    }
    New-NetAccess @Param

    #>
    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Source,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SourceTenant,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Destination,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DestinationTenant,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Ports,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][ValidateSet('tcp','udp')][string]$Protocol
    )

    #$APIKey = Read-Host "Please enter your SS&C Cloud API Key"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/network/accesses"

    $jsondata = @{
            "name" =                 "$($Name)"
            "source" =               "$($Source)"
            "sourceTenant" =         "$($SourceTenant)"
            "destination" =          "$($Destination)"
            "destinationTenant" =    "$($DestinationTenant)"
            "ports" =                "$($Ports)"
            "protocol" =             "$($Protocol)"
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers -Body $jsondata

    Return $response.content
}

Function Set-NetAccess {
    <#
	.SYNOPSIS
	This function is used to modify access rules.

    Make this more involved like Set-Instance, grab unprovided information.

    .EXAMPLE
    ...

    #>
    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Source,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SourceTenant,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Destination,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$DestinationTenant,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Ports,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Protocol
    )

    #$APIKey = Read-Host "Please enter your SS&C Cloud API Key"

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/network/accesses"

    $jsondata = @{
            "name" =                 "$($Name)"
            "source" =               "$($Source)"
            "sourceTenant" =         "$($SourceTenant)"
            "destination" =          "$($Destination)"
            "destinationTenant" =    "$($DestinationTenant)"
            "ports" =                "$($Ports)"
            "protocol" =             "$($Protocol)"
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'PUT' -Headers $headers -Body $jsondata

    Return $response.content
}

Function Remove-NetAccess {
    <#
    .SYNOPSIS
    This function removes a specified 'networkaccess' Id.
  
    .EXAMPLE
    Remove-NetAccess -Id "networkaccess-00000000-0000-0000-0000-0000000000000"
    #>
  
    Param
    (
        [string]$Id
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/accesses/$($Id)"
  
    $response = Invoke-RestMethod $request -Method 'DELETE' -Headers $headers
  
    Return $response.content
}

Function Get-SecurityGroup {
    <#
    .SYNOPSIS
    This function returns details about either a single security group or all security groups within a sub-project/project.  

    NOTES: Requesting single instance/volume information will return more detailed results than getting them at the sub-project level or higher. Recommended to get at sub-project level as a set $variable, then Get-Volume -instanceId $variable.id, for example to get deeper details. 
  
    .EXAMPLE
    Get-SecurityGroup -securitygroupId "securitygroup-00000000-0000-0000-0000-0000000000000" 
  
    .EXAMPLE
    Get-SecurityGroup -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000" 
    #>
  
    Param
    (
        [string]$projectId,
        [string]$subprojectId,
        [string]$securitygroupId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups"
  
    If ($securitygroupId) { $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups/$($securitygroupId)"}
    If ($subprojectId) { $request = $request + "?resourceId=" + $subprojectId }
    If ($projectId) { $request = $request + "?resourceId=" + $projectId }

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function New-SecurityGroup {
    <#
    .SYNOPSIS
    This function creates a new cloud Security Group in the specified Sub-Project. 
  
    .EXAMPLE
    New-SecurityGroup -subprojectId "subproject-00000000-0000-0000-0000-0000000000000" -Name "..."  
    #>
  
    Param
    (
        [string]$name,
        [string]$subprojectId,
        [string]$type = "Standard"

    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups"

    $jsondata = @{
            "subprojectId" =            $subprojectId
            "name" =                    $name
            "groupPolicyEnabled" =      "$($false)"
            "type" =                    $type
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers -Body $jsondata

    Return $response.content

}

Function Add-SecurityGroupMember {
        <#
    .SYNOPSIS
    This function adds a member IP to a specified security group ID.
    
    NOTE: Only one member IP can be specified at a time. Suggest to Foreach though each instance retrieved from Get-Instance -subprojectId "..."
  
    .EXAMPLE
    Add-SecurityGroupMember -securitygroupId "securitygroup-00000000-0000-0000-0000-0000000000000" -members "10.10.10.10" 
    #>
  
    Param
    (
        [string]$securitygroupId,
        [string]$member
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups/$($securitygroupId)/members/$($member)"

    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers 

    Return $response.content
}

Function Remove-SecurityGroupMember {
        <#
    .SYNOPSIS
    This function removes a member IP from a specified security group ID.
  
    .EXAMPLE
    Remove-SecurityGroupMember -securitygroupId "securitygroup-00000000-0000-0000-0000-0000000000000" -members "10.10.10.10" 
    #>
  
    Param
    (
        [string]$securitygroupId,
        [string]$members
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups/$($securitygroupId)/members/$($members)"

    $response = Invoke-RestMethod $request -Method 'DELETE' -Headers $headers 

    Return $response.content
}

Function Remove-SecurityGroup {    
    <#
    .SYNOPSIS
    This function removes a specified security group ID. 
  
    .EXAMPLE
    Remove-SecurityGroup -securitygroupId "securitygroup-00000000-0000-0000-0000-0000000000000" 
    #>
  
    Param
    (
        [string]$securitygroupId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups/$($securitygroupId)"
  
    $response = Invoke-RestMethod $request -Method 'DELETE' -Headers $headers
  
    Return $response.content
}

Function Get-SecondaryIP {
    <#
    .SYNOPSIS
    This function returns either a single secondary-IP or all SIP's within a sub-project.  

    .EXAMPLE
    Get-SecondaryIP -ipId "sub-project-00000000-0000-0000-0000-0000000000000" 

    .EXAMPLE
    Get-SecondaryIP -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000" 
    #>
  
    Param
    (
        [string]$secondaryIpId,
        [string]$subprojectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
  
    if (!$secondaryipId) {
        $request = "https://portal.ssnc-corp.cloud/api/v2/network/secondary-ips?subprojectId=$($subprojectId)"
    } else {
        $request = "https://portal.ssnc-corp.cloud/api/v2/network/secondary-ips/$($secondaryIpId)"
    }

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function New-SecondaryIP {
    <#
    .SYNOPSIS
    This function creates secondary-IP's within a sub-project.  

    Future: Use instance ID to gather jsondata? If so, function both 

    .EXAMPLE
    $param = @{
        name = "Name"
        deploymentZoneId = "deploymentzone-na-central-kc"
        subprojectId = "subproject-00000000-0000-0000-0000-0000000000000"
        network = "10.222.123.0/24"
    }

    New-SecondaryIP @param
    #>
  
    Param
    (
        [string]$name,
        [string]$deploymentZoneId,
        [string]$subprojectId,
        [string]$network
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/secondary-ips"

    $jsondata = @{
        "name" =                 "$($Name)"
        "deploymentZoneId" =     "$($deploymentZoneId)"
        "subprojectId" =         "$($subprojectId)"
        "network" =              "$($network)"
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'POST' -Headers $headers -Body $jsondata
  
    Return $response.content
}

Function Add-SecondaryIP {
    <#
    .SYNOPSIS
    This function attaches a secondary-IP's to an instance.  

    Future: perform validation of Instance network matches secondary IP. 

    .EXAMPLE
    Add-SecondaryIP -secondaryIpId "ip-00000000-0000-0000-0000-0000000000000" -instanceId "i-00000000-0000-0000-0000-0000000000000"
    #>
  
    Param
    (
        [string]$secondaryIpId,
        [string]$instanceId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/secondary-ips/$($secondaryIpId)/members"

    $jsondata = @{
        "instanceId" = $instanceId
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'POST' -Headers $headers -Body $jsondata
  
    Return $response.content
}

Function Get-DNSAliases {
    <#
    .SYNOPSIS
    This function returns either a single secondary-IP or all SIP's within a sub-project.  

    .EXAMPLE
    Get-SecondaryIP -ipId "sub-project-00000000-0000-0000-0000-0000000000000" 

    .EXAMPLE
    Get-SecondaryIP -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000" 
    #>
  
    Param
    (
        [string]$secondaryIpId,
        [string]$subprojectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
  
    if (!$ipId) {
        $request = "https://portal.ssnc-corp.cloud/api/v2/network/secondary-ips?subprojectId=$($subprojectId)"
    } else {
        $request = "https://portal.ssnc-corp.cloud/api/v2/network/secondary-ips/$($secondaryIpId)"
    }

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function New-DNSAlias {
    <#
    .SYNOPSIS
    This function creates a new cloud DNS Alias. 
  
    .EXAMPLE
    New-SecurityGroup -subprojectId "subproject-00000000-0000-0000-0000-0000000000000" -Name "..."  
    #>
  
    Param
    (
        [string]$name,
        [string]$subprojectId
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/network/securitygroups"

    $jsondata = @{
            "subprojectId" =            $subprojectId
            "name" =                    $name
            "groupPolicyEnabled" =      "$($false)"
            "type" =                    "Standard"
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers -Body $jsondata

    Return $response.content

}

Function Confirm-DNSAliasAvailable {
    <#
    .SYNOPSIS
    This function returns either a single secondary-IP or all SIP's within a sub-project.  

    .EXAMPLE
    Get-SecondaryIP -ipId "sub-project-00000000-0000-0000-0000-0000000000000" 

    .EXAMPLE
    Get-SecondaryIP -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000" 
    #>
  
    Param
    (
        [string]$secondaryIpId,
        [string]$subprojectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
  
    if (!$ipId) {
        $request = "https://portal.ssnc-corp.cloud/api/v2/network/dns/availability"}

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function Get-DeploymentZones {
    <#
    .SYNOPSIS
    This function get all deployment zones available in an account with the '-account' parameter or all publicly available deployment zones if run stand-alone. 

    .EXAMPLE
    Get-DeploymentZones

    .EXAMPLE
    Get-DeploymentZones -accountId "account-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$Id,
        [string]$accountId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    if (![string]::IsNullOrEmpty($Id)){
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/deploymentzones/$($Id)"
    } elseif (![string]::IsNullOrEmpty($accountId)){
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/deploymentzones?accountId=$($accountId)"
    } else {
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/deploymentzones"
    }
    
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

### Storage Functions

Function Get-CloudDisk {
    <#
    .SYNOPSIS
    This function returns all volumes for the provided sub-project or instance ID. 

    NOTES: Requesting single instance/volume information will return more detailed results than getting them at the sub-project level or higher. Recommended to get at sub-project level as a set $variable, then Get-Volume -instanceId $variable.id, for example to get deeper details. 
  
    .EXAMPLE
    Get-Volume -volumeId "v-00000000-0000-0000-0000-0000000000000" 
  
    .EXAMPLE
    Get-Volume -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000" 
    #>
  
    Param
    (
        [string]$volumeId,
        [string]$subprojectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/storage/volumes"
  
    If ($volumeId) { $request = "https://portal.ssnc-corp.cloud/api/v2/storage/volumes/$($volumeId)"}
    If ($subprojectId) { $request = $request + "?subprojectId=" + $subprojectId + "&sort=name%252Casc"}
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function New-CloudDisk {
    <#
	.SYNOPSIS
	This function creates a new volume with specified settings and attaches it to the instance specified.  

    .EXAMPLE
    New-Volume -instanceId "i-00000000-0000-0000-0000-0000000000000" -size "50"

    #>
    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$instanceId,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$size,
        [string]$name,
        [string]$subprojectId,
        [string]$site,
        [string]$deploymentZoneId,
        [string]$isDatabase = $false
    )

    $Date = Get-date -Format "dd-MM-yyyy-HH-mm-ss"
    $Instance = Get-Instance -instanceId $instanceId 

    if (!$name) { $name = $Instance.name}
    if (!$subprojectId) { $subprojectId = $Instance.subprojectId}
    if (!$site) { $site = $Instance.site}
    if (!$deploymentZoneId) { $deploymentZoneId = $Instance.deploymentZoneId}

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/storage/volumes"

    $jsondata = @{
            "subprojectId" =        "$($subprojectId)"
            "instanceId" =          "$($instanceId)"
            "name" =                "$($name)-data-$($Date)"
            "site" =                "$($site)"
            "deploymentZoneId" =    "$($deploymentZoneId)"
            "isDatabase" =          "$($isDatabase)"
            "size" =                "$($size)"
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers -Body $jsondata

    Return $response.content
}

Function Set-CloudDisk {
    <#
	.SYNOPSIS
	This function creates a new volume with specified settings and attaches it to the instance specified. 

    **NOTE: this function will throw the error below. If "status" shows as processing in the return, you are good. 

    Invoke-RestMethod:  {   "message": "One of subprojectId or instanceId is required." } 

    .EXAMPLE
    New-Volume -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000" -instanceId "i-00000000-0000-0000-0000-0000000000000" -name "name" -site "na-central-kc" -deploymentZoneId "deploymentzone-na-central-kc" -isDatabase "false" -size "50"

    #>
    Param
    (
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$volumeId,
        [string]$instanceId,
        [string]$name,
        [string]$isDatabase,
        [string]$size
    )

    $Volume = Get-Volume -volumeId $volumeId
    if (!$instanceId) { $instanceId = $Volume.instanceId}
    if (!$name) { $name = $Volume.name}
    if (!$isDatabase) { $isDatabase = $Volume.isDatabase}
    if (!$size) { $instanceId = $Volume.size}

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/storage/volumes/$($volumeId)"

    $jsondata = @{
            "volumeId"      =        "$($volumeId)"
            "instanceId"    =        "$($instanceId)"
            "name"          =        "$($name)"
            "isDatabase"    =        "$($isDatabase)"
            "size"          =        "$($size)"
            "detach"        =        "$($detach)"
    } | ConvertTo-Json

    $response = Invoke-RestMethod $request -Method 'PUT' -Headers $headers -Body $jsondata

    Return $response.content
}

Function Remove-CloudDisk {
    <#
	.SYNOPSIS
	Removes a single specified volume.

    .EXAMPLE
    Remove-Volume -volumeId "v-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$volumeId
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/storage/volumes/$($volumeId)"

    $response = Invoke-RestMethod $request -Method 'Delete' -Headers $headers

    Return $response.content
}

### Uncategorized Functions

Function Get-SubProject {
    <#
    .SYNOPSIS
    This function gets sub-project information from the cloud API. 

    .EXAMPLE
    Get-SubProject -subprojectId "sub-project-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$subprojectId,
        [string]$projectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    if ($projectId){
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/subprojects?projectId=$($projectId)"
    } else {
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/subprojects/$($subprojectId)"
    }
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function Get-Project {
    <#
    .SYNOPSIS
    This function gets project information from the cloud API. 

    .EXAMPLE
    Get-Project -projectId "project-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$projectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/management/projects/$($projectId)"
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function Get-Account {
    <#
    .SYNOPSIS
    This function gets accout information from the cloud API.

    .EXAMPLE
    Get-Account -accountId "project-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$accountId
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")

    $request = "https://portal.ssnc-corp.cloud/api/v2/management/accounts/$($accountId)"

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers

    Return $response.content
}

Function Get-CloudCMDB {
    <#
    .SYNOPSIS
    Returns the CMDB record for a server identified by its primary IPv4 address.

    .DESCRIPTION
    Calls /api/v2/cmdb/server?serverIp= to look up CMDB data (including the
    vcenterId / cloud instance id) for a given IP. Useful for reconciling a
    local salt minion's identity against what the CMDB says.

    .EXAMPLE
    Get-CloudCMDB -IPAddress "10.42.117.76"

    .EXAMPLE
    Get-CloudCMDB -IPAddress (Resolve-DnsName $env:COMPUTERNAME -Type A).IPAddress
    #>

    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidatePattern("\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}")]
        [string]$IPAddress
    )

    Try {
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("x-api-key", $APIKey)
        $headers.Add("Content-Type", "application/json")

        $request = "https://portal.ssnc-corp.cloud/api/v2/cmdb/server?serverIp=$IPAddress"

        $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
        Return $response.content
    } Catch {
        Write-Error "Failed to retrieve CMDB data. $($Error[0].Exception.Message)"
        Return $null
    }
}

Function Get-ImageGroup {
    <#
    .SYNOPSIS
    This function gets project information from the cloud API. 

    .EXAMPLE
    Get-Project -projectId "project-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$projectId,
        [string]$imageGroupId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    if ($projectId) {$request = "https://portal.ssnc-corp.cloud/api/v2/compute/imagegroups?projectId=$($projectId)&sort=asc"}
    if ($imageGroupId) {$request = "https://portal.ssnc-corp.cloud/api/v2/compute/imagegroups/$($imageGroupId)/images"}
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function Get-CloudJob {
        <#
    .SYNOPSIS
    This function gets information for a specific Job ID or all jobs in a sub-project. 

    .EXAMPLE
    Get-CloudJob -jobId "job-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$jobId,
        [string]$subprojectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    if (!$subprojectId) { 
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/jobs/$($jobId)" 
    } else {
        $request = "https://portal.ssnc-corp.cloud/api/v2/management/jobs?subprojectId=$($subprojectId)&isComplete=false&sort=createdDate"
    }

    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}

Function Resume-StuckJob {
        <#
    .SYNOPSIS
    This function retries running a stuck job in the SS&C Cloud. 

    .EXAMPLE
    Resume-StuckJob -jobId "job-00000000-0000-0000-0000-0000000000000"

    #>
  
    Param
    (
        [string]$jobId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/management/jobs/$($jobId)" 

    $response = Invoke-RestMethod $request -Method 'POST' -Headers $headers
  
    Return $response.content
}

Function Get-PatchGroups {
    <#
    .SYNOPSIS
    This function gets patching group information from the cloud API. 

    .EXAMPLE
    Get-PatchGroups

    #>
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/patch-groups"
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}


Function Sync-POSIXGroups {
    <#
    .SYNOPSIS
    This function synchronizes a projects group membership. 

    .EXAMPLE
    Sync-POSIXGroups -projectId "project-00000000-0000-0000-0000-0000000000000"

    #>

    Param
    (
        [string]$projectId
    )
  
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("accept", "application/json")
  
    $request = "https://portal.ssnc-corp.cloud/api/v1/admin/ldap/ensurePosixGroups/project/$($projectId)"
  
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
  
    Return $response.content
}