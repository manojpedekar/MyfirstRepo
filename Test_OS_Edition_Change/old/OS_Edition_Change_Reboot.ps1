# Detect current edition ID
$currentEdition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID

# If already Datacenter, skip upgrade and exit
if ($currentEdition -eq "ServerDatacenter") {
    Write-Output "Already Datacenter edition. Skipping upgrade."
    exit 0
}

# 2. Detect OS Caption
$caption = (Get-CimInstance Win32_OperatingSystem).Caption

# 3. Official KMS GVLK Keys (Datacenter)
$kmsKeys = @{
    "2012"   = "48HP8-DN98B-MYWDG-T2DCC-8W83P"
    "2012R2" = "W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9"
    "2016"   = "CB7KF-BWN84-R7R2Y-793K2-8XDDG"
    "2019"   = "WMDGN-G9PQG-XVVXX-R3X43-63DFG"
    "2022"   = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33"
}

$key = $null

# 4. Match OS version to Key
switch -Regex ($caption) {
    "2012 R2" { $key = $kmsKeys["2012R2"] }
    "2012"    { $key = $kmsKeys["2012"] }
    "2016"    { $key = $kmsKeys["2016"] }
    "2019"    { $key = $kmsKeys["2019"] }
    "2022"    { $key = $kmsKeys["2022"] }
    default   { Write-Error "Unsupported OS version: $caption"; exit 1 }
}

# 5. Execute Edition Upgrade
# Note: DISM exit code 0 = Success, 3010 = Success (Reboot Required)
Write-Output "Upgrading $currentEdition to ServerDatacenter using key $key..."
dism /online /Set-Edition:ServerDatacenter /ProductKey:$key /AcceptEula /Quiet /NoRestart

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3010) {
    Write-Output "Edition change applied successfully."
    
    # 6. Attempt background activation
    # This may fail until the reboot is complete, but slmgr /ato is safe to run.
    cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /ato
    
    # 7. Trigger Reboot
    Write-Output "Rebooting in 30 seconds to finalize upgrade..."
    shutdown /r /t 30 /c "Windows Server edition upgraded to Datacenter. Rebooting to complete upgrade."
} else {
    Write-Error "DISM failed with exit code $LASTEXITCODE"
    exit 1
}
