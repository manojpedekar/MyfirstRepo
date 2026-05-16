<#
    .SYNOPSIS
        Opens TCP/3389 (RDP) from one dev security group to 22 Lighthouse
        Asia destination security groups in the msplh tenant.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Originally executed 2025-12-10 to bulk-add
        RDP access rules during Lighthouse Asia onboarding. Iterates the
        $Dest array (22 specific securitygroup IDs) and calls New-NetAccess
        once per destination.

        The Cloud-API module also has a New-NetAccess function with the same
        signature. The inline copy below was the version actually used at
        the time and is preserved as the historical record.

        The trailing "ForEach ($r In $LHAsiaRules)" loop is broken in the
        original - $LHAsiaRules is never defined - preserved as-is.

        The Get-CloudSecurityGroups helper that was defined inline and never
        called has been removed. The canonical version lives in the Cloud-API
        module as Get-SecurityGroup.
#>



Function New-NetAccess {
<#
    .SYNOPSIS
        This function is used to create access rules.
    
    .DESCRIPTION
        A detailed description of the New-NetAccess function.
    
    .PARAMETER Name
        A description of the Name parameter.
    
    .PARAMETER Source
        A description of the Source parameter.
    
    .PARAMETER SourceTenant
        A description of the SourceTenant parameter.
    
    .PARAMETER Destination
        A description of the Destination parameter.
    
    .PARAMETER DestinationTenant
        A description of the DestinationTenant parameter.
    
    .PARAMETER Ports
        A description of the Ports parameter.
    
    .PARAMETER Protocol
        A description of the Protocol parameter.
    
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
    
    .NOTES
        Additional information about the function.
#>
    
    Param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceTenant,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationTenant,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Ports,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('tcp', 'udp')]
        [string]$Protocol
    )
    
    #$APIKey = Read-Host "Please enter your SS&C Cloud API Key"
    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("x-api-key", $APIKey)
    $headers.Add("Content-Type", "application/json")
    $headers.Add("accept", "application/json")
    
    $request = "https://portal.ssnc-corp.cloud/api/v2/network/accesses"
    
    $jsondata = @{
        "name"              = "$($Name)"
        "source"            = "$($Source)"
        "sourceTenant"      = "$($SourceTenant)"
        "destination"       = "$($Destination)"
        "destinationTenant" = "$($DestinationTenant)"
        "ports"             = "$($Ports)"
        "protocol"          = "$($Protocol)"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod $request -Method 'Post' -Headers $headers -Body $jsondata
    
    Return $response.content
}


$Sourceid = 'securitygroup-b0861e52-f1c3-4335-9503-1e4ea5e3a802'


$Dest = @(
    'securitygroup-9f88baa9-b250-4d7c-ae7c-b3aa6c5957eb',
    'securitygroup-5b92f84e-2eba-4696-8d1b-a2e85809ac18',
    'securitygroup-1c42e92d-1418-4d81-b24c-5c465d933646',
    'securitygroup-46ffa01d-74c3-4072-b75a-81039b3612d7',
    'securitygroup-2b723b5a-183f-472a-b8d0-784da20cb03a',
    'securitygroup-4007a8b5-a851-4285-8ec9-c4f6f79e76d2',
    'securitygroup-1166717e-3f56-4a42-b173-becff8f2fdd6',
    'securitygroup-02c2db3d-f151-487d-a530-6c221fa16ba2',
    'securitygroup-d66d3570-0f50-4222-9314-bd88a5545428',
    'securitygroup-c025ba11-6cbd-4531-bfef-1ee9063fa111',
    'securitygroup-16c7264b-9e8b-4e7a-a869-60bda39328d0',
    'securitygroup-b6066315-fff4-4bd9-9dec-06ebc7b47ba0',
    'securitygroup-beb0e53f-2cb2-46de-8213-20565508cb9b',
    'securitygroup-3d5d835c-4b72-4e51-88b7-4f1b5bc54e0b',
    'securitygroup-0b8fa8d5-afca-4315-8add-58ea5d080520',
    'securitygroup-596e4ec7-df00-4f51-acb6-6064e76351ab',
    'securitygroup-efd28c3b-9b10-422f-bfad-5d987a65dd2e',
    'securitygroup-8d48cf72-e2e0-4a15-b7e6-e201d433c9e6',
    'securitygroup-ccea4f04-5446-4f35-ad40-9677549fa512',
    'securitygroup-e4b60437-bc7c-45ec-b323-38f54168d3e3',
    'securitygroup-5580522d-ead3-478b-b062-d6449b5807dc',
    'securitygroup-199a53c9-c9fb-4829-ba0e-621d11d282a3'
)



ForEach ($d In $Dest) {
    
    
    $Param = @{
        name              = "RDP - Dev to $($d)"
        source            = $Sourceid
        sourcetenant      = "msplh"
        destination       = $d
        destinationTenant = "msplh"
        protocol          = "tcp"
        ports             = "3389"
    }
    New-NetAccess @Param
    
}

ForEach ($r In $LHAsiaRules) {
    
    
    $Param = @{
        name              = $r.Name
        source            = $r.Source
        sourcetenant      = $r.Stenant
        destination       = $r.Dest
        destinationTenant = $r.Dtenant
        protocol          = $r.Protocol
        ports             = $r.Ports
    }
    New-NetAccess @Param
    
}
