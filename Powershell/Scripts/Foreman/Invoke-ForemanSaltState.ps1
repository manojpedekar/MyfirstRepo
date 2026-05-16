<#
.SYNOPSIS
Automates the submission of Salt states to Foreman via its REST API.

.DESCRIPTION
This script reads a list of server FQDNs from `servers.csv`, batches them into groups
(default size 100), and invokes the Foreman `Salt: state.apply` job template
against each batch. It handles authentication via Basic Auth (username + API token),
trusts all certificates, and logs each invocation result to a timestamped CSV.

.PARAMETER User
The Foreman username to authenticate as (e.g., `DT234496`).

.PARAMETER ApiToken
Either the raw API token string, or a path to a file that contains the token.

.PARAMETER SaltState
The identifier of the Salt state to apply (e.g.,
`ssnc-windows.ssnc-winops_server_inventory`).

.PARAMETER SaltEnv
The Salt environment to target (e.g., `sandbox`, `prod`).

.PARAMETER Description
A custom description for each Foreman job invocation. Defaults to `"Foreman batch job"`.

.PARAMETER ConcurrencyLevel
(Optional) Maximum number of hosts to run in parallel. Maps to the “Concurrency level” field
in the Foreman UI.

.PARAMETER WhatIf
If specified, performs a dry run: prints what would be submitted without calling the API.

.EXAMPLE
.\foreman_run_Salt_State--WORKING.ps1 `
  -User DT234496 `
  -ApiToken "C:\Admin\Foreman\API_TOKEN\Mark.txt" `
  -SaltState ssnc-windows.ssnc-winops_server_inventory `
  -SaltEnv sandbox `
  -ConcurrencyLevel 10
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$User,

    [Parameter(Mandatory = $true)]
    [string]$ApiToken,

    [string]$SaltState,
    [string]$SaltEnv,
    [string]$Description     = "Foreman batch job",

    [int]$ConcurrencyLevel,

    [switch]$WhatIf
)

# if ApiToken is a file, read it
if (Test-Path $ApiToken) {
    $ApiToken = (Get-Content $ApiToken -Raw).Trim()
}

$ForemanUrl      = "https://foreman.ssnc-corp.cloud"
$ServerListCsv   = ".\servers.csv"
$JobTemplateName = "Salt: state.apply"
$BatchSize       = 100
$timestamp       = Get-Date -Format "yyyyMMdd-HHmmss"
$LogPath         = ".\foreman_batch_job_log_$timestamp.csv"

"BatchNumber,SearchQuery,Submitted,JobID,Error" | Out-File $LogPath

# Trust all certs…
if (-not ("TrustAllCertsPolicy" -as [type])) {
    Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
    }
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Build headers
$Base64Auth = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes("$User`:$ApiToken")
)
$Headers = @{
    Authorization  = "Basic $Base64Auth"
    Accept         = "application/json"
    "Content-Type" = "application/json"
}

# Lookup job template
Write-Output "Looking up Job Template ID for '$JobTemplateName'..."
$jtUrl = "$ForemanUrl/api/job_templates?search=name=`"$JobTemplateName`""
$jid   = (Invoke-RestMethod $jtUrl -Headers $Headers -Method Get).results[0].id
if (-not $jid) { Write-Error "Job Template not found."; exit 1 }
Write-Output "Found Job Template ID: $jid"

# Prepare batching
$servers     = Import-Csv $ServerListCsv | Select-Object -Expand Name
$batch       = @()
$batchIndex  = 0
$batchNumber = 1

foreach ($fqdnRaw in $servers) {
    $fqdn = $fqdnRaw.Trim()
    if ($fqdn) {
        $batch       += $fqdn
        $batchIndex++
    }

    if ($batchIndex -ge $BatchSize) {
        $names = $batch | ForEach-Object { "name=`"$_`"" }
        $query = $names -join " OR "

        Write-Output "`n--- Submitting Batch ${batchNumber} ---"
        Write-Output "Search Query: $query"

        if ($WhatIf) {
            Write-Output "WHATIF: Would have submitted batch ${batchNumber}: $($batch -join ', ')"
            "${batchNumber},`"$query`",NO,N/A,WHATIF" | Out-File -Append $LogPath
        }
        else {
            try {
                $inputs = @{
                    state                   = $SaltState
                    saltenv                 = $SaltEnv
                    "Test Mode (test=true)" = "False"
                    Description             = $Description
                    "pillar overrides"      = ""
                    loglevel                = "warning"
                }

                # THIS LINE ADDS YOUR THROTTLE SETTING
                $jobInvocation = @{
                    job_template_id     = $jid
                    inputs              = $inputs
                    search_query        = $query
                    targeting_type      = "static_query"
                    concurrency_control = @{
                        concurrency_level = $ConcurrencyLevel
                    }
                }

                $body = @{ job_invocation = $jobInvocation } | ConvertTo-Json -Depth 10

                $resp = Invoke-RestMethod "$ForemanUrl/api/job_invocations" `
                    -Headers $Headers -Body $body -Method Post

                Write-Output "Batch ${batchNumber} submitted as job ID: $($resp.id)"
                "${batchNumber},`"$query`",YES,${resp.id}," | Out-File -Append $LogPath
            }
            catch {
                $err = $_.Exception.Message
                Write-Error "Failed Batch ${batchNumber}: $err"
                "${batchNumber},`"$query`",NO,N/A,${err}" | Out-File -Append $LogPath
            }
        }

        # reset for next batch
        $batch       = @()
        $batchIndex  = 0
        $batchNumber++
    }
}

# FINAL BATCH
if ($batch.Count) {
    $names = $batch | ForEach-Object { "name=`"$_`"" }
    $query = $names -join " OR "

    Write-Output "`n--- Submitting Final Batch ${batchNumber} ---"
    Write-Output "Search Query: $query"

    if ($WhatIf) {
        Write-Output "WHATIF: Would have submitted final batch ${batchNumber}: $($batch -join ', ')"
        "${batchNumber},`"$query`",NO,N/A,WHATIF" | Out-File -Append $LogPath
    }
    else {
        try {
            $inputs = @{
                state                   = $SaltState
                saltenv                 = $SaltEnv
                "Test Mode (test=true)" = "False"
                Description             = $Description
                "pillar overrides"      = ""
                loglevel                = "warning"
            }

            # INSERT THROTTLING HERE AS WELL
            $jobInvocation = @{
                job_template_id     = $jid
                inputs              = $inputs
                search_query        = $query
                targeting_type      = "static_query"
                concurrency_control = @{
                    concurrency_level = $ConcurrencyLevel
                }
            }

            $body = @{ job_invocation = $jobInvocation } | ConvertTo-Json -Depth 10

            $resp = Invoke-RestMethod "$ForemanUrl/api/job_invocations" `
                -Headers $Headers -Body $body -Method Post

            Write-Output "Batch ${batchNumber} submitted as job ID: $($resp.id)"
            "${batchNumber},`"$query`",YES,${resp.id}," | Out-File -Append $LogPath
        }
        catch {
            $err = $_.Exception.Message
            Write-Error "Failed Final Batch ${batchNumber}: $err"
            "${batchNumber},`"$query`",NO,N/A,${err}" | Out-File -Append $LogPath
        }
    }
}

Write-Output "`nAll batches processed. Log saved to: $LogPath"
