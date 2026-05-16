# upgrade_to_datacenter.ps1
$currentEdition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID

if ($currentEdition -eq "ServerDatacenter") {
    Write-Output "Already Datacenter edition. Skipping upgrade."
    exit 0
}

$caption = (Get-CimInstance Win32_OperatingSystem).Caption

$kmsKeys = @{
    "2012"   = "48HP8-DN98B-MYWDG-T2DCC-8W83P"
    "2012R2" = "W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9"
    "2016"   = "CB7KF-BWN84-R7R2Y-793K2-8XDDG"
    "2019"   = "WMDGN-G9PQG-XVVXX-R3X43-63DFG"
    "2022"   = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33"
}

$key = $null

switch -Regex ($caption) {
    "2012 R2" { $key = $kmsKeys["2012R2"] }
    "2012"    { $key = $kmsKeys["2012"] }
    "2016"    { $key = $kmsKeys["2016"] }
    "2019"    { $key = $kmsKeys["2019"] }
    "2022"    { $key = $kmsKeys["2022"] }
    default   { Write-Error "Unsupported OS version: $caption"; exit 1 }
}

Write-Output "Upgrading $currentEdition to ServerDatacenter using key $key..."
dism /online /Set-Edition:ServerDatacenter /ProductKey:$key /AcceptEula /Quiet /NoRestart

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
    Write-Output "Edition change applied successfully."
    cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato
    shutdown /r /t 30 /c "Windows Server edition upgraded to Datacenter. Rebooting to complete upgrade."
} else {
    Write-Error "DISM failed with exit code $LASTEXITCODE"
    exit 1
}
