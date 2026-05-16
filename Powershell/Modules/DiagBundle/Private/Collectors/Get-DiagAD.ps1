function Get-DiagAD {
    <#
    .SYNOPSIS
        Capture domain join state, time service status, GPO results, and (on domain controllers) dcdiag output.

    .DESCRIPTION
        Reads Win32_ComputerSystem via Get-CimInstance to determine domain membership and DC role (DomainRole 4 or 5). Runs w32tm.exe /query /status and /query /peers and captures their output. When the host is domain-joined, runs gpresult.exe /h and gpresult.exe /x with /scope:computer to produce HTML and XML reports under raw\gpo\. The /scope:computer restriction is intentional: full-scope gpresult enumerates the calling user's group memberships and applied user-side GPOs, which on hosts with token bloat or many user-side GPOs can take 5+ minutes per call (gpresult /h alone measured 350+ seconds during instrumentation). Computer-scope output answers the AD-troubleshooting questions this collector exists for (which DC processed policy, which computer-side GPOs applied, what failed) at a fraction of the cost. When the host is a domain controller, runs dcdiag.exe with /test:Connectivity, /test:Replications, /test:Advertising, /test:Services, and /skip:DNS, captures full output, and extracts a short pass/fail summary. Aggregates everything into summary\ad_context.json.

    .PARAMETER WorkingDirectory
        Root of the staging tree. Artifacts land under summary\ and raw\gpo\ inside this path.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with path/category/type/description and per-type metadata), Errors (array of hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagAD -WorkingDirectory 'C:\ProgramData\DiagBundle\work\bundle-001'

    .NOTES
        Artifacts written:
          summary/ad_context.json
          raw/gpo/gpresult.html            (domain-joined hosts only)
          raw/gpo/gpresult.xml             (domain-joined hosts only)
          raw/gpo/dcdiag.txt               (domain controllers only)

        gpresult.exe requires elevation. When the collector runs as an unelevated user, gpresult.exe writes nothing and the artifact is silently absent -- no Errors entry is added because Test-Path on the missing file is the only signal.

        The collector never throws. On fatal abort it returns Success=$false with populated Errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkingDirectory
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
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $isDc = ([int]$cs.DomainRole -in @(4, 5))

        $w32tmStatus = @()
        try {
            $w32tmStatus = Invoke-DiagTimed -Collector 'Get-DiagAD' -Step 'w32tm /query /status' -Action { & w32tm /query /status 2>&1 }
        } catch { }

        $w32tmPeers = @()
        try {
            $w32tmPeers = Invoke-DiagTimed -Collector 'Get-DiagAD' -Step 'w32tm /query /peers' -Action { & w32tm /query /peers 2>&1 }
        } catch { }

        $rawGpo = Join-Path $WorkingDirectory 'raw\gpo'

        if ($cs.PartOfDomain) {
            # gpresult /h has a hard 127-char limit on the output path. Write
            # to a short path under TEMP and move the file into the bundle.
            $htmlFinal = Join-Path $rawGpo 'gpresult.html'
            $xmlFinal  = Join-Path $rawGpo 'gpresult.xml'
            $shortStem = Join-Path $env:TEMP ("gp_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $shortHtml = "$shortStem.html"
            $shortXml  = "$shortStem.xml"

            try {
                $stderr = Invoke-DiagTimed -Collector 'Get-DiagAD' -Step 'gpresult /h /scope:computer' -Action { & gpresult /h $shortHtml /scope:computer /f 2>&1 }
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $shortHtml)) {
                    Move-Item -LiteralPath $shortHtml -Destination $htmlFinal -Force
                    $result.Artifacts += @{ path = 'raw/gpo/gpresult.html'; category = 'gpresult'; type = 'raw'; description = 'gpresult /h /scope:computer output (user-side policy intentionally excluded for speed)' }
                } else {
                    $result.Errors += @{ collector = 'Get-DiagAD'; artifact = 'raw/gpo/gpresult.html'; reason = "gpresult /h exit ${LASTEXITCODE}: $($stderr -join '; ')"; severity = 'warning' }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagAD'; artifact = 'raw/gpo/gpresult.html'; reason = $_.Exception.Message; severity = 'warning' }
            } finally {
                if (Test-Path -LiteralPath $shortHtml) { Remove-Item -LiteralPath $shortHtml -Force -ErrorAction SilentlyContinue }
            }

            try {
                $stderr = Invoke-DiagTimed -Collector 'Get-DiagAD' -Step 'gpresult /x /scope:computer' -Action { & gpresult /x $shortXml /scope:computer /f 2>&1 }
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $shortXml)) {
                    Move-Item -LiteralPath $shortXml -Destination $xmlFinal -Force
                    $result.Artifacts += @{ path = 'raw/gpo/gpresult.xml'; category = 'gpresult'; type = 'raw'; description = 'gpresult /x /scope:computer output (user-side policy intentionally excluded for speed)' }
                } else {
                    $result.Errors += @{ collector = 'Get-DiagAD'; artifact = 'raw/gpo/gpresult.xml'; reason = "gpresult /x exit ${LASTEXITCODE}: $($stderr -join '; ')"; severity = 'warning' }
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagAD'; artifact = 'raw/gpo/gpresult.xml'; reason = $_.Exception.Message; severity = 'warning' }
            } finally {
                if (Test-Path -LiteralPath $shortXml) { Remove-Item -LiteralPath $shortXml -Force -ErrorAction SilentlyContinue }
            }
        }

        $dcdiagSummary = $null
        if ($isDc) {
            try {
                $dcOut = Invoke-DiagTimed -Collector 'Get-DiagAD' -Step 'dcdiag (Connectivity,Replications,Advertising,Services)' -Action {
                    & dcdiag /test:Connectivity /test:Replications /test:Advertising /test:Services /skip:DNS 2>&1
                }
                $dcPath = Join-Path $WorkingDirectory 'raw\gpo\dcdiag.txt'
                [System.IO.File]::WriteAllText($dcPath, ($dcOut -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
                $result.Artifacts += @{ path = 'raw/gpo/dcdiag.txt'; category = 'dcdiag'; type = 'raw'; description = 'dcdiag selected tests' }
                $dcdiagSummary = ($dcOut | Select-String -Pattern 'passed|failed' -SimpleMatch | Select-Object -First 50 | ForEach-Object { $_.Line.Trim() })
            } catch {
                $result.Errors += @{ collector = 'Get-DiagAD'; artifact = 'raw/gpo/dcdiag.txt'; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        $data = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                part_of_domain = [bool]$cs.PartOfDomain
                domain         = [string]$cs.Domain
                domain_role    = [int]$cs.DomainRole
                is_dc          = $isDc
                w32tm_status   = @($w32tmStatus | ForEach-Object { "$_" })
                w32tm_peers    = @($w32tmPeers  | ForEach-Object { "$_" })
                dcdiag_summary = $dcdiagSummary
            }
        }

        $path = Join-Path $WorkingDirectory 'summary\ad_context.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/ad_context.json'
            category       = 'ad_context'
            schema_version = '1.0'
            type           = 'derived'
            description    = 'Domain join, w32tm, dcdiag summary if DC'
        }
        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagAD'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
