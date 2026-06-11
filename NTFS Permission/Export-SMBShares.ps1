# Export all SMB shares — requires PowerShell 3+ / Server 2012+
#
# Usage — local machine:
#   .\Export-SMBShares.ps1
#
# Usage — remote server:
#   .\Export-SMBShares.ps1 -Server "FILESERVER01"
#
# Usage — multiple servers:
#   .\Export-SMBShares.ps1 -Server "FS01","FS02","FS03"

param(
    [string[]]$Server    = @($env:COMPUTERNAME),
    [string]  $OutputDir = "C:\temp",
    [switch]  $IncludeAdmin          # include hidden admin shares (C$, ADMIN$, IPC$)
)

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$allShares = foreach ($srv in $Server) {
    Write-Host "Querying shares on '$srv'..."

    try {
        $shares = Get-SmbShare -CimSession $srv -ErrorAction Stop

        if (-not $IncludeAdmin) {
            # Special = 0 means regular share; exclude $ shares
            $shares = $shares | Where-Object { $_.Special -eq $false }
        }

        $shares | Select-Object `
            @{N="Server";      E={ $srv }},
            @{N="ShareName";   E={ $_.Name }},
            @{N="LocalPath";   E={ $_.Path }},
            @{N="UNCPath";     E={ "\\$srv\$($_.Name)" }},
            @{N="Description"; E={ $_.Description }},
            @{N="ShareState";  E={ $_.ShareState }},
            @{N="Special";     E={ $_.Special }}
    }
    catch {
        Write-Warning "  Failed on '$srv': $_"
    }
}

if (-not $allShares) {
    Write-Warning "No shares found."
    exit 0
}

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDir "SMBShares_$timestamp.csv"

$allShares | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "`nExported $($allShares.Count) share(s) -> $outputFile" -ForegroundColor Green

# Print to console as a table too
$allShares | Format-Table Server, ShareName, LocalPath, UNCPath, Description -AutoSize