function Get-DiagRoleIIS {
    <#
    .SYNOPSIS
        Collect IIS configuration, site and app pool inventory, and recent W3SVC logs.

    .DESCRIPTION
        Detect IIS by checking for the WebAdministration module OR the W3SVC service.
        When detected, copy applicationHost.config verbatim, project Get-Website and
        Get-WebAppPool output to JSON, and copy W3SVC log files modified within the
        time window. Log copy is newest-first with a 50 MB total cap; oldest files
        drop when the cap is reached. Each artifact failure adds an entry to Errors
        but does not abort the collector.

    .PARAMETER WorkingDirectory
        Absolute path to the bundle staging directory. Artifacts write under
        raw\role_specific\iis and raw\role_specific\iis_w3svc_lastday beneath it.

    .PARAMETER WindowHours
        Lookback window in hours for W3SVC log file LastWriteTime. Default 24.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        $r = Get-DiagRoleIIS -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle1' -WindowHours 24

    .NOTES
        Detection signal: WebAdministration module presence OR W3SVC service presence.
        When neither is present, return Success=$true with empty Artifacts. This is
        "not applicable", not failure.

        Artifacts written under raw/role_specific/:
          - raw/role_specific/iis/applicationHost.config
          - raw/role_specific/iis/sites.json
          - raw/role_specific/iis/apppools.json
          - raw/role_specific/iis_w3svc_lastday/<W3SVC*>/<logfile>  (per site, last
            WindowHours, newest-first, 50 MB total cap across all sites)

        Get-DiagRoles is the dispatcher and is responsible for calling this only when
        the role is detected; this collector also self-checks defensively and returns
        a no-op result when IIS is absent.

        The collector never throws. Per-artifact failures append to Errors with
        severity 'warning'. On fatal abort it returns Success=$false with populated
        Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter()]
        [int] $WindowHours = 24
    )

    $started = Get-Date
    $result = [pscustomobject]@{
        Success         = $false
        Artifacts       = @()
        Errors          = @()
        DurationSeconds = 0
    }
    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    try {
        $hasModule  = [bool](Get-Module -ListAvailable -Name WebAdministration -ErrorAction SilentlyContinue)
        $hasService = [bool](Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue)
        if (-not $hasModule -and -not $hasService) {
            $result.Success = $true
            return $result
        }

        $rawIis    = Join-Path $WorkingDirectory 'raw\role_specific\iis'
        $rawW3svc  = Join-Path $WorkingDirectory 'raw\role_specific\iis_w3svc_lastday'
        if (-not (Test-Path $rawIis))   { New-Item -ItemType Directory -Path $rawIis   -Force | Out-Null }
        if (-not (Test-Path $rawW3svc)) { New-Item -ItemType Directory -Path $rawW3svc -Force | Out-Null }

        $appHostSrc = Join-Path $env:windir 'System32\inetsrv\config\applicationHost.config'
        try {
            if (Test-Path $appHostSrc) {
                $appHostDst = Join-Path $rawIis 'applicationHost.config'
                Copy-Item -Path $appHostSrc -Destination $appHostDst -Force -ErrorAction Stop
                $result.Artifacts += @{
                    path        = 'raw/role_specific/iis/applicationHost.config'
                    category    = 'iis_config'
                    type        = 'raw'
                    description = 'IIS applicationHost.config'
                }
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleIIS'; artifact = 'raw/role_specific/iis/applicationHost.config'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $moduleLoaded = $false
        if ($hasModule) {
            try {
                Import-Module WebAdministration -ErrorAction Stop
                $moduleLoaded = $true
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleIIS'; reason = "Import-Module WebAdministration failed: $($_.Exception.Message)"; severity = 'warning' }
            }
        }

        if ($moduleLoaded) {
            try {
                $sites = @(Get-Website -ErrorAction Stop | ForEach-Object {
                    $bindingStrings = @()
                    try {
                        $bindingStrings = @($_.bindings.Collection | ForEach-Object { "$($_.protocol) $($_.bindingInformation)" })
                    } catch { }
                    [ordered]@{
                        name             = "$($_.name)"
                        id               = [int]$_.id
                        state            = "$($_.state)"
                        physical_path    = "$($_.physicalPath)"
                        application_pool = "$($_.applicationPool)"
                        bindings         = $bindingStrings
                    }
                })

                $sitesData = [ordered]@{
                    schema_version = '1.0'
                    host           = @{ computer_name = $env:COMPUTERNAME }
                    collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                    data           = [ordered]@{
                        site_count = $sites.Count
                        sites      = $sites
                    }
                }
                $sitesPath = Join-Path $rawIis 'sites.json'
                $json = $sitesData | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($sitesPath, $json, [System.Text.UTF8Encoding]::new($false))
                $result.Artifacts += @{
                    path           = 'raw/role_specific/iis/sites.json'
                    category       = 'iis_sites'
                    schema_version = '1.0'
                    type           = 'derived'
                    description    = 'IIS websites with bindings, state, physical path, app pool'
                    row_count      = $sites.Count
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleIIS'; artifact = 'raw/role_specific/iis/sites.json'; reason = $_.Exception.Message; severity = 'warning' }
            }

            try {
                $pools = @(Get-WebAppPool -ErrorAction Stop | ForEach-Object {
                    $identityType = $null
                    $restartTime  = $null
                    try { $identityType = "$($_.processModel.identityType)" } catch { }
                    try { $restartTime  = "$($_.recycling.periodicRestart.time)" } catch { }
                    [ordered]@{
                        name                    = "$($_.name)"
                        state                   = "$($_.state)"
                        managed_runtime_version = "$($_.managedRuntimeVersion)"
                        identity_type           = $identityType
                        periodic_restart_time   = $restartTime
                    }
                })

                $poolsData = [ordered]@{
                    schema_version = '1.0'
                    host           = @{ computer_name = $env:COMPUTERNAME }
                    collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
                    data           = [ordered]@{
                        pool_count = $pools.Count
                        app_pools  = $pools
                    }
                }
                $poolsPath = Join-Path $rawIis 'apppools.json'
                $json = $poolsData | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($poolsPath, $json, [System.Text.UTF8Encoding]::new($false))
                $result.Artifacts += @{
                    path           = 'raw/role_specific/iis/apppools.json'
                    category       = 'iis_apppools'
                    schema_version = '1.0'
                    type           = 'derived'
                    description    = 'IIS application pools with identity, runtime, recycling'
                    row_count      = $pools.Count
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagRoleIIS'; artifact = 'raw/role_specific/iis/apppools.json'; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        try {
            $logRoot = 'C:\inetpub\logs\LogFiles'
            if (Test-Path $logRoot) {
                $cutoff   = (Get-Date).AddHours(-1 * $WindowHours)
                $maxBytes = 50MB
                $candidates = @(Get-ChildItem -Path $logRoot -Directory -Filter 'W3SVC*' -ErrorAction SilentlyContinue | ForEach-Object {
                    $siteDir = $_
                    Get-ChildItem -Path $siteDir.FullName -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -ge $cutoff } |
                        ForEach-Object {
                            [pscustomobject]@{
                                SiteDir = $siteDir.Name
                                File    = $_
                            }
                        }
                })
                # Newest-first so oldest are dropped when the size cap is reached.
                $ordered = @($candidates | Sort-Object { $_.File.LastWriteTime } -Descending)
                $running = [int64]0
                foreach ($c in $ordered) {
                    $size = [int64]$c.File.Length
                    if (($running + $size) -gt $maxBytes) { continue }
                    $destDir = Join-Path $rawW3svc $c.SiteDir
                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    $destFile = Join-Path $destDir $c.File.Name
                    try {
                        Copy-Item -Path $c.File.FullName -Destination $destFile -Force -ErrorAction Stop
                        $running += $size
                        $result.Artifacts += @{
                            path        = "raw/role_specific/iis_w3svc_lastday/$($c.SiteDir)/$($c.File.Name)"
                            category    = 'iis_w3svc_log'
                            type        = 'raw'
                            description = "W3SVC log file modified within last $WindowHours h"
                        }
                    } catch {
                        $result.Errors += @{ collector = 'Get-DiagRoleIIS'; artifact = "raw/role_specific/iis_w3svc_lastday/$($c.SiteDir)/$($c.File.Name)"; reason = $_.Exception.Message; severity = 'warning' }
                    }
                }
            }
        } catch {
            $result.Errors += @{ collector = 'Get-DiagRoleIIS'; artifact = 'raw/role_specific/iis_w3svc_lastday/*'; reason = $_.Exception.Message; severity = 'warning' }
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagRoleIIS'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
