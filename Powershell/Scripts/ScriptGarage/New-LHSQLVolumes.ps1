<#
    .SYNOPSIS
        Creates SQL data volumes on a set of Lighthouse cloud instances
        from a CSV of allocations.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed 2025-01-13 to create
        SQL data volumes for the Lighthouse subproject migration. Reads
        C:\temp\sqlstorage.csv (one row per (Server, DriveLetter, VolumeName,
        Allocated GB plus 20%)) and posts one Create Volume call per row.

        Volume names follow the original convention "<ServerName> - <Drive> -
        <VolumeName>". The Cloud-API module's New-CloudDisk auto-appends
        "-data-<timestamp>" to names, which would differ from what was
        originally created in production, so the inline Get-CloudInstances
        and New-CloudDisk helpers are preserved here as the historical
        record of what actually executed.

        Do not re-run without reviewing the hardcoded subproject ID and
        confirming the storage allocations are still desired.
#>

Function Get-CloudInstances {
    Param
    (
        [ValidateNotNullOrEmpty()]
        [string]$APIKey,
        [string]$projectId,
        [string]$accountId,
        [string]$subprojectId,
        [string]$tierId,
        [string]$deploymentZoneId
    )
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    
    $request = "https://portal.ssnc-corp.cloud/api/v2/compute/instances?sort=name%2Casc"
    
    If ($accountId) { $request = $request + "&accountId=" + $accountId }
    If ($projectId) { $request = $request + "&projectId=" + $projectId }
    If ($subprojectId) { $request = $request + "&subprojectId=" + $subprojectId }
    If ($tierId) { $request = $request + "&tierId=" + $tierId }
    If ($deploymentZoneId) { $request = $request + "&deploymentZoneId=" + $deploymentZoneId }
    
    $response = Invoke-RestMethod $request -Method 'GET' -Headers $headers
    
    Return $response.content
}


Function New-CloudDisk {
    Param
    (
        [string]$subproject,
        [string]$instance,
        [string]$volName,
        [string]$Site,
        [string]$deploymentZoneID,
        [boolean]$isDatabase,
        [int]$size,
        [ValidateNotNullOrEmpty()]
        [string]$APIKey
    )
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")
    
    $request = "https://portal.ssnc-corp.cloud/api/v2/storage/volumes"
    
    $jsondata = @{
        "subprojectId"     = $subproject
        "instanceId"       = $instance
        "name"             = $volName
        "site"             = $Site
        "deploymentZoneId" = $deploymentZoneID
        "isDatabase"       = $isDatabase
        "size"             = $size
    } | ConvertTo-Json
       
    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers -Body $jsondata
    
    Return $response.content
}


$APIKey = ""

$Instances = Get-CloudInstances -APIKey $APIKey -subprojectId subproject-9cb9a2b2-2634-4fdd-8d38-c7f526250ed3

$SQLStorage = import-csv C:\temp\sqlstorage.csv | ? {$_.DriveLetter -ne "C:"}

ForEach ($Instance In $Instances) {
    
   $storageneeds = $SQLStorage | Where-Object { $_.Server -eq $Instance.name}
    
    If ($storageneeds) {
        
        ForEach ($LHDisk In $storageneeds) {
            
            $roundedNumber = [Math]::Ceiling($LHDisk."Allocated GB plus 20%")
            If ($roundedNumber -eq 10000) { $roundedNumber = 1000 }
            $isDBDisk= if ($LHDisk.VolumeName -like "SQL*"){$true}else{$false}
            
            $Param = @{
                subproject       = $Instance.subprojectId
                instance         = $Instance.id
                volName          = "$($Instance.name) - $($LHDisk.DriveLetter) - $($LHDisk.VolumeName)"
                Site             = $Instance.site
                deploymentZoneID = $Instance.deploymentZoneId
                isDatabase       = $isDBDisk
                size             = $roundedNumber
            }
            
            New-CloudDisk @Param -APIKey $APIKey
            
        }
        
        
    }
  
}

