# Export share-level permissions for all SMB shares
# Uses Get-SmbShare + Get-SmbShareAccess (Server 2012+ / PS3+)
#
# Usage — local machine:
#   .\Export-SharePermissions.ps1
#
# Usage — remote server:
#   .\Export-SharePermissions.ps1 -Server "FILESERVER01"
#
# Usage — multiple servers:
#   .\Export-SharePermissions.ps1 -Server "FS01","FS02","FS03"

param(
    [string[]]$Server      = @($env:COMPUTERNAME),
    [string]  $OutputDir   = "C:\temp",
    [switch]  $IncludeAdmin     # include C$, ADMIN$, IPC$ etc.
)

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$results = foreach ($srv in $Server) {
    Write-Host "`nQuerying shares on '$srv'..."

    try {
        $shares = Get-SmbShare -CimSession $srv -ErrorAction Stop

        if (-not $IncludeAdmin) {
            $shares = $shares | Where-Object { $_.Special -eq $false }
        }

        foreach ($share in $shares) {
            Write-Host "  Share: $($share.Name)"

            try {
                $acls = Get-SmbShareAccess -Name $share.Name `
                            -CimSession $srv -ErrorAction Stop

                foreach ($acl in $acls) {
                    [PSCustomObject]@{
                        Server          = $srv
                        ShareName       = $share.Name
                        LocalPath       = $share.Path
                        UNCPath         = "\\$srv\$($share.Name)"
                        AccountName     = $acl.AccountName
                        AccessControlType = $acl.AccessControlType   # Allow / Deny
                        AccessRight     = $acl.AccessRight            # Full / Change / Read
                    }
                }
            }
            catch {
                Write-Warning "    Could not read ACL for '$($share.Name)': $_"
            }
        }
    }
    catch {
        Write-Warning "  Failed on '$srv': $_"
    }
}

if (-not $results) {
    Write-Warning "No results found."
    exit 0
}

$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $OutputDir "SharePermissions_$timestamp.csv"

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "`nExported $($results.Count) ACE(s) across all shares -> $outputFile" -ForegroundColor Green

$results | Format-Table Server, ShareName, AccountName, AccessControlType, AccessRight -AutoSize