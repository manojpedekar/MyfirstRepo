#requires -Version 5.1
<#
.SYNOPSIS
    One-off diagnostic: reproduces the New-CloudInstance_v2 POST and prints the
    RAW API response body for the 400 that the module currently swallows.

.DESCRIPTION
    Runs inside the Cloud-API module scope so the private New-CloudAPIHeaders
    function resolves. Rebuilds the exact request body New-CloudInstance_v2 sends,
    prints it, then captures and prints the raw HTTP error body (which names the
    offending field).

    This is a temporary troubleshooting script, not part of the module.

.EXAMPLE
    PS> Import-Module .\Cloud-API.psm1
    PS> .\Debug-CloudInstance400.ps1
#>
[CmdletBinding()]
param(
    [string]$SubprojectId     = "subproject-43be98b7-6eed-4dbe-a056-fbbfca1e4b49",
    [string]$Name             = "ifdsuknetappdisconvery",
    [int]   $Cpu              = 4,
    [int]   $Memory           = 12,
    [string[]]$SecurityGroupIds = @("tier-f40267c6-2263-46e2-935f-14c757d92cb9"),
    [string]$Site             = "uk-east-lon",
    [string]$ImageId          = "ssnc-cloud-w2k25-base",
    [string]$DomainDelegation = "ifdsgroup.co.uk"
)

$module = Get-Module Cloud-API
if (-not $module) {
    Write-Error "Cloud-API module is not imported. Run: Import-Module .\Cloud-API.psm1"
    return
}

$spec = [PSCustomObject]@{
    SubprojectId     = $SubprojectId
    Name             = $Name
    Cpu              = $Cpu
    Memory           = $Memory
    SecurityGroupIds = $SecurityGroupIds
    Site             = $Site
    ImageId          = $ImageId
    DomainDelegation = $DomainDelegation
}

& $module {
    param($p)

    $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

    $body = @{
        subprojectId     = $p.SubprojectId
        name             = $p.Name
        domainDelegation = $p.DomainDelegation
        cpu              = $p.Cpu
        memory           = $p.Memory
        imageId          = $p.ImageId
        securityGroupIds = @($p.SecurityGroupIds)
        site             = $p.Site
    }
    $json = $body | ConvertTo-Json -Depth 10

    Write-Host ""
    Write-Host "--- REQUEST BODY ---" -ForegroundColor Cyan
    Write-Host $json

    $uri = "$($script:ModuleConfig.BaseUri)/api/$($script:ModuleConfig.ApiVersion)/compute/instances"

    try {
        $result = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $json -ContentType 'application/json' -ErrorAction Stop
        Write-Host ""
        Write-Host "--- SUCCESS (no 400) ---" -ForegroundColor Green
        $result | ConvertTo-Json -Depth 10 | Write-Host
    }
    catch {
        Write-Host ""
        Write-Host "--- RAW ERROR RESPONSE BODY ---" -ForegroundColor Yellow

        $bodyText = $null

        # PowerShell 7 (and 5.1 in most cases) exposes the raw response body here.
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $bodyText = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            $resp = $_.Exception.Response
            if ($resp -is [System.Net.Http.HttpResponseMessage]) {
                # PowerShell 7 / HttpClient
                $bodyText = $resp.Content.ReadAsStringAsync().Result
            }
            elseif ($resp.PSObject.Methods.Name -contains 'GetResponseStream') {
                # Windows PowerShell 5.1 / WebRequest
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $sr.BaseStream.Position = 0
                $sr.DiscardBufferedData()
                $bodyText = $sr.ReadToEnd()
            }
        }

        if (-not $bodyText) { $bodyText = $_.Exception.Message }
        Write-Host $bodyText
    }
} $spec
