
Function Export-RemoteEvtx {
    <#
    .SYNOPSIS
    Export Application, System, and Security EVTX logs from remote Windows hosts.

    .DESCRIPTION
    Creates a PowerShell Remoting session to each target, runs `wevtutil epl`
    to export the specified logs to a temp folder on the remote system, then
    copies the .evtx files back to a local destination with names like:
      20250922-093015_HOSTNAME_System.evtx

    .PARAMETER ComputerName
    One or more remote computer names (DNS/FQDN/NetBIOS).

    .PARAMETER Credential
    Optional PSCredential used for the remote session.

    .PARAMETER DestinationPath
    Local directory to store the exported .evtx files. Created if missing.

    .PARAMETER Logs
    Which logs to export. Defaults to Application, System, Security.

    .PARAMETER Overwrite
    If specified, overwrite existing local files with the same name.

    .EXAMPLE
    Export-RemoteEvtx -ComputerName PC01 -DestinationPath C:\Temp\Evtx

    .EXAMPLE
    $creds = Get-Credential
    Export-RemoteEvtx -ComputerName PC01,PC02 -Credential $creds -DestinationPath .\Logs

    .NOTES
    - Requires remote admin and access to read the Security log.
    - Uses wevtutil epl on the remote host to produce proper .evtx.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'Name')]
        [string[]]$ComputerName,
        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath = ".\EvtxExports",
        [Parameter()]
        [ValidateSet('Application', 'System', 'Security')]
        [string[]]$Logs = @('Application', 'System', 'Security'),
        [switch]$Overwrite
    )
    
    Begin {
        # Ensure local destination exists
        If (-not (Test-Path -LiteralPath $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
        
        # Helper to make safe filenames
        Function _Sanitize([string]$name) {
            $bad = [IO.Path]::GetInvalidFileNameChars()
            ForEach ($c In $bad) { $name = $name -replace [Regex]::Escape($c), '_' }
            $name
        }
        
        $results = New-Object System.Collections.Generic.List[object]
    }
    
    Process {
        ForEach ($comp In $ComputerName) {
            $target = $comp.Trim()
            If (-not $target) { Continue }
            
            $ts = Get-Date
            $tsStamp = $ts.ToString('yyyyMMdd-HHmmss')
            $safeComputer = _Sanitize $target
            
            Write-Verbose "[$target] Starting export at $tsStamp"
            
            $sessionParams = @{
                ComputerName = $target
                ErrorAction  = 'Stop'
            }
            If ($Credential) { $sessionParams.Credential = $Credential }
            
            Try {
                If ($PSCmdlet.ShouldProcess($target, "Create PSSession")) {
                    $sess = New-PSSession @sessionParams
                }
                
                # Remote prep: create a unique temp folder
                $remote = Invoke-Command -Session $sess -ScriptBlock {
                    $root = Join-Path $env:TEMP "EvtxExport"
                    If (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root | Out-Null }
                    $guid = [guid]::NewGuid().ToString()
                    $dir = Join-Path $root $guid
                    New-Item -ItemType Directory -Path $dir | Out-Null
                    # Return both the dir and computername resolved on remote
                    [pscustomobject]@{
                        TempDir      = $dir
                        ComputerName = $env:COMPUTERNAME
                    }
                }
                
                $remoteTemp = $remote.TempDir
                $remoteComputerResolved = $remote.ComputerName
                
                # Export each requested log on the remote host
                $exportedRemoteFiles = Invoke-Command -Session $sess -ArgumentList @($Logs, $tsStamp) -ScriptBlock {
                    Param ($logs,
                        $stamp)
                    $out = @()
                    ForEach ($log In $logs) {
                        $file = Join-Path $using:remoteTemp ("{0}-{1}.evtx" -f $log, $stamp)
                        # /ow:true allows overwriting in the remote temp folder if re-run
                        $cmd = "wevtutil epl `"${log}`" `"${file}`" /ow:true"
                        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmd" -Wait -PassThru -WindowStyle Hidden
                        If ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne $null) {
                            Throw "wevtutil failed for log '$log' with exit code $($proc.ExitCode)."
                        }
                        $out += $file
                    }
                    $out
                }
                
                # Copy each exported file back locally with our naming convention
                ForEach ($remoteFile In $exportedRemoteFiles) {
                    $logBase = Split-Path $remoteFile -Leaf # e.g., "System-20250922-093015.evtx"
                    # Our final local name: 20250922-093015_PC01_System.evtx
                    $logName = $logBase.Split('-')[0] # "System"
                    $localName = "{0}_{1}_{2}.evtx" -f $tsStamp, $safeComputer, $logName
                    $localPath = Join-Path $DestinationPath $localName
                    
                    If ((-not $Overwrite) -and (Test-Path -LiteralPath $localPath)) {
                        Throw "Local file already exists: $localPath (use -Overwrite to replace)"
                    }
                    
                    If ($PSCmdlet.ShouldProcess("$remoteComputerResolved : $remoteFile", "Copy to $localPath")) {
                        Copy-Item -FromSession $sess -Path $remoteFile -Destination $localPath -Force
                    }
                    
                    $results.Add([pscustomobject]@{
                            ComputerName   = $target
                            RemoteComputer = $remoteComputerResolved
                            Log            = $logName
                            LocalPath      = (Resolve-Path -LiteralPath $localPath).Path
                            Timestamp      = $ts
                            Success        = $true
                        })
                }
                
                # Cleanup the remote temp folder (best effort)
                Invoke-Command -Session $sess -ScriptBlock {
                    Try { Remove-Item -LiteralPath $using:remoteTemp -Recurse -Force -ErrorAction Stop } Catch { }
                } | Out-Null
            } Catch {
                $err = $_
                Write-Warning "[$target] Export failed: $($err.Exception.Message)"
                $results.Add([pscustomobject]@{
                        ComputerName   = $target
                        RemoteComputer = $null
                        Log            = $null
                        LocalPath      = $null
                        Timestamp      = $ts
                        Success        = $false
                        Error          = $err.Exception.Message
                    })
            } Finally {
                If ($sess) {
                    Try { Remove-PSSession -Session $sess -ErrorAction SilentlyContinue } Catch { }
                }
            }
        }
    }
    
    End {
        $results
    }
}

Function Get-EvtxBootSummary {
<#
.SYNOPSIS
Parse local EVTX files to list reboot/startup/shutdown events and common startup/shutdown issues.

.DESCRIPTION
Reads System/Security .evtx files from a folder and returns a unified timeline of:
- Boot/Startup: 6005, 6009, 6013, Kernel-General(12), Security(4608)
- Clean/Planned shutdown: 6006, Kernel-General(13), USER32(1074), Kernel-Power(109), Security(4609)
- Unexpected/Crash: 6008, Kernel-Power(41), BugCheck(1001)
- (Optional) Service startup/shutdown issues: SCM 7000, 7001, 7009, 7031, 7034

Uses Get-WinEvent -Path with -FilterXPath (since -FilterHashtable can't be used with -Path).

.PARAMETER Path
Root folder containing .evtx files.

.PARAMETER Recurse
Search subfolders for .evtx.

.PARAMETER StartTime
Only include events on/after this time (filtered after read).

.PARAMETER EndTime
Only include events before this time (filtered after read).

.PARAMETER IncludeServiceFailures
Include Service Control Manager failures/timeouts.

.PARAMETER NoMessage
Skip the .Message property (faster, smaller output).

.PARAMETER CsvPath
If provided, export results to CSV at this path.

.EXAMPLE
Get-EvtxBootSummary -Path .\EvtxExports -Recurse -IncludeServiceFailures -CsvPath .\temp\boot_shutdown_issues.csv
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$Path,
        [switch]$Recurse,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [switch]$IncludeServiceFailures,
        [switch]$NoMessage,
        [string]$CsvPath
    )
    
    # Event ID sets
    $idsBoot = 6005, 6009, 6013, 12, 4608
    $idsShutdown = 6006, 13, 1074, 109, 4609
    $idsUnexpected = 6008, 41, 1001
    $idsServices = 7000, 7001, 7009, 7031, 7034
    
    $allIds = @($idsBoot + $idsShutdown + $idsUnexpected) | Select-Object -Unique
    If ($IncludeServiceFailures) { $allIds += $idsServices }
    $allIds = $allIds | Select-Object -Unique
    
    # Helpers
    Function _Classify([int]$Id) {
        Switch ($Id) {
            { $_ -in 6005, 6009, 6013, 12, 4608 } { 'Boot/Startup'; Break }
            { $_ -in 6006, 13, 1074, 109, 4609 }  { 'Shutdown/Planned'; Break }
            { $_ -in 6008, 41, 1001 }           { 'Unexpected/Crash'; Break }
            default {
                If ($Id -in 7000, 7001, 7009, 7031, 7034) { 'ServiceStartupIssue' } Else { 'Other' }
            }
        }
    }
    
    Function _InferLogFromFile([string]$File) {
        $name = [IO.Path]::GetFileNameWithoutExtension($File)
        $parts = $name -split '_'
        If ($parts.Count -ge 3) { $parts[-1] } Else { $null }
    }
    
    Function _InferComputerFromFile([string]$File) {
        $name = [IO.Path]::GetFileNameWithoutExtension($File)
        $parts = $name -split '_'
        If ($parts.Count -ge 3) { $parts[-2] } Else { $null }
    }
    
    Function _BuildXPathForIds([int[]]$Ids) {
        # Example: *[System[(EventID=6005 or EventID=6006 or EventID=41)]]
        $idExpr = ($Ids | ForEach-Object { "EventID=$_" }) -join ' or '
        "*[System[($idExpr)]]"
    }
    
    # File list (keep System/Security; others pass through but will be filtered by IDs)
    $files = Get-ChildItem -LiteralPath $Path -Filter *.evtx -File -ErrorAction Stop -Recurse:$Recurse
    $candidateFiles = ForEach ($f In $files) {
        $hint = _InferLogFromFile $f.FullName
        If ($hint) {
            If ($hint -in @('System', 'Security')) { $f }
        } Else { $f }
    }
    
    If (-not $candidateFiles) {
        Write-Warning "No EVTX files found (or none matched System/Security)."
        Return
    }
    
    $xPath = _BuildXPathForIds $allIds
    $out = New-Object System.Collections.Generic.List[object]
    
    ForEach ($file In $candidateFiles) {
        Try {
            # Use -FilterXPath with -Path (supported); time filtering applied afterwards
            $events = Get-WinEvent -Path $file.FullName -FilterXPath $xPath -ErrorAction Stop
        } Catch {
            Write-Warning "Failed to read '$($file.FullName)': $($_.Exception.Message)"
            Continue
        }
        
        If ($StartTime) { $events = $events | Where-Object { $_.TimeCreated -ge $StartTime } }
        If ($EndTime) { $events = $events | Where-Object { $_.TimeCreated -lt $EndTime } }
        
        ForEach ($ev In $events) {
            $machine = If ($ev.MachineName) { $ev.MachineName } Else { _InferComputerFromFile $file.FullName }
            $logName = If ($ev.LogName) { $ev.LogName } Else { _InferLogFromFile $file.FullName }
            $type = _Classify -Id $ev.Id
            
            $out.Add([pscustomobject]@{
                    Computer      = $machine
                    SourceFile    = $file.FullName
                    LogName       = $logName
                    Provider      = $ev.ProviderName
                    Id            = $ev.Id
                    Level         = $ev.LevelDisplayName
                    Type          = $type
                    TimeCreated   = $ev.TimeCreated
                    EventRecordId = $ev.RecordId
                    Message       = $(If ($NoMessage) { $null } Else { $ev.Message })
                }) | Out-Null
        }
    }
    
    $results = $out | Sort-Object TimeCreated, Computer
    
    If ($CsvPath) {
        $dir = Split-Path -Path $CsvPath -Parent
        If ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath
    }
    
    $results
}

#  Get-EvtxBootSummary -Path .\EvtxExports -IncludeServiceFailures -CsvPath .\temp\boot_shutdown_issues.csv -StartTime (Get-Date).AddHours(-240)

Function Export-RemoteCitrixLogs {
    <#
    .SYNOPSIS
    Export Citrix VDA logs and events from remote Windows hosts for troubleshooting.

    .DESCRIPTION
    Creates a PowerShell Remoting session to each target and collects:
    - Citrix event logs (Citrix-VirtualDesktopAgent, Citrix-ICA, etc.)
    - Configuration files from Citrix install directories
    - Optional: WEM Agent logs, Profile Management logs
    
    Exports .evtx files and copies configuration/log files to a local destination
    with timestamped names like: 20250922-093015_HOSTNAME_CitrixVDA.evtx

    .PARAMETER ComputerName
    One or more remote computer names (DNS/FQDN/NetBIOS).

    .PARAMETER Credential
    Optional PSCredential used for the remote session.

    .PARAMETER DestinationPath
    Local directory to store the exported logs. Created if missing.

    .PARAMETER IncludeConfigFiles
    If specified, also copy Citrix configuration files (ICA config, etc.).

    .PARAMETER IncludeWEM
    If specified, include Workspace Environment Management (WEM) agent logs.

    .PARAMETER IncludeProfileManagement
    If specified, include Citrix Profile Management logs.

    .PARAMETER DaysBack
    Number of days of logs to collect. Defaults to 7 days.

    .PARAMETER Overwrite
    If specified, overwrite existing local files with the same name.

    .EXAMPLE
    Export-RemoteCitrixLogs -ComputerName VDA01 -DestinationPath C:\Temp\CitrixLogs

    .EXAMPLE
    $creds = Get-Credential
    Export-RemoteCitrixLogs -ComputerName VDA01,VDA02 -Credential $creds `
        -DestinationPath .\CitrixLogs -IncludeConfigFiles -IncludeWEM -DaysBack 14

    .NOTES
    - Requires remote admin access
    - Citrix VDA must be installed on target systems
    - Some logs may require elevated permissions
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('CN', 'Name')]
        [string[]]$ComputerName,
        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath = ".\CitrixLogs",
        [switch]$IncludeConfigFiles,
        [switch]$IncludeWEM,
        [switch]$IncludeProfileManagement,
        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$DaysBack = 7,
        [switch]$Overwrite
    )
    
    Begin {
        # Ensure local destination exists
        If (-not (Test-Path -LiteralPath $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
        
        # Helper to make safe filenames
        Function _Sanitize([string]$name) {
            $bad = [IO.Path]::GetInvalidFileNameChars()
            ForEach ($c In $bad) { $name = $name -replace [Regex]::Escape($c), '_' }
            $name
        }
        
        $results = New-Object System.Collections.Generic.List[object]
        
        # Define Citrix event log names to collect
        $citrixEventLogs = @(
            'Citrix-VirtualDesktopAgent-Admin'
            'Citrix-VirtualDesktopAgent-Operational'
            'Citrix-Desktop-Service-Admin'
            'Citrix-Desktop-Service-Operational'
            'Citrix-GroupPolicy-Admin'
            'Citrix-GroupPolicy-Operational'
            'Citrix-ICA-Admin'
            'Citrix-ICA-Operational'
            'Citrix-PortICA-Admin'
            'Citrix-PortICA-Operational'
            'Citrix-SessionSharing-Admin'
            'Citrix-SessionSharing-Operational'
            'Citrix-HDX-Admin'
            'Citrix-HDX-Operational'
        )
    }
    
    Process {
        ForEach ($comp In $ComputerName) {
            $target = $comp.Trim()
            If (-not $target) { Continue }
            
            $ts = Get-Date
            $tsStamp = $ts.ToString('yyyyMMdd-HHmmss')
            $safeComputer = _Sanitize $target
            
            Write-Verbose "[$target] Starting Citrix log export at $tsStamp"
            
            $sessionParams = @{
                ComputerName = $target
                ErrorAction  = 'Stop'
            }
            If ($Credential) { $sessionParams.Credential = $Credential }
            
            Try {
                If ($PSCmdlet.ShouldProcess($target, "Create PSSession")) {
                    $sess = New-PSSession @sessionParams
                }
                
                # Remote prep: create a unique temp folder
                $remote = Invoke-Command -Session $sess -ScriptBlock {
                    $root = Join-Path $env:TEMP "CitrixLogExport"
                    If (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root | Out-Null }
                    $guid = [guid]::NewGuid().ToString()
                    $dir = Join-Path $root $guid
                    New-Item -ItemType Directory -Path $dir | Out-Null
                    
                    # Detect Citrix installation paths
                    $vdaPath = $null
                    $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
                    ForEach ($pf In $programFiles) {
                        $testPath = Join-Path $pf "Citrix\Virtual Desktop Agent"
                        If (Test-Path $testPath) {
                            $vdaPath = $testPath
                            Break
                        }
                    }
                    
                    [pscustomobject]@{
                        TempDir      = $dir
                        ComputerName = $env:COMPUTERNAME
                        VDAPath      = $vdaPath
                    }
                }
                
                $remoteTemp = $remote.TempDir
                $remoteComputerResolved = $remote.ComputerName
                $remoteVDAPath = $remote.VDAPath
                
                If (-not $remoteVDAPath) {
                    Write-Warning "[$target] Citrix VDA not detected. Attempting log export anyway..."
                }
                
                # Export Citrix event logs
                $exportedFiles = Invoke-Command -Session $sess -ArgumentList @($citrixEventLogs, $tsStamp, $DaysBack) -ScriptBlock {
                    Param ($logs,
                        $stamp,
                        $days)
                    $out = @()
                    $cutoffDate = (Get-Date).AddDays(-$days)
                    
                    ForEach ($log In $logs) {
                        Try {
                            # Check if log exists
                            $logExists = Get-WinEvent -ListLog $log -ErrorAction SilentlyContinue
                            If (-not $logExists) { Continue }
                            
                            $safeName = $log -replace '[\\/:*?"<>|]', '-'
                            $file = Join-Path $using:remoteTemp ("{0}-{1}.evtx" -f $safeName, $stamp)
                            
                            # Export with wevtutil
                            $cmd = "wevtutil epl `"${log}`" `"${file}`" /ow:true"
                            $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmd" `
                                                  -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                            
                            If ($proc.ExitCode -eq 0 -and (Test-Path $file)) {
                                $out += [pscustomobject]@{
                                    Type   = 'EventLog'
                                    Source = $log
                                    Path   = $file
                                }
                            }
                        } Catch {
                            Write-Warning "Failed to export log '$log': $_"
                        }
                    }
                    $out
                }
                
                # Collect configuration files if requested
                If ($IncludeConfigFiles -and $remoteVDAPath) {
                    $configFiles = Invoke-Command -Session $sess -ArgumentList @($remoteVDAPath, $tsStamp) -ScriptBlock {
                        Param ($vdaPath,
                            $stamp)
                        $out = @()
                        
                        # Common Citrix config file patterns
                        $patterns = @(
                            'ICA\*.config'
                            'ICA\*.ini'
                            '*.config'
                            'Logs\*.log'
                        )
                        
                        ForEach ($pattern In $patterns) {
                            $searchPath = Join-Path $vdaPath $pattern
                            Try {
                                $files = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
                                ForEach ($f In $files) {
                                    # Copy to temp with timestamp
                                    $destName = "{0}_{1}" -f $stamp, $f.Name
                                    $destPath = Join-Path $using:remoteTemp $destName
                                    Copy-Item -LiteralPath $f.FullName -Destination $destPath -Force
                                    
                                    $out += [pscustomobject]@{
                                        Type   = 'ConfigFile'
                                        Source = $f.FullName
                                        Path   = $destPath
                                    }
                                }
                            } Catch {
                                Write-Warning "Failed to collect config files from $searchPath"
                            }
                        }
                        $out
                    }
                    
                    If ($configFiles) { $exportedFiles += $configFiles }
                }
                
                # Collect WEM logs if requested
                If ($IncludeWEM) {
                    $wemLogs = Invoke-Command -Session $sess -ArgumentList $tsStamp -ScriptBlock {
                        Param ($stamp)
                        $out = @()
                        $wemPaths = @(
                            "${env:ProgramFiles}\Citrix\WEM Agent\Logs"
                            "${env:ProgramFiles(x86)}\Citrix\WEM Agent\Logs"
                            "C:\Program Files\Norskale\Norskale Agent Host\Logs"
                        )
                        
                        ForEach ($path In $wemPaths) {
                            If (Test-Path $path) {
                                Try {
                                    $logs = Get-ChildItem -Path $path -Filter *.log -ErrorAction Stop
                                    ForEach ($log In $logs) {
                                        $destName = "WEM_{0}_{1}" -f $stamp, $log.Name
                                        $destPath = Join-Path $using:remoteTemp $destName
                                        Copy-Item -LiteralPath $log.FullName -Destination $destPath -Force
                                        
                                        $out += [pscustomobject]@{
                                            Type   = 'WEMLog'
                                            Source = $log.FullName
                                            Path   = $destPath
                                        }
                                    }
                                } Catch { }
                                Break
                            }
                        }
                        $out
                    }
                    
                    If ($wemLogs) { $exportedFiles += $wemLogs }
                }
                
                # Collect Profile Management logs if requested
                If ($IncludeProfileManagement) {
                    $pmLogs = Invoke-Command -Session $sess -ArgumentList $tsStamp -ScriptBlock {
                        Param ($stamp)
                        $out = @()
                        $pmPaths = @(
                            "${env:ProgramFiles}\Citrix\User Profile Manager\Logs"
                            "${env:SystemRoot}\System32\Logfiles\UserProfileManager"
                        )
                        
                        ForEach ($path In $pmPaths) {
                            If (Test-Path $path) {
                                Try {
                                    $logs = Get-ChildItem -Path $path -Filter *.log -ErrorAction Stop
                                    ForEach ($log In $logs) {
                                        $destName = "ProfileMgmt_{0}_{1}" -f $stamp, $log.Name
                                        $destPath = Join-Path $using:remoteTemp $destName
                                        Copy-Item -LiteralPath $log.FullName -Destination $destPath -Force
                                        
                                        $out += [pscustomobject]@{
                                            Type   = 'ProfileManagementLog'
                                            Source = $log.FullName
                                            Path   = $destPath
                                        }
                                    }
                                } Catch { }
                                Break
                            }
                        }
                        $out
                    }
                    
                    If ($pmLogs) { $exportedFiles += $pmLogs }
                }
                
                # Copy all collected files back locally
                ForEach ($item In $exportedFiles) {
                    $fileName = Split-Path $item.Path -Leaf
                    $localName = "{0}_{1}" -f $safeComputer, $fileName
                    $localPath = Join-Path $DestinationPath $localName
                    
                    If ((-not $Overwrite) -and (Test-Path -LiteralPath $localPath)) {
                        Write-Warning "[$target] Local file already exists: $localPath (use -Overwrite to replace)"
                        Continue
                    }
                    
                    If ($PSCmdlet.ShouldProcess("$remoteComputerResolved : $($item.Path)", "Copy to $localPath")) {
                        Try {
                            Copy-Item -FromSession $sess -Path $item.Path -Destination $localPath -Force
                            
                            $results.Add([pscustomobject]@{
                                    ComputerName   = $target
                                    RemoteComputer = $remoteComputerResolved
                                    Type           = $item.Type
                                    Source         = $item.Source
                                    LocalPath      = (Resolve-Path -LiteralPath $localPath).Path
                                    Timestamp      = $ts
                                    Success        = $true
                                })
                        } Catch {
                            Write-Warning "[$target] Failed to copy $($item.Path): $_"
                        }
                    }
                }
                
                # Cleanup the remote temp folder (best effort)
                Invoke-Command -Session $sess -ScriptBlock {
                    Try { Remove-Item -LiteralPath $using:remoteTemp -Recurse -Force -ErrorAction Stop } Catch { }
                } | Out-Null
                
            } Catch {
                $err = $_
                Write-Warning "[$target] Export failed: $($err.Exception.Message)"
                $results.Add([pscustomobject]@{
                        ComputerName   = $target
                        RemoteComputer = $null
                        Type           = $null
                        Source         = $null
                        LocalPath      = $null
                        Timestamp      = $ts
                        Success        = $false
                        Error          = $err.Exception.Message
                    })
            } Finally {
                If ($sess) {
                    Try { Remove-PSSession -Session $sess -ErrorAction SilentlyContinue } Catch { }
                }
            }
        }
    }
    
    End {
        $results
    }
}

Function Get-CitrixLogSummary {
    <#
    .SYNOPSIS
    Parse Citrix EVTX and log files to identify connection and performance issues.

    .DESCRIPTION
    Reads Citrix event logs and text logs from a folder and returns events related to:
    - Connection failures and timeouts
    - Session startup/disconnection issues
    - HDX performance problems
    - VDA registration issues
    - Authentication failures
    - Profile Management issues
    - WEM issues

    .PARAMETER Path
    Root folder containing Citrix log files.

    .PARAMETER Recurse
    Search subfolders for log files.

    .PARAMETER StartTime
    Only include events on/after this time.

    .PARAMETER EndTime
    Only include events before this time.

    .PARAMETER IncludeInformational
    Include informational events (default is Warning/Error only).

    .PARAMETER CsvPath
    If provided, export results to CSV at this path.

    .EXAMPLE
    Get-CitrixLogSummary -Path .\CitrixLogs -Recurse -CsvPath .\CitrixIssues.csv

    .EXAMPLE
    Get-CitrixLogSummary -Path .\CitrixLogs -StartTime (Get-Date).AddHours(-24) -IncludeInformational
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$Path,
        [switch]$Recurse,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [switch]$IncludeInformational,
        [string]$CsvPath
    )
    
    # Critical Citrix event IDs for troubleshooting
    $criticalEventIds = @{
        # VDA Registration
        1000 = 'VDA registration succeeded'
        1001 = 'VDA registration failed'
        1016 = 'VDA cannot contact Controller'
        
        # Session/Connection
        1053 = 'Session logon failed'
        1054 = 'Session disconnected'
        1055 = 'Session reconnected'
        1056 = 'Session logoff'
        
        # HDX/ICA
        2598 = 'ICA connection failure'
        2599 = 'ICA session timeout'
        
        # Licensing
        16384 = 'License checkout succeeded'
        16385 = 'License checkout failed'
        
        # Profile Management
        1 = 'Profile load succeeded'
        2 = 'Profile load failed'
        11 = 'Profile unload succeeded'
        12 = 'Profile unload failed'
    }
    
    $out = New-Object System.Collections.Generic.List[object]
    
    # Process EVTX files
    $evtxFiles = Get-ChildItem -LiteralPath $Path -Filter *.evtx -File -Recurse:$Recurse -ErrorAction SilentlyContinue
    
    ForEach ($file In $evtxFiles) {
        Try {
            Write-Verbose "Processing EVTX: $($file.Name)"
            
            $filterHash = @{
                Path = $file.FullName
            }
            
            If (-not $IncludeInformational) {
                $filterHash.Level = @(1, 2, 3) # Critical, Error, Warning
            }
            
            $events = Get-WinEvent -FilterHashtable $filterHash -ErrorAction Stop
            
            If ($StartTime) { $events = $events | Where-Object { $_.TimeCreated -ge $StartTime } }
            If ($EndTime) { $events = $events | Where-Object { $_.TimeCreated -lt $EndTime } }
            
            ForEach ($ev In $events) {
                $category = 'General'
                $description = $criticalEventIds[$ev.Id]
                
                # Categorize events
                If ($ev.ProviderName -like '*VirtualDesktopAgent*') {
                    $category = 'VDA'
                } ElseIf ($ev.ProviderName -like '*ICA*' -or $ev.ProviderName -like '*HDX*') {
                    $category = 'Connection/HDX'
                } ElseIf ($ev.ProviderName -like '*Profile*') {
                    $category = 'ProfileManagement'
                } ElseIf ($ev.ProviderName -like '*GroupPolicy*') {
                    $category = 'Policy'
                }
                
                $out.Add([pscustomobject]@{
                        TimeCreated   = $ev.TimeCreated
                        Computer      = $ev.MachineName
                        Category      = $category
                        Provider      = $ev.ProviderName
                        EventId       = $ev.Id
                        Level         = $ev.LevelDisplayName
                        Description   = $description
                        Message       = $ev.Message
                        SourceFile    = $file.Name
                        EventRecordId = $ev.RecordId
                    })
            }
        } Catch {
            Write-Warning "Failed to read '$($file.FullName)': $_"
        }
    }
    
    # Process text log files (WEM, Profile Management, etc.)
    $logFiles = Get-ChildItem -LiteralPath $Path -Filter *.log -File -Recurse:$Recurse -ErrorAction SilentlyContinue
    
    ForEach ($file In $logFiles) {
        Try {
            Write-Verbose "Processing log: $($file.Name)"
            
            $content = Get-Content -LiteralPath $file.FullName -ErrorAction Stop
            $lineNum = 0
            
            ForEach ($line In $content) {
                $lineNum++
                
                # Parse common log patterns for errors/warnings
                If ($line -match '\b(ERROR|FAIL|WARN|CRITICAL|EXCEPTION|TIMEOUT)\b') {
                    # Try to extract timestamp
                    $timestamp = $null
                    If ($line -match '\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}') {
                        Try {
                            $timestamp = [datetime]::Parse($matches[0])
                        } Catch { }
                    }
                    
                    If ($timestamp) {
                        If ($StartTime -and $timestamp -lt $StartTime) { Continue }
                        If ($EndTime -and $timestamp -ge $EndTime) { Continue }
                    }
                    
                    $level = 'Warning'
                    If ($line -match '\bERROR\b|\bFAIL\b|\bCRITICAL\b|\bEXCEPTION\b') {
                        $level = 'Error'
                    }
                    
                    $category = 'TextLog'
                    If ($file.Name -like 'WEM*') {
                        $category = 'WEM'
                    } ElseIf ($file.Name -like 'ProfileMgmt*' -or $file.Name -like '*UPM*') {
                        $category = 'ProfileManagement'
                    }
                    
                    $out.Add([pscustomobject]@{
                            TimeCreated   = $timestamp
                            Computer      = $null
                            Category      = $category
                            Provider      = 'TextLog'
                            EventId       = $lineNum
                            Level         = $level
                            Description   = $null
                            Message       = $line.Trim()
                            SourceFile    = $file.Name
                            EventRecordId = $lineNum
                        })
                }
            }
        } Catch {
            Write-Warning "Failed to read '$($file.FullName)': $_"
        }
    }
    
    $results = $out | Sort-Object TimeCreated, Computer
    
    If ($CsvPath) {
        $dir = Split-Path -Path $CsvPath -Parent
        If ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $CsvPath
        Write-Verbose "Results exported to: $CsvPath"
    }
    
    $results
}


Function Test-RemoteCitrixLogs {
    <#
    .SYNOPSIS
    Diagnose what Citrix logs are available on a remote system and identify the VDA version.
    
    .DESCRIPTION
    Connects to a remote system and lists:
    - Citrix VDA version and build information
    - All Citrix-related event logs and their record counts
    - File system log locations
    - Installed Citrix components
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    $sessionParams = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
    }
    If ($Credential) { $sessionParams.Credential = $Credential }
    
    Try {
        $sess = New-PSSession @sessionParams
        
        $report = Invoke-Command -Session $sess -ScriptBlock {
            $output = [ordered]@{
                ComputerName   = $env:COMPUTERNAME
                CitrixVersion  = $null
                CitrixProducts = @()
                EventLogs      = @()
                FileSystemLogs = @()
                CitrixPaths    = @()
                CitrixServices = @()
            }
            
            # Check Citrix VDA version from registry
            Write-Host "`n=== Checking Citrix Version ===" -ForegroundColor Cyan
            
            $versionKeys = @(
                'HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent',
                'HKLM:\SOFTWARE\Wow6432Node\Citrix\VirtualDesktopAgent',
                'HKLM:\SOFTWARE\Citrix\ICA Client',
                'HKLM:\SOFTWARE\Citrix\InstallManager'
            )
            
            ForEach ($keyPath In $versionKeys) {
                If (Test-Path $keyPath) {
                    Try {
                        $key = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue
                        If ($key) {
                            # VDA specific keys
                            If ($key.ProductVersion) {
                                $output.CitrixVersion = [pscustomobject]@{
                                    Product     = 'Virtual Desktop Agent'
                                    Version     = $key.ProductVersion
                                    Build       = $key.BuildNumber
                                    InstallPath = $key.InstallPath
                                    RegistryKey = $keyPath
                                }
                                Write-Host ("  VDA Version: {0}" -f $key.ProductVersion) -ForegroundColor Green
                                Write-Host ("  VDA Build: {0}" -f $key.BuildNumber) -ForegroundColor Green
                            }
                            
                            # Try to get version another way if ProductVersion isn't set
                            If ($key.Version) {
                                Write-Host ("  Version: {0}" -f $key.Version)
                            }
                        }
                    } Catch { }
                }
            }
            
            # Check for installed Citrix products via registry
            Write-Host "`n=== Checking Installed Citrix Products ===" -ForegroundColor Cyan
            $uninstallKeys = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            
            $citrixProducts = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Citrix*' } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
            Sort-Object DisplayName
            
            ForEach ($product In $citrixProducts) {
                $output.CitrixProducts += $product
                Write-Host ("  {0} - Version {1}" -f $product.DisplayName, $product.DisplayVersion) -ForegroundColor Green
            }
            
            # Check Citrix services for additional version info
            Write-Host "`n=== Checking Citrix Services ===" -ForegroundColor Cyan
            $services = Get-Service | Where-Object { $_.DisplayName -like '*Citrix*' -or $_.Name -like '*Citrix*' }
            ForEach ($svc In $services) {
                $svcDetail = [pscustomobject]@{
                    Name        = $svc.Name
                    DisplayName = $svc.DisplayName
                    Status      = $svc.Status
                    StartType   = $svc.StartType
                }
                
                # Try to get the executable path for version info
                Try {
                    $svcConfig = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
                    If ($svcConfig.PathName) {
                        # Extract the executable path (remove quotes and parameters)
                        $exePath = $svcConfig.PathName -replace '"', '' -split ' ' | Select-Object -First 1
                        If (Test-Path $exePath) {
                            $fileVersion = (Get-Item $exePath).VersionInfo
                            $svcDetail | Add-Member -NotePropertyName FileVersion -NotePropertyValue $fileVersion.FileVersion
                            $svcDetail | Add-Member -NotePropertyName ProductVersion -NotePropertyValue $fileVersion.ProductVersion
                        }
                    }
                } Catch { }
                
                $output.CitrixServices += $svcDetail
                Write-Host ("  {0} ({1}) - {2}" -f $svc.DisplayName, $svc.Status, $svc.StartType)
            }
            
            # Check for Citrix event logs
            Write-Host "`n=== Checking Citrix Event Logs ===" -ForegroundColor Cyan
            $allLogs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
            Where-Object { $_.LogName -like '*Citrix*' }
            
            ForEach ($log In $allLogs) {
                $count = 0
                $oldestEvent = $null
                $newestEvent = $null
                
                Try {
                    $events = Get-WinEvent -LogName $log.LogName -ErrorAction SilentlyContinue
                    If ($events) {
                        $count = ($events | Measure-Object).Count
                        $oldestEvent = ($events | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
                        $newestEvent = ($events | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
                    }
                } Catch { }
                
                $output.EventLogs += [pscustomobject]@{
                    LogName     = $log.LogName
                    RecordCount = $count
                    IsEnabled   = $log.IsEnabled
                    MaxSizeKB   = [math]::Round($log.MaximumSizeInBytes / 1KB, 0)
                    OldestEvent = $oldestEvent
                    NewestEvent = $newestEvent
                }
                
                If ($count -gt 0) {
                    Write-Host ("  {0}: {1} records (Newest: {2})" -f $log.LogName, $count, $newestEvent) -ForegroundColor Green
                } Else {
                    Write-Host ("  {0}: Empty" -f $log.LogName) -ForegroundColor DarkGray
                }
            }
            
            # Check for Citrix installation paths
            Write-Host "`n=== Checking Citrix Installation Paths ===" -ForegroundColor Cyan
            $programFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
            ForEach ($pf In $programFiles) {
                $citrixPath = Join-Path $pf "Citrix"
                If (Test-Path $citrixPath) {
                    $output.CitrixPaths += $citrixPath
                    Write-Host "  Found: $citrixPath" -ForegroundColor Green
                    
                    # List subdirectories with file counts
                    $subdirs = Get-ChildItem -Path $citrixPath -Directory -ErrorAction SilentlyContinue
                    ForEach ($dir In $subdirs) {
                        $fileCount = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
                        Write-Host ("    - {0} ({1} files)" -f $dir.Name, $fileCount)
                    }
                }
            }
            
            # Check for log files in file system
            Write-Host "`n=== Checking File System Logs ===" -ForegroundColor Cyan
            $logPaths = @(
                "${env:ProgramFiles}\Citrix\Virtual Desktop Agent\Logs"
                "${env:ProgramFiles(x86)}\Citrix\Virtual Desktop Agent\Logs"
                "${env:ProgramFiles}\Citrix\ICA Client\Logs"
                "${env:ProgramFiles(x86)}\Citrix\ICA Client\Logs"
                "${env:ProgramFiles}\Citrix\WEM Agent\Logs"
                "${env:ProgramFiles(x86)}\Citrix\WEM Agent\Logs"
                "${env:ProgramFiles}\Citrix\User Profile Manager\Logs"
                "${env:ProgramFiles(x86)}\Citrix\User Profile Manager\Logs"
                "${env:SystemRoot}\System32\Logfiles\Citrix"
                "${env:SystemRoot}\Temp"
                "C:\Program Files\Norskale\Norskale Agent Host\Logs"
                "${env:LOCALAPPDATA}\Citrix\Logs"
                "${env:TEMP}\Citrix"
            )
            
            ForEach ($path In $logPaths) {
                If (Test-Path $path) {
                    Write-Host "  Found: $path" -ForegroundColor Green
                    $logs = Get-ChildItem -Path $path -Filter *.log -File -ErrorAction SilentlyContinue
                    $totalSize = ($logs | Measure-Object -Property Length -Sum).Sum
                    Write-Host ("    Total: {0} files, {1:N2} MB" -f $logs.Count, ($totalSize/1MB))
                    
                    ForEach ($log In $logs) {
                        $output.FileSystemLogs += [pscustomobject]@{
                            Path   = $log.FullName
                            Name   = $log.Name
                            SizeMB = [math]::Round($log.Length / 1MB, 2)
                            LastWrite = $log.LastWriteTime
                            Directory = Split-Path $log.FullName -Parent
                        }
                        
                        If ($logs.Count -le 20) {
                            Write-Host ("      - {0} ({1:N2} MB, Last: {2})" -f $log.Name, ($log.Length/1MB), $log.LastWriteTime)
                        }
                    }
                    
                    If ($logs.Count -gt 20) {
                        Write-Host "      (showing summary only - too many files to list individually)"
                    }
                }
            }
            
            $output
        }
        
        Remove-PSSession -Session $sess
        
        # Display summary
        Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
        Write-Host ("Computer: {0}" -f $report.ComputerName) -ForegroundColor White
        
        If ($report.CitrixVersion) {
            Write-Host ("`nCitrix VDA:") -ForegroundColor Yellow
            Write-Host ("  Product: {0}" -f $report.CitrixVersion.Product) -ForegroundColor White
            Write-Host ("  Version: {0}" -f $report.CitrixVersion.Version) -ForegroundColor White
            Write-Host ("  Build: {0}" -f $report.CitrixVersion.Build) -ForegroundColor White
        }
        
        If ($report.CitrixProducts.Count -gt 0) {
            Write-Host ("`nInstalled Products: {0}" -f $report.CitrixProducts.Count) -ForegroundColor Yellow
            $report.CitrixProducts | ForEach-Object {
                Write-Host ("  - {0} ({1})" -f $_.DisplayName, $_.DisplayVersion) -ForegroundColor White
            }
        }
        
        Write-Host ("`nServices: {0} total, {1} running" -f $report.CitrixServices.Count, ($report.CitrixServices | Where-Object Status -eq 'Running').Count) -ForegroundColor Yellow
        Write-Host ("Event Logs: {0} found, {1} with records" -f $report.EventLogs.Count, ($report.EventLogs | Where-Object RecordCount -gt 0).Count) -ForegroundColor Yellow
        Write-Host ("File System Logs: {0} files" -f $report.FileSystemLogs.Count) -ForegroundColor Yellow
        Write-Host ("Citrix Install Paths: {0}" -f $report.CitrixPaths.Count) -ForegroundColor Yellow
        
        # Show event logs with the most records
        $topLogs = $report.EventLogs | Where-Object RecordCount -gt 0 | Sort-Object RecordCount -Descending | Select-Object -First 5
        If ($topLogs) {
            Write-Host "`nTop Event Logs by Record Count:" -ForegroundColor Yellow
            $topLogs | ForEach-Object {
                Write-Host ("  {0}: {1:N0} records" -f $_.LogName, $_.RecordCount) -ForegroundColor White
            }
        }
        
        Return $report
        
    } Catch {
        Write-Error "Failed to connect or query: $_"
    }
}
