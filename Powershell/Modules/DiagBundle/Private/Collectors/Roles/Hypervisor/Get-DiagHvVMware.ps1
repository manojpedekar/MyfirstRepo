function Get-DiagHvVMware {
    <#
    .SYNOPSIS
        VMware ESXi / vSphere guest-agent collector. Captures VMware Tools
        version, install path, build, registry export, operational logs,
        installer logs in the time window, paravirt drivers, NIC advanced
        properties, and time-sync provider state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory)] [string] $RawDir,
        [Parameter(Mandatory)] [int]    $WindowHours,
        [Parameter(Mandatory)] [ref]    $HvData,
        [Parameter(Mandatory)] [ref]    $Result
    )

    $platformDir = Join-Path $RawDir 'vmware'
    if (-not (Test-Path -LiteralPath $platformDir)) {
        New-Item -ItemType Directory -Force -Path $platformDir | Out-Null
    }
    $cutoff = (Get-Date).AddHours(-1 * $WindowHours)

    $HvData.Value.guest_agent_name = 'VMware Tools'

    try {
        $tools = Get-ItemProperty -Path 'HKLM:\SOFTWARE\VMware, Inc.\VMware Tools' -ErrorAction Stop
        $HvData.Value.guest_agent_installed    = $true
        $HvData.Value.guest_agent_install_path = "$($tools.InstallPath)"
        $HvData.Value.guest_agent_version      = "$($tools.ProductVersion)"
        if ($tools.PSObject.Properties['BuildNumber'])          { $HvData.Value.platform_specific['tools_build']        = "$($tools.BuildNumber)" }
        if ($tools.PSObject.Properties['InstallTime'])          { $HvData.Value.platform_specific['tools_install_time'] = "$($tools.InstallTime)" }
        if ($tools.PSObject.Properties['LastUpgradeStatus'])    { $HvData.Value.platform_specific['tools_last_upgrade'] = "$($tools.LastUpgradeStatus)" }
    } catch { }

    $regOut = Join-Path $platformDir 'vmware_registry.reg'
    Invoke-DiagTimed -Collector 'Get-DiagHvVMware' -Step 'reg export VMware Tools' -Action {
        & reg.exe export 'HKLM\SOFTWARE\VMware, Inc.' $regOut /y 2>&1
    } | Out-Null
    if (Test-Path -LiteralPath $regOut) {
        $HvData.Value.registry_export_path = 'raw/role_specific/hypervisor/vmware/vmware_registry.reg'
        $Result.Value.Artifacts += @{
            path        = 'raw/role_specific/hypervisor/vmware/vmware_registry.reg'
            category    = 'hypervisor_registry'
            type        = 'raw'
            description = 'reg export HKLM\SOFTWARE\VMware, Inc.'
        }
    }

    _CopyAgentLogs -SrcDir 'C:\ProgramData\VMware\VMware Tools' `
                   -DstDir (Join-Path $platformDir 'tools_logs') `
                   -Patterns '*.log','*.log_old','*.txt' `
                   -HvData $HvData -Result $Result `
                   -ArtifactCategory 'hypervisor_agent_log' `
                   -BundlePathPrefix 'raw/role_specific/hypervisor/vmware/tools_logs'

    _CopyInstallerLogsInWindow -Patterns 'vmware-*','vminst.log*','vmmsi.log*' `
                               -DstDir (Join-Path $platformDir 'installer_logs') `
                               -Cutoff $cutoff `
                               -HvData $HvData -Result $Result `
                               -BundlePathPrefix 'raw/role_specific/hypervisor/vmware/installer_logs'

    foreach ($bin in 'vmtoolsd.exe','vm3dservice.exe','VGAuthService.exe') {
        if ($HvData.Value.guest_agent_install_path) {
            _AddBinaryVersionInfo -InstallPath $HvData.Value.guest_agent_install_path -BinaryName $bin -HvData $HvData
        }
    }

    _CapturePvDrivers   -Names 'vmci','vmxnet3','vmxnet3ndis6','pvscsi','vsock','vm3dmp','vmmouse' -HvData $HvData
    _CaptureNicAdvanced -InterfaceLike '*vmxnet3*' -HvData $HvData
    _CaptureTimeSyncProvider -HvData $HvData
}
