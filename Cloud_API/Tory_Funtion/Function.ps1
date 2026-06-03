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

    $APIKey = Read-Host "Please enter your SS&C Cloud API Key"

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