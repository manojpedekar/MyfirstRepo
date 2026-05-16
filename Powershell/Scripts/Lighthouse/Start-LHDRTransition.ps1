<#
    .SYNOPSIS
        A brief description of the Start-LHDRTransition.ps1 file.
    
    .DESCRIPTION
        A description of the file.
    
    .PARAMETER Direction
        Determines the direction of the DR Event
        
        ToDR will update the FW Rules with the DR settings
        ToProd weill update the FW Rules with the Prod Settings
    
    .PARAMETER IPList
        A list of the Prod and DR IP addresses
    
    .PARAMETER msp_tenant_name
        A description of the msp_tenant_name parameter.
    
    .NOTES
        ===========================================================================
        Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
        Created on:   	6/11/2025 9:17 AM
        Created by:   	DT234083
        Organization: 	SS&C
        Filename:     	Start-LHDRTransition.ps1
        ===========================================================================
#>
Param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ToDR', 'ToProd')]
    [string]$Direction,
    [Parameter(Mandatory = $true)]
    [ValidateScript({
            If (Test-Path -Path $_ -PathType Leaf) {
                $true
            } Else {
                Throw "The file '$_' does not exist."
            }
        })]
    [string]$IPList,
    [string]$msp_tenant_name = "msplh",
    [Parameter(Mandatory = $true)]
    [pscredential]$Credentials
)

Function Encode-APICredentials {
    Param
    (
        [Parameter(Mandatory = $true)]
        [pscredential]$Credentials
    )
    
    $username = $Credentials.UserName
    $password = $Credentials.GetNetworkCredential().password
    
    # build the Base64-encoded token
    $pair = "$($username):$($password)"
    $bytes = [Text.Encoding]::ASCII.GetBytes($pair)
    $encoded = [Convert]::ToBase64String($bytes)
    
    return $encoded
}

Function Get-IPSecurityZones {
    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$msp_tenant_name,
        [Parameter(Mandatory = $true)]
        [string]$original_ip,
        [Parameter(Mandatory = $true)]
        [pscredential]$Credentials
    )
    
    $EncodedCreds = Encode-APICredentials -Credentials $Credentials
    
    # construct headers
    $headers = @{
        Authorization = "Basic $EncodedCreds"
        'Content-Type' = 'application/json'
    }
   
    $request = "https://network-api.ssnc-corp.cloud/api/v4/cloud/ip/zones?tenant=$msp_tenant_name&ip=$original_ip"

    $response = Invoke-RestMethod -Uri $request -Method 'GET' -Headers $headers
     
    $zones = $response.match.PSObject.Properties |
    Where-Object {
        ($_.Value.endpoints.PSObject.Properties.Value |
            Select-Object -ExpandProperty ip) -contains $original_ip
    } | ForEach-Object {
        [PSCustomObject]@{
            Zone = $_.Value.zone
        }
    }
    
    Return $zones
}

Function Update-NSXZone {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$zone_name,
        [Parameter(Mandatory = $true)]
        [string]$msp_tenant_name,
        [Parameter(Mandatory = $true)]
        [string]$instance_name,
        [Parameter(Mandatory = $true)]
        [string]$ip,
        [Parameter(Mandatory = $true)]
        [pscredential]$Credentials,
        [Parameter(Mandatory = $true)]
        [ValidateSet('POST', 'DELETE')]
        [string]$Action
        
    )
    
    $EncodedCreds = Encode-APICredentials -Credentials $Credentials
    
    # construct headers
    $headers = @{
        Authorization = "Basic $EncodedCreds"
        'Content-Type' = 'application/json'
    }
    
    $request = "https://network-api.ssnc-corp.cloud/api/v4/cloud/zones/$zone_name/endpoints?tenant=$msp_tenant_name"
    
    # build the payload as a normal PS object
    $payload = @{
        endpoints = @(
            @{
                name = $instance_name
                ip   = $ip
            }
        )
    }
    
    # convert to JSON
    $body = $payload | ConvertTo-Json -Depth 3
    
    $response = Invoke-RestMethod -Uri $request -Method $action -Headers $headers -Body $body
    
    return $response
}



$ProtectedSystems = Import-Csv $IPList

ForEach ($ProtectedSystem In $ProtectedSystems) {
    
    switch ($Direction) {
        ToDR {
            $original_ip = $ProtectedSystem.prod_ip
            $destination_ip = $ProtectedSystem.dr_ip
    	}
        ToProd {
            $original_ip = $ProtectedSystem.dr_ip
            $destination_ip = $ProtectedSystem.prod_ip
    	}
    }
    
    $IPSecurityZones = Get-IPSecurityZones -msp_tenant_name $msp_tenant_name -original_ip $original_ip -Credentials $Credentials
    
    ForEach ($IPSecurityZone In $IPSecurityZones) {
        $commonParams = @{
            msp_tenant_name = $msp_tenant_name
            instance_name   = $ProtectedSystem.id
            Credentials     = $Credentials
            zone_name       = $IPSecurityZone
        }
        
        Update-NSXZone @commonParams -ip $destination_ip -Action POST
        Update-NSXZone @commonParams -ip $original_ip -Action DELETE
    }
    
}

