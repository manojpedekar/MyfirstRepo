#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for Transform helper functions

.DESCRIPTION
    Pester tests for AD Inventory data transformation functions.
    Tests conversion functions for SIDs, GUIDs, and timestamps.

.NOTES
    Run with: Invoke-Pester -Path .\Transform.Tests.ps1
    Requires: Pester 5.0+
#>

BeforeAll {
    # Import functions to test
    $transformPath = Join-Path $PSScriptRoot "../../Private/Transform"

    . (Join-Path $transformPath "ConvertTo-SidString.ps1")
    . (Join-Path $transformPath "ConvertTo-SidBytes.ps1")
    . (Join-Path $transformPath "ConvertTo-GuidString.ps1")
    . (Join-Path $transformPath "ConvertTo-DateTimeFromFileTime.ps1")

    # Import logging dependency
    . (Join-Path $PSScriptRoot "../../Private/Utility/Write-ADInventoryLog.ps1")
}

Describe "ConvertTo-SidString" {
    Context "Valid Inputs" {
        It "Converts byte array to SID string" {
            # S-1-5-32-544 (Administrators)
            $bytes = @(1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0, 0)
            $result = ConvertTo-SidString -Value $bytes
            $result | Should -Be "S-1-5-32-544"
        }

        It "Returns string input as-is for valid SID format" {
            $sid = "S-1-5-21-123456789-987654321-111111111-1001"
            $result = ConvertTo-SidString -Value $sid
            $result | Should -Be $sid
        }

        It "Converts SecurityIdentifier object to string" {
            $sidObj = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            $result = ConvertTo-SidString -Value $sidObj
            $result | Should -Be "S-1-5-32-544"
        }

        It "Works with pipeline input" {
            $sidString = "S-1-5-18"
            $result = $sidString | ConvertTo-SidString
            $result | Should -Be "S-1-5-18"
        }
    }

    Context "Invalid Inputs" {
        It "Returns null for null input" {
            $result = ConvertTo-SidString -Value $null
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for invalid string format" {
            $result = ConvertTo-SidString -Value "not-a-sid" -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for invalid byte array" {
            $invalidBytes = @(1, 2, 3)  # Too short
            $result = ConvertTo-SidString -Value $invalidBytes
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "ConvertTo-SidBytes" {
    Context "Valid Inputs" {
        It "Converts SID string to byte array" {
            $sidString = "S-1-5-32-544"
            $result = ConvertTo-SidBytes -SidString $sidString
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [byte[]]
            $result[0] | Should -Be 1  # Revision
        }

        It "Converts well-known SID correctly" {
            $sidString = "S-1-5-18"  # Local System
            $result = ConvertTo-SidBytes -SidString $sidString
            # Convert back to verify
            $sid = New-Object System.Security.Principal.SecurityIdentifier($result, 0)
            $sid.Value | Should -Be $sidString
        }

        It "Works with pipeline input" {
            $result = "S-1-5-32-544" | ConvertTo-SidBytes
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [byte[]]
        }
    }

    Context "Invalid Inputs" {
        It "Returns null for empty string" {
            $result = ConvertTo-SidBytes -SidString "" -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for whitespace string" {
            $result = ConvertTo-SidBytes -SidString "   " -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for invalid SID format" {
            $result = ConvertTo-SidBytes -SidString "invalid-sid" -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Round-trip Conversion" {
        It "SID string -> bytes -> string produces same result" {
            $original = "S-1-5-21-1234567890-1234567890-1234567890-1000"
            $bytes = ConvertTo-SidBytes -SidString $original
            $result = ConvertTo-SidString -Value $bytes
            $result | Should -Be $original
        }
    }
}

Describe "ConvertTo-GuidString" {
    Context "Valid Inputs" {
        It "Converts byte array to GUID string" {
            $guid = [Guid]::NewGuid()
            $bytes = $guid.ToByteArray()
            $result = ConvertTo-GuidString -Value $bytes
            $result | Should -Be $guid.ToString()
        }

        It "Converts Guid object to string" {
            $guid = [Guid]::NewGuid()
            $result = ConvertTo-GuidString -Value $guid
            $result | Should -Be $guid.ToString()
        }

        It "Parses and normalizes GUID string" {
            $guidString = "{12345678-1234-1234-1234-123456789012}"
            $result = ConvertTo-GuidString -Value $guidString
            # Should be normalized without braces
            $result | Should -Match "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        }

        It "Works with pipeline input" {
            $guid = [Guid]::NewGuid()
            $result = $guid | ConvertTo-GuidString
            $result | Should -Be $guid.ToString()
        }
    }

    Context "Invalid Inputs" {
        It "Returns null for null input" {
            $result = ConvertTo-GuidString -Value $null
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for invalid byte array length" {
            $invalidBytes = @(1, 2, 3, 4)  # Not 16 bytes
            $result = ConvertTo-GuidString -Value $invalidBytes -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for invalid string format" {
            $result = ConvertTo-GuidString -Value "not-a-guid"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Round-trip Conversion" {
        It "GUID -> bytes -> string produces same result" {
            $original = [Guid]::NewGuid()
            $bytes = $original.ToByteArray()
            $result = ConvertTo-GuidString -Value $bytes
            $result | Should -Be $original.ToString()
        }
    }
}

Describe "ConvertTo-DateTimeFromFileTime" {
    Context "Valid Inputs" {
        It "Converts int64 file time to DateTime" {
            # 2025-01-01 00:00:00 UTC
            $fileTime = [DateTime]::Parse("2025-01-01").ToFileTimeUtc()
            $result = ConvertTo-DateTimeFromFileTime -Value $fileTime
            $result | Should -Not -BeNullOrEmpty
            $result.Year | Should -Be 2025
            $result.Month | Should -Be 1
            $result.Day | Should -Be 1
        }

        It "Converts string representation of int64" {
            $fileTime = [DateTime]::Parse("2025-01-01").ToFileTimeUtc()
            $result = ConvertTo-DateTimeFromFileTime -Value $fileTime.ToString()
            $result | Should -Not -BeNullOrEmpty
            $result.Year | Should -Be 2025
        }

        It "Returns DateTime in UTC" {
            $fileTime = [DateTime]::Parse("2025-01-01").ToFileTimeUtc()
            $result = ConvertTo-DateTimeFromFileTime -Value $fileTime
            $result.Kind | Should -Be ([DateTimeKind]::Utc)
        }

        It "Works with pipeline input" {
            $fileTime = [DateTime]::Parse("2025-01-01").ToFileTimeUtc()
            $result = $fileTime | ConvertTo-DateTimeFromFileTime
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Invalid/Special Inputs" {
        It "Returns null for zero value" {
            $result = ConvertTo-DateTimeFromFileTime -Value 0
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for negative value" {
            $result = ConvertTo-DateTimeFromFileTime -Value -1
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for null input" {
            $result = ConvertTo-DateTimeFromFileTime -Value $null
            $result | Should -BeNullOrEmpty
        }

        It "Returns null for non-numeric string" {
            $result = ConvertTo-DateTimeFromFileTime -Value "not-a-number"
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Mock IADsLargeInteger" {
        It "Converts COM LargeInteger object" {
            # Create mock object with HighPart and LowPart
            $fileTime = [DateTime]::Parse("2025-01-01").ToFileTimeUtc()
            $high = [int64]($fileTime -shr 32)
            $low = [uint32]($fileTime -band 0xFFFFFFFF)

            $mockObj = [PSCustomObject]@{
                HighPart = $high
                LowPart = $low
            }

            $result = ConvertTo-DateTimeFromFileTime -Value $mockObj
            $result | Should -Not -BeNullOrEmpty
            $result.Year | Should -Be 2025
        }
    }
}
