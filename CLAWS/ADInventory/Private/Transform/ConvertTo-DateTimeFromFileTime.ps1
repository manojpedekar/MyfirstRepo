function ConvertTo-DateTimeFromAD {
    <#
    .SYNOPSIS
        Converts AD timestamp attributes (whenCreated, whenChanged) to DateTime

    .DESCRIPTION
        Handles the various formats that AD timestamp attributes can be returned as:
        - DateTime objects (pass through)
        - Generalized Time strings (format: YYYYMMDDHHmmss.0Z)
        - String representations that can be parsed

        Note: This is different from file time attributes (lastLogonTimestamp,
        accountExpires) which use ConvertTo-DateTimeFromFileTime.

    .PARAMETER Value
        The timestamp value from AD. Can be:
        - [DateTime] object (returned as-is in UTC)
        - [string] in Generalized Time format (YYYYMMDDHHmmss.0Z)
        - null (returns null)

    .OUTPUTS
        System.DateTime
        Returns DateTime in UTC or $null if conversion fails

    .EXAMPLE
        ConvertTo-DateTimeFromAD -Value $result.Properties['whenCreated'][0]
        Converts whenCreated attribute to DateTime

    .NOTES
        Part of SSNC.ADInventory module
        Use for: whenCreated, whenChanged
        Do NOT use for: lastLogonTimestamp, accountExpires, pwdLastSet (use ConvertTo-DateTimeFromFileTime)
    #>
    [CmdletBinding()]
    [OutputType([DateTime])]
    param(
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [AllowNull()]
        [object]$Value
    )

    process {
        if ($null -eq $Value) {
            return $null
        }

        try {
            # Already a DateTime - convert to UTC if needed
            if ($Value -is [DateTime]) {
                if ($Value.Kind -eq [DateTimeKind]::Utc) {
                    return $Value
                }
                return $Value.ToUniversalTime()
            }

            # String - try to parse as Generalized Time or standard format
            if ($Value -is [string]) {
                # Generalized Time format: YYYYMMDDHHmmss.0Z
                if ($Value -match '^\d{14}') {
                    $year = [int]$Value.Substring(0, 4)
                    $month = [int]$Value.Substring(4, 2)
                    $day = [int]$Value.Substring(6, 2)
                    $hour = [int]$Value.Substring(8, 2)
                    $minute = [int]$Value.Substring(10, 2)
                    $second = [int]$Value.Substring(12, 2)
                    return [DateTime]::new($year, $month, $day, $hour, $minute, $second, [DateTimeKind]::Utc)
                }

                # Try standard DateTime parsing
                $parsed = [DateTime]::MinValue
                if ([DateTime]::TryParse($Value, [ref]$parsed)) {
                    return $parsed.ToUniversalTime()
                }

                Write-Verbose "Unable to parse string as DateTime: $Value"
                return $null
            }

            Write-Verbose "Unexpected type for DateTime conversion: $($Value.GetType().FullName)"
            return $null
        }
        catch {
            Write-Verbose "Failed to convert value to DateTime: $_"
            return $null
        }
    }
}

function ConvertTo-DateTimeFromLargeInteger {
    <#
    .SYNOPSIS
        Fast-path conversion of IADsLargeInteger to DateTime

    .DESCRIPTION
        Optimized function for converting IADsLargeInteger COM objects
        (the native format returned by LDAP for timestamp attributes)
        directly to DateTime without type-checking overhead.

        Use this function in hot paths where you know the input is
        an IADsLargeInteger (e.g., bulk AD object processing).

    .PARAMETER LargeInt
        The IADsLargeInteger COM object from AD attributes like
        accountExpires, lastLogonTimestamp, pwdLastSet, etc.

    .OUTPUTS
        System.DateTime
        Returns DateTime in UTC or $null if value is 0/negative or AD "never expires" sentinel

    .EXAMPLE
        ConvertTo-DateTimeFromLargeInteger -LargeInt $entry.Properties['lastLogonTimestamp'][0]
        Direct conversion of LDAP timestamp attribute

    .NOTES
        Part of SSNC.ADInventory module
        For general-purpose conversion with type detection, use ConvertTo-DateTimeFromFileTime
    #>
    [CmdletBinding()]
    [OutputType([DateTime])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$LargeInt
    )

    $fileTime = ([int64]$LargeInt.HighPart -shl 32) -bor [uint32]$LargeInt.LowPart
    # Return null for "never set" (0/negative) or AD "never expires" sentinel (0x7FFFFFFFFFFFFFFF)
    if ($fileTime -le 0 -or $fileTime -eq [Int64]::MaxValue) { return $null }
    [DateTime]::FromFileTimeUtc($fileTime)
}

function ConvertTo-DateTimeFromFileTime {
    <#
    .SYNOPSIS
        Converts Windows file time (LargeInteger or Int64) to DateTime object

    .DESCRIPTION
        Safely converts AD timestamp values to DateTime objects.
        Handles various input types including:
        - IADsLargeInteger COM objects (from AD attributes like accountExpires, lastLogonTimestamp)
        - Int64 values
        - String representations of Int64

        Returns null for invalid, zero, or negative values.

        For bulk processing where input is known to be IADsLargeInteger,
        use ConvertTo-DateTimeFromLargeInteger for better performance.

    .PARAMETER Value
        The file time value to convert. Can be:
        - IADsLargeInteger COM object (from AD)
        - [int64] value
        - [string] containing numeric value
        - null (returns null)

    .OUTPUTS
        System.DateTime
        Returns DateTime in UTC or $null if conversion fails or value is 0/negative

    .EXAMPLE
        ConvertTo-DateTimeFromFileTime -Value $lastLogonTimestamp
        Converts lastLogonTimestamp from AD to DateTime

    .EXAMPLE
        $accountExpires | ConvertTo-DateTimeFromFileTime
        Pipeline conversion of accountExpires attribute

    .NOTES
        Part of SSNC.ADInventory module
        Replaces: Convert-LargeIntToDate from original script

        Special handling:
        - Values <= 0 return null (never set or not applicable)
        - The AD "never expires" sentinel (0x7FFFFFFFFFFFFFFF / Int64.MaxValue) returns null
        - COM IADsLargeInteger is converted via HighPart/LowPart
        - Result is always in UTC
    #>
    [CmdletBinding()]
    [OutputType([DateTime])]
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
            [int64]$fileTime = 0

            if ($Value -is [int64]) {
                $fileTime = $Value
            }
            elseif ($Value -is [string]) {
                # Handle string representation of numeric value
                if (-not [int64]::TryParse($Value, [ref]$fileTime)) {
                    Write-Verbose "Unable to parse string as int64: $Value"
                    return $null
                }
            }
            else {
                # IADsLargeInteger COM object - use fast-path logic inline
                # These have HighPart (signed 32-bit) and LowPart (unsigned 32-bit)
                try {
                    $fileTime = ([int64]$Value.HighPart -shl 32) -bor [uint32]$Value.LowPart
                }
                catch {
                    Write-Warning "Unable to extract HighPart/LowPart from value: $_"
                    return $null
                }
            }

            # File time values <= 0 indicate "never" or "not set"
            # 0x7FFFFFFFFFFFFFFF (Int64.MaxValue) is the AD "never expires" sentinel for accountExpires
            # and can appear in other timestamp fields - handle it explicitly rather than via exception
            if ($fileTime -le 0 -or $fileTime -eq [Int64]::MaxValue) {
                return $null
            }

            # Convert Windows file time (100-nanosecond intervals since 1601-01-01) to DateTime
            return [DateTime]::FromFileTimeUtc($fileTime)
        }
        catch {
            Write-Verbose "Failed to convert value to DateTime: $_"
            return $null
        }
    }
}
