function ConvertTo-GuidString {
    <#
    .SYNOPSIS
        Converts byte array or object to GUID string representation

    .DESCRIPTION
        Safely converts various GUID representations to string format.
        Handles byte arrays, Guid objects, and string inputs.
        Returns null for invalid or empty inputs.

    .PARAMETER Value
        The value to convert. Can be:
        - byte[] (16-byte binary GUID)
        - System.Guid object
        - string (parsed and validated)
        - null (returns null)

    .OUTPUTS
        System.String
        Returns GUID in string format (e.g., "a1b2c3d4-e5f6-...") or $null if conversion fails

    .EXAMPLE
        ConvertTo-GuidString -Value $bytes
        Converts 16-byte array to GUID string

    .EXAMPLE
        ConvertTo-GuidString -Value $guidObject
        Converts Guid object to string

    .EXAMPLE
        $objectGuid | ConvertTo-GuidString
        Pipeline conversion of AD objectGuid attribute

    .NOTES
        Part of SSNC.ADInventory module
        Replaces: Convert-ByteToGuidString from original script
        Fixed: Better type checking and error reporting
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            Position = 0
        )]
        [AllowNull()]
        [object]$Value
    )

    process {
        if ($null -eq $Value) {
            return $null
        }

        try {
            if ($Value -is [byte[]]) {
                if ($Value.Length -ne 16) {
                    Write-Warning "Invalid GUID byte array length: $($Value.Length) (expected 16)"
                    return $null
                }
                return ([Guid]$Value).ToString()
            }
            elseif ($Value -is [Guid]) {
                return $Value.ToString()
            }
            elseif ($Value -is [string]) {
                # Validate and normalize GUID string format
                $guid = [Guid]::Parse($Value)
                return $guid.ToString()
            }
            else {
                Write-Warning "Unsupported GUID input type: $($Value.GetType().FullName)"
                return $null
            }
        }
        catch {
            Write-Verbose "Failed to convert value to GUID string: $_"
            return $null
        }
    }
}
