#requires -Version 5.1
<#
.SYNOPSIS
    Read-only discovery of valid domainDelegation values for a subproject/site.

.DESCRIPTION
    The API validates 'domainDelegation' against a server-side list but the module
    has no cmdlet to enumerate it. This script gathers the accepted values three ways:
      1. Dumps the target subproject object (may include an allowed-delegations list).
      2. Reads an existing instance's actual 'domainDelegation' (a known-good value).
      3. Best-effort GET against likely delegation endpoints.

    All calls are GET (read-only). Nothing is created or modified.

.EXAMPLE
    PS> Import-Module .\Cloud-API.psm1 -Force
    PS> .\Debug-CloudDelegations.ps1
#>
[CmdletBinding()]
param(
    [string]$SubprojectId    = "subproject-43be98b7-6eed-4dbe-a056-fbbfca1e4b49",
    # An existing London instance to read a known-good delegation from (POC_LONFileServer1):
    [string]$SampleInstanceId = "i-b99fe78c-b36b-4844-85bb-17278b4b05b0"
)

$module = Get-Module Cloud-API
if (-not $module) {
    Write-Error "Cloud-API module is not imported. Run: Import-Module .\Cloud-API.psm1 -Force"
    return
}

Write-Host "`n=== 1. SUBPROJECT OBJECT (looking for allowed delegations) ===" -ForegroundColor Cyan
$sp = Get-CloudSubproject -Id $SubprojectId
$sp | ConvertTo-Json -Depth 10

Write-Host "`n=== 2. EXISTING INSTANCE (known-good domainDelegation) ===" -ForegroundColor Cyan
$inst = Get-CloudInstance -Id $SampleInstanceId
if ($inst) {
    [PSCustomObject]@{
        name             = $inst.name
        site             = $inst.site
        domainDelegation = $inst.domainDelegation
    } | Format-List
}

Write-Host "`n=== 3. PROBING LIKELY DELEGATION ENDPOINTS (best-effort) ===" -ForegroundColor Cyan
& $module {
    param($spId)

    $headers   = New-CloudAPIHeaders -IncludeAccept
    $baseUri    = $script:ModuleConfig.BaseUri
    $apiVersion = $script:ModuleConfig.ApiVersion

    $candidates = @(
        "management/domaindelegations",
        "management/domaindelegations?subprojectId=$spId",
        "network/domaindelegations",
        "management/domains"
    )

    foreach ($path in $candidates) {
        $uri = "$baseUri/api/$apiVersion/$path"
        Write-Host "`n--- GET $path ---" -ForegroundColor DarkCyan
        try {
            $r = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ContentType 'application/json' -ErrorAction Stop
            $r | ConvertTo-Json -Depth 6
        }
        catch {
            $code = $null
            if ($_.Exception.Response) {
                try { $code = [int]$_.Exception.Response.StatusCode } catch { }
            }
            Write-Host "  (no data - HTTP $code)" -ForegroundColor DarkGray
        }
    }
} $SubprojectId
