# --------------------------
# Initialize result objects
# --------------------------
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$tcpResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$computerName = $env:COMPUTERNAME

# --------------------------
# 1. Check RD Session Host Role
# --------------------------
$rdRole = Get-WindowsFeature -Name RDS-RD-Server -ErrorAction SilentlyContinue
$rdInstalled = if ($rdRole.Installed) { $true } else { $false }

# --------------------------
# 2. Reboot Pending (Role/Feature Changes ONLY)
# --------------------------
$cbsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

if (-not $rdInstalled) {
    $rebootPending = "NA"
} elseif (Test-Path $cbsPath) {
    $rebootPending = "Yes"
} else {
    $rebootPending = "No"
}

# --------------------------
# 3. Domain Group Membership Check
# --------------------------
$groupName = "role-gpo-RDSH-servers"
$isMember = "No"
try {
    $groupMembersOutput = net group $groupName /domain 2>$null
    if ($groupMembersOutput) {
        # Filter headers/footers, join, and split by whitespace
        $members = $groupMembersOutput | 
            Where-Object { $_ -and $_ -notmatch "Members|-----|The command completed successfully" } | 
            ForEach-Object { $_.Trim() }
        
        $membersList = ($members -join ' ') -split '\s+'
        
        if ($membersList -contains "$computerName$") { 
            $isMember = "Yes" 
        }
    }
} catch { $isMember = "Check failed" }

# --------------------------
# 4. License Servers & Mode
# --------------------------
$tsKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
$regData = Get-ItemProperty -Path $tsKey -ErrorAction SilentlyContinue

$licenseServers = if ($regData.LicenseServers) {
    $regData.LicenseServers -split "," | ForEach-Object { $_.Trim() }
} else { @() }

$licensingModeText = switch ($regData.LicensingMode) {
    2 { "Per Device" }
    4 { "Per User" }
    default { "Not Configured" }
}

# --------------------------
# 5. TCP Connectivity Check (Port 135)
# --------------------------
if ($licenseServers.Count -gt 0) {
    foreach ($server in $licenseServers) {
        $status = if (Test-NetConnection -ComputerName $server -Port 135 -WarningAction SilentlyContinue -InformationLevel Quiet) {
            "Success"
        } else {
            "Failed"
        }
        $tcpResults.Add([PSCustomObject]@{
            LicenseServer   = $server
            TCP135Reachable = $status
        })
    }
} else {
    $tcpResults.Add([PSCustomObject]@{
        LicenseServer   = "None configured"
        TCP135Reachable = "Skipped"
    })
}

# --------------------------
# 6. Build Summary Result
# --------------------------
$summaryTCP = if ($tcpResults.Count -gt 1) {
    "See details below"
} elseif ($tcpResults.Count -eq 1) {
    $tcpResults[0].TCP135Reachable
} else { "N/A" }

$results.Add([PSCustomObject]@{
    ServerName        = $computerName
    RDSessionHostRole = if ($rdInstalled) { "Yes" } else { "No" }
    RebootPending     = $rebootPending
    GroupMembership   = $isMember
    LicenseServers    = if ($licenseServers) { $licenseServers -join "," } else { "None" }
    LicensingMode     = $licensingModeText
    TCP135Check       = $summaryTCP
})

# --------------------------
# 7. Output Summary Table
# --------------------------
Write-Host "`n--- Server Summary ---`n"
$results | Format-Table -AutoSize

if ($licenseServers.Count -gt 1) {
    Write-Host "`n--- TCP 135 Connectivity per License Server ---`n"
    $tcpResults | Format-Table -AutoSize
}