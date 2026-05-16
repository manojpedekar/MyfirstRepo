# Must run as Administrator
If (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    Exit 1
}

Write-Host "Detecting Windows Server version and edition..." -ForegroundColor Cyan

$os = Get-CimInstance Win32_OperatingSystem
$caption = $os.Caption
$currentEdition = (dism /online /Get-CurrentEdition) |
    Select-String "Current Edition" |
    ForEach-Object { $_.Line.Split(':')[1].Trim() }

Write-Host "OS: $caption"
Write-Host "Current Edition: $currentEdition"

If ($currentEdition -like "*Datacenter*") {
    Write-Host "System is already Datacenter edition. No action required." -ForegroundColor Green
    Exit 0
}

# KMS Client Setup Keys (Microsoft official generic keys)
$kmsKeys = @{
    "2012"   = "BC46NM4-VDY9V-DYPG2-3TY7X-3D3PP"   # Server 2012 Datacenter
    "2012R2" = "W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9"   # Server 2012 R2 Datacenter
    "2016"   = "CB7KF-BWN84-R7R2Y-793K2-8XDDG"   # Server 2016 Datacenter
    "2019"   = "WMDGN-G9PQG-XVVXX-R3X43-63DFG"   # Server 2019 Datacenter
    "2022"   = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33"   # Server 2022 Datacenter
}

# Detect OS version
Switch -Regex ($caption) {
    "2012 R2" { $targetKey = $kmsKeys["2012R2"] }
    "2012"    { $targetKey = $kmsKeys["2012"] }
    "2016"    { $targetKey = $kmsKeys["2016"] }
    "2019"    { $targetKey = $kmsKeys["2019"] }
    "2022"    { $targetKey = $kmsKeys["2022"] }
    Default {
        Write-Error "Unsupported Windows Server version."
        Exit 1
    }
}

Write-Host "Applying Datacenter edition using KMS key..." -ForegroundColor Yellow

# Change edition
dism /online /Set-Edition:ServerDatacenter /ProductKey:$targetKey /AcceptEula

If ($LASTEXITCODE -ne 0) {
    Write-Error "Edition upgrade failed."
    Exit 1
}

Write-Host "Edition change initiated successfully." -ForegroundColor Green
Write-Host "Activating via KMS..." -ForegroundColor Cyan

# Activate
cscript.exe //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato

Write-Host "============================================"
Write-Host "SUCCESS!"
Write-Host "System upgraded to Datacenter edition."
Write-Host "REBOOT REQUIRED to complete the upgrade."
Write-Host "============================================" -ForegroundColor Green
