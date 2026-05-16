function ConvertTo-SidString {
    <#
    .SYNOPSIS
        Converts byte array or object to SID string representation

    .DESCRIPTION
        Safely converts various SID representations to string format.
        Handles byte arrays, SecurityIdentifier objects, and string inputs.
        Returns null for invalid or empty inputs.

    .PARAMETER Value
        The value to convert. Can be:
        - byte[] (binary SID)
        - System.Security.Principal.SecurityIdentifier object
        - string (returns as-is if valid)
        - null (returns null)

    .OUTPUTS
        System.String
        Returns SID in string format (e.g., "S-1-5-21-...") or $null if conversion fails

    .EXAMPLE
        ConvertTo-SidString -Value $bytes
        Converts byte array to SID string

    .EXAMPLE
        ConvertTo-SidString -Value $sidObject
        Converts SecurityIdentifier object to string

    .NOTES
        Part of SSNC.ADInventory module
        Replaces: Convert-ByteToSidString from original script
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$Value
    )

    process {
        if ($null -eq $Value) {
            return $null
        }

        try {
            if ($Value -is [byte[]]) {
                $sid = New-Object System.Security.Principal.SecurityIdentifier($Value, 0)
                return $sid.Value
            }
            elseif ($Value -is [System.Security.Principal.SecurityIdentifier]) {
                return $Value.Value
            }
            elseif ($Value -is [string]) {
                # Validate it's a proper SID string format
                if ($Value -match '^S-\d+-\d+') {
                    return $Value
                }
                else {
                    Write-Warning "Invalid SID string format: $Value"
                    return $null
                }
            }
            else {
                Write-Warning "Unsupported SID input type: $($Value.GetType().FullName)"
                return $null
            }
        }
        catch {
            Write-Verbose "Failed to convert value to SID string: $_"
            return $null
        }
    }
}
