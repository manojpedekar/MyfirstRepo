# ==============================
# CONFIG
# ==============================
$RootPath  = "G:\Group"
$OutputCsv = "C:\temp\Varx_Recurse_NTFS_Permissions.csv"

# Identities to exclude
$ExcludedIdentities = @(
    "NT AUTHORITY\SYSTEM",
    "BUILTIN\Administrators",
    "BUILTIN\Users",
    "NT AUTHORITY\SERVICE"
)

# Ensure output directory exists
$OutDir = Split-Path $OutputCsv
if (!(Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

Write-Host "Starting NTFS permission export (explicit + inherited where applicable)..."

# ==============================
# EXPORT NTFS PERMISSIONS
# ==============================
Get-ChildItem -Path $RootPath -Recurse -Directory -Force -ErrorAction SilentlyContinue |
ForEach-Object {

    $path = $_.FullName

    try {
        $acl = Get-Acl -Path $path

        # Check if folder has ANY explicit permission
        $hasExplicit = $acl.Access | Where-Object { -not $_.IsInherited }

        if ($hasExplicit) {

            foreach ($entry in $acl.Access |
                     Where-Object {
                         $ExcludedIdentities -notcontains $_.IdentityReference.Value
                     }) {

                [PSCustomObject]@{
                    Path       = $path
                    Identity   = $entry.IdentityReference.Value
                    AccessType = $entry.AccessControlType
                    Rights     = $entry.FileSystemRights
                    Inherited  = $entry.IsInherited
                }
            }
        }
    }
    catch {
        Write-Warning "Access denied: $path"
    }
} | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Export completed:"
Write-Host $OutputCsv
