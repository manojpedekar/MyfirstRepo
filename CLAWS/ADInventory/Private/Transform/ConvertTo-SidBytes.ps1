function ConvertTo-SidBytes {
    <#
    .SYNOPSIS
        Converts SID string to byte array representation

    .DESCRIPTION
        Converts a SID string (e.g., "S-1-5-21-...") to its binary byte array format
        suitable for storage in databases or comparison with AD byte[] properties.
        Returns null for invalid or empty inputs.

    .PARAMETER SidString
        The SID in string format (e.g., "S-1-5-21-123-456-789-1001")

    .OUTPUTS
        System.Byte[]
        Returns SID as byte array or $null if conversion fails

    .EXAMPLE
        ConvertTo-SidBytes -SidString "S-1-5-21-123-456-789-1001"
        Converts SID string to byte array

    .EXAMPLE
        "S-1-5-32-544" | ConvertTo-SidBytes
        Converts built-in Administrator group SID using pipeline

    .NOTES
        Part of SSNC.ADInventory module
        Replaces: Convert-SidStringToBytes from original script
        Fixed: Added proper error logging instead of silent failures
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [AllowEmptyString()]
        [string]$SidString
    )

    process {
        if ([string]::IsNullOrWhiteSpace($SidString)) {
            Write-Verbose "SID string is null or empty"
            return $null
        }

        try {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($SidString)
            $bytes = New-Object byte[] $sid.BinaryLength
            $sid.GetBinaryForm($bytes, 0)
            return $bytes
        }
        catch {
            Write-Warning "Failed to convert SID '$SidString' to bytes: $_"
            return $null
        }
    }
}
