function Get-DiagNetwork {
    <#
    .SYNOPSIS
        Capture network configuration, listening ports, DNS cache, and firewall.

    .DESCRIPTION
        Run ipconfig /all, route print, netstat -ano, netsh advfirewall show
        currentprofile, and ipconfig /displaydns into five raw text files under
        raw/netsh/. Then enumerate Get-NetIPConfiguration for adapters,
        Get-NetTCPConnection for listening sockets joined to process names, and
        Get-NetFirewallProfile for firewall posture, and emit a derived
        summary/network.json. Runs in parallel with peer collectors. netstat -ano
        and the firewall query benefit from administrator privileges; non-admin
        runs still produce most data.

    .PARAMETER WorkingDirectory
        Mandatory. Absolute path to the bundle staging root. The collector writes
        into the existing summary\ and raw\netsh\ subdirectories.

    .INPUTS
        None.

    .OUTPUTS
        [pscustomobject] with Success ([bool]), Artifacts (array of hashtables with
        path/category/type/description and per-type metadata), Errors (array of
        hashtables with collector/reason/severity), DurationSeconds ([int]).

    .EXAMPLE
        Get-DiagNetwork -WorkingDirectory $bundleRoot

    .NOTES
        Writes:
          - raw/netsh/ipconfig.txt
          - raw/netsh/route.txt
          - raw/netsh/netstat.txt
          - raw/netsh/firewall.txt
          - raw/netsh/dns_cache.txt
          - summary/network.json

        Per-command failures append warning entries to Errors and skip only the
        affected file. Get-NetIPConfiguration, Get-NetTCPConnection, and
        Get-NetFirewallProfile failures degrade their summary sections to empty
        without aborting. Never throws; populates Errors and returns
        Success=$false on fatal abort.
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
        $rawNet = Join-Path $WorkingDirectory 'raw\netsh'

        $cmds = @(
            @{ Name = 'ipconfig.txt'; Cmd = 'ipconfig.exe'; Args = @('/all') }
            @{ Name = 'route.txt';    Cmd = 'route.exe';    Args = @('print') }
            @{ Name = 'netstat.txt';  Cmd = 'netstat.exe';  Args = @('-ano') }
            @{ Name = 'firewall.txt'; Cmd = 'netsh.exe';    Args = @('advfirewall', 'show', 'currentprofile') }
            @{ Name = 'dns_cache.txt'; Cmd = 'ipconfig.exe'; Args = @('/displaydns') }
        )

        foreach ($c in $cmds) {
            $out = Join-Path $rawNet $c.Name
            try {
                $text = & $c.Cmd @($c.Args) 2>&1
                [System.IO.File]::WriteAllText($out, ($text -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
                $result.Artifacts += @{
                    path        = "raw/netsh/$($c.Name)"
                    category    = 'network_text'
                    type        = 'raw'
                    description = "$($c.Cmd) $($c.Args -join ' ')"
                }
            } catch {
                $result.Errors += @{ collector = 'Get-DiagNetwork'; artifact = "raw/netsh/$($c.Name)"; reason = $_.Exception.Message; severity = 'warning' }
            }
        }

        $adapters = @()
        try {
            $adapters = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
                [ordered]@{
                    interface_alias = $_.InterfaceAlias
                    interface_index = $_.InterfaceIndex
                    description     = $_.InterfaceDescription
                    ipv4_addresses  = @($_.IPv4Address  | ForEach-Object { $_.IPAddress })
                    ipv6_addresses  = @($_.IPv6Address  | ForEach-Object { $_.IPAddress })
                    default_gateway = @($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
                    dns_servers     = @($_.DNSServer | ForEach-Object { $_.ServerAddresses } | ForEach-Object { $_ })
                    net_profile     = "$($_.NetProfile.Name)"
                }
            })
        } catch { }

        $listening = @()
        try {
            $tcps = Invoke-DiagTimed -Collector 'Get-DiagNetwork' -Step 'Get-NetTCPConnection -State Listen' -Action {
                Get-NetTCPConnection -State Listen -ErrorAction Stop
            }
            $procMap = @{}
            Get-Process | ForEach-Object { $procMap[$_.Id] = $_.ProcessName }
            $listening = @($tcps | ForEach-Object {
                [ordered]@{
                    local_address = $_.LocalAddress
                    local_port    = [int]$_.LocalPort
                    pid           = [int]$_.OwningProcess
                    process_name  = if ($procMap.ContainsKey([int]$_.OwningProcess)) { $procMap[[int]$_.OwningProcess] } else { $null }
                }
            })
        } catch { }

        $firewallProfiles = @()
        try {
            $firewallProfiles = @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
                [ordered]@{
                    name              = "$($_.Name)"
                    enabled           = [bool]$_.Enabled
                    default_inbound   = "$($_.DefaultInboundAction)"
                    default_outbound  = "$($_.DefaultOutboundAction)"
                    log_allowed       = [bool]$_.LogAllowed
                    log_blocked       = [bool]$_.LogBlocked
                }
            })
        } catch { }

        $data = [ordered]@{
            schema_version = '1.0'
            host           = @{ computer_name = $env:COMPUTERNAME }
            collected_utc  = (Get-Date).ToUniversalTime().ToString($fmt)
            data           = [ordered]@{
                adapters          = $adapters
                listening_ports   = $listening
                firewall_profiles = $firewallProfiles
            }
        }

        $sumPath = Join-Path $WorkingDirectory 'summary\network.json'
        $json = $data | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($sumPath, $json, [System.Text.UTF8Encoding]::new($false))

        $result.Artifacts += @{
            path           = 'summary/network.json'
            category       = 'network'
            schema_version = '1.0'
            type           = 'derived'
            description    = 'Adapters, listening ports, firewall profiles'
        }

        $result.Success = $true
    }
    catch {
        $result.Errors += @{ collector = 'Get-DiagNetwork'; reason = $_.Exception.Message; severity = 'error' }
    }
    finally {
        $result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
    }

    return $result
}
