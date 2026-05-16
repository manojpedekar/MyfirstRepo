#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for advanced features (Phase 5)

.DESCRIPTION
    Pester tests for advanced features including:
    - Large multi-valued attribute retrieval
    - Foreign Security Principal collection
    - Checkpoint save/restore
    - Parallel domain collection

.NOTES
    Run with: Invoke-Pester -Path .\ADAdvancedFeatures.Tests.ps1
    Requires: Pester 5.0+
#>

BeforeAll {
    # Import classes
    $classPath = Join-Path $PSScriptRoot "../../Classes"
    . (Join-Path $classPath "ADQueryConfig.ps1")

    # Import functions to test
    $utilityPath = Join-Path $PSScriptRoot "../../Private/Utility"
    $ldapPath = Join-Path $PSScriptRoot "../../Private/LDAP"

    . (Join-Path $utilityPath "Write-ADInventoryLog.ps1")
    . (Join-Path $utilityPath "Checkpoint-ADInventory.ps1")
    . (Join-Path $ldapPath "Get-LargeMultiValuedAttribute.ps1")
    . (Join-Path $ldapPath "Get-ForeignSecurityPrincipal.ps1")
}

Describe "Checkpoint-ADInventory" {
    Context "Save-ADInventoryCheckpoint" {
        BeforeEach {
            $testOutputPath = Join-Path $TestDrive "CheckpointTests"
            New-Item -Path $testOutputPath -ItemType Directory -Force | Out-Null
            $testInventoryID = [guid]::NewGuid()
        }

        It "Creates checkpoint file successfully" {
            $completedDomains = @('contoso.com', 'fabrikam.com')
            $statistics = @{
                DomainsProcessed = 2
                UsersCollected = 1000
                GroupsCollected = 500
            }
            $metadata = @{
                TotalDomains = 3
                StartTime = Get-Date
            }

            $checkpointPath = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains $completedDomains `
                -Statistics $statistics `
                -Metadata $metadata

            $checkpointPath | Should -Not -BeNullOrEmpty
            Test-Path $checkpointPath | Should -Be $true
        }

        It "Checkpoint file contains correct data" {
            $completedDomains = @('contoso.com')
            $statistics = @{ DomainsProcessed = 1 }
            $metadata = @{ TotalDomains = 2 }

            $checkpointPath = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains $completedDomains `
                -Statistics $statistics `
                -Metadata $metadata

            # Read and verify content
            $content = Get-Content $checkpointPath -Raw | ConvertFrom-Json
            $content.InventoryID | Should -Be $testInventoryID.ToString()
            $content.CheckpointVersion | Should -Be "1.0"
            $content.CompletedDomains.Count | Should -Be 1
            $content.CompletedDomains[0] | Should -Be 'contoso.com'
        }

        It "Handles empty completed domains array" {
            $checkpointPath = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @() `
                -Statistics @{} `
                -Metadata @{}

            $checkpointPath | Should -Not -BeNullOrEmpty
            Test-Path $checkpointPath | Should -Be $true

            $content = Get-Content $checkpointPath -Raw | ConvertFrom-Json
            $content.CompletedDomains.Count | Should -Be 0
        }

        It "Overwrites existing checkpoint" {
            # First save
            $checkpointPath1 = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @('domain1.com') `
                -Statistics @{ DomainsProcessed = 1 } `
                -Metadata @{}

            Start-Sleep -Milliseconds 100

            # Second save (should overwrite)
            $checkpointPath2 = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @('domain1.com', 'domain2.com') `
                -Statistics @{ DomainsProcessed = 2 } `
                -Metadata @{}

            $checkpointPath1 | Should -Be $checkpointPath2

            $content = Get-Content $checkpointPath2 -Raw | ConvertFrom-Json
            $content.CompletedDomains.Count | Should -Be 2
            $content.Statistics.DomainsProcessed | Should -Be 2
        }
    }

    Context "Get-ADInventoryCheckpoint" {
        BeforeEach {
            $testOutputPath = Join-Path $TestDrive "CheckpointTests"
            New-Item -Path $testOutputPath -ItemType Directory -Force | Out-Null
            $testInventoryID = [guid]::NewGuid()
        }

        It "Loads existing checkpoint successfully" {
            # Create checkpoint
            $completedDomains = @('contoso.com', 'fabrikam.com')
            $statistics = @{
                DomainsProcessed = 2
                UsersCollected = 1000
            }

            Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains $completedDomains `
                -Statistics $statistics `
                -Metadata @{} | Out-Null

            # Load checkpoint
            $checkpoint = Get-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath

            $checkpoint | Should -Not -BeNullOrEmpty
            $checkpoint.InventoryID | Should -Be $testInventoryID
            $checkpoint.CompletedDomains.Count | Should -Be 2
            $checkpoint.Statistics.DomainsProcessed | Should -Be 2
            $checkpoint.Statistics.UsersCollected | Should -Be 1000
        }

        It "Returns null if checkpoint doesn't exist" {
            $nonExistentID = [guid]::NewGuid()

            $checkpoint = Get-ADInventoryCheckpoint `
                -InventoryID $nonExistentID `
                -OutputPath $testOutputPath

            $checkpoint | Should -BeNullOrEmpty
        }

        It "Loads checkpoint by path" {
            # Create checkpoint
            $checkpointPath = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @('test.com') `
                -Statistics @{} `
                -Metadata @{}

            # Load by path
            $checkpoint = Get-ADInventoryCheckpoint -CheckpointPath $checkpointPath

            $checkpoint | Should -Not -BeNullOrEmpty
            $checkpoint.InventoryID | Should -Be $testInventoryID
        }
    }

    Context "Test-ADInventoryCheckpoint" {
        BeforeEach {
            $testOutputPath = Join-Path $TestDrive "CheckpointTests"
            New-Item -Path $testOutputPath -ItemType Directory -Force | Out-Null
            $testInventoryID = [guid]::NewGuid()
        }

        It "Returns true when checkpoint exists" {
            Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @() `
                -Statistics @{} `
                -Metadata @{} | Out-Null

            $exists = Test-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath

            $exists | Should -Be $true
        }

        It "Returns false when checkpoint doesn't exist" {
            $nonExistentID = [guid]::NewGuid()

            $exists = Test-ADInventoryCheckpoint `
                -InventoryID $nonExistentID `
                -OutputPath $testOutputPath

            $exists | Should -Be $false
        }
    }

    Context "Remove-ADInventoryCheckpoint" {
        BeforeEach {
            $testOutputPath = Join-Path $TestDrive "CheckpointTests"
            New-Item -Path $testOutputPath -ItemType Directory -Force | Out-Null
            $testInventoryID = [guid]::NewGuid()
        }

        It "Removes existing checkpoint" {
            # Create checkpoint
            $checkpointPath = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @() `
                -Statistics @{} `
                -Metadata @{}

            Test-Path $checkpointPath | Should -Be $true

            # Remove checkpoint
            Remove-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath

            Test-Path $checkpointPath | Should -Be $false
        }

        It "Doesn't throw when checkpoint doesn't exist" {
            $nonExistentID = [guid]::NewGuid()

            {
                Remove-ADInventoryCheckpoint `
                    -InventoryID $nonExistentID `
                    -OutputPath $testOutputPath
            } | Should -Not -Throw
        }

        It "Removes checkpoint by path" {
            $checkpointPath = Save-ADInventoryCheckpoint `
                -InventoryID $testInventoryID `
                -OutputPath $testOutputPath `
                -CompletedDomains @() `
                -Statistics @{} `
                -Metadata @{}

            Remove-ADInventoryCheckpoint -CheckpointPath $checkpointPath

            Test-Path $checkpointPath | Should -Be $false
        }
    }
}

Describe "Get-LargeMultiValuedAttribute" {
    Context "Input Validation" {
        It "Requires DistinguishedName parameter" {
            { Get-LargeMultiValuedAttribute -AttributeName "member" -Server "dc01.contoso.com" } | Should -Throw
        }

        It "Requires AttributeName parameter" {
            { Get-LargeMultiValuedAttribute -DistinguishedName "CN=Test,DC=contoso,DC=com" -Server "dc01.contoso.com" } | Should -Throw
        }

        It "Requires Server parameter" {
            { Get-LargeMultiValuedAttribute -DistinguishedName "CN=Test,DC=contoso,DC=com" -AttributeName "member" } | Should -Throw
        }

        It "Accepts valid parameters" {
            # This will fail to connect but should not throw on parameter validation
            $config = [ADQueryConfig]::new()

            # Mock the error - function should return empty array on connection failure
            $result = Get-LargeMultiValuedAttribute `
                -DistinguishedName "CN=NonExistent,DC=test,DC=local" `
                -AttributeName "member" `
                -Server "nonexistent.local" `
                -Config $config `
                -ErrorAction SilentlyContinue

            # Should return empty array, not throw
            $result | Should -BeOfType [array]
        }
    }

    Context "Return Values" {
        It "Returns array type" {
            $config = [ADQueryConfig]::new()

            $result = Get-LargeMultiValuedAttribute `
                -DistinguishedName "CN=Test,DC=test,DC=local" `
                -AttributeName "member" `
                -Server "nonexistent.local" `
                -Config $config `
                -ErrorAction SilentlyContinue

            $result | Should -BeOfType [array]
        }

        It "Returns empty array on object not found" {
            $config = [ADQueryConfig]::new()

            $result = Get-LargeMultiValuedAttribute `
                -DistinguishedName "CN=NonExistent,DC=test,DC=local" `
                -AttributeName "member" `
                -Server "nonexistent.local" `
                -Config $config `
                -ErrorAction SilentlyContinue

            $result.Count | Should -Be 0
        }
    }
}

Describe "Get-ForeignSecurityPrincipal" {
    Context "Input Validation" {
        It "Requires Server parameter" {
            { Get-ForeignSecurityPrincipal -DomainName "contoso.com" } | Should -Throw
        }

        It "Requires DomainName parameter" {
            { Get-ForeignSecurityPrincipal -Server "dc01.contoso.com" } | Should -Throw
        }

        It "Accepts valid parameters" {
            $config = [ADQueryConfig]::new()

            # This will fail to connect but should not throw on parameter validation
            $result = Get-ForeignSecurityPrincipal `
                -Server "nonexistent.local" `
                -DomainName "test.local" `
                -Config $config `
                -ErrorAction SilentlyContinue

            # Should return empty array, not throw
            $result | Should -BeOfType [array]
        }
    }

    Context "Return Values" {
        It "Returns array type" {
            $config = [ADQueryConfig]::new()

            $result = Get-ForeignSecurityPrincipal `
                -Server "nonexistent.local" `
                -DomainName "test.local" `
                -Config $config `
                -ErrorAction SilentlyContinue

            $result | Should -BeOfType [array]
        }

        It "Returns empty array when FSP container doesn't exist" {
            $config = [ADQueryConfig]::new()

            $result = Get-ForeignSecurityPrincipal `
                -Server "nonexistent.local" `
                -DomainName "test.local" `
                -Config $config `
                -ErrorAction SilentlyContinue

            $result.Count | Should -Be 0
        }

        It "Accepts ResolveForeignDomain switch" {
            $config = [ADQueryConfig]::new()

            {
                Get-ForeignSecurityPrincipal `
                    -Server "nonexistent.local" `
                    -DomainName "test.local" `
                    -Config $config `
                    -ResolveForeignDomain `
                    -ErrorAction SilentlyContinue
            } | Should -Not -Throw
        }

        It "Accepts TrustMap parameter" {
            $config = [ADQueryConfig]::new()
            $trustMap = @{
                'S-1-5-21-1234567890-1234567890-1234567890' = 'trusted.com'
            }

            {
                Get-ForeignSecurityPrincipal `
                    -Server "nonexistent.local" `
                    -DomainName "test.local" `
                    -Config $config `
                    -ResolveForeignDomain `
                    -TrustMap $trustMap `
                    -ErrorAction SilentlyContinue
            } | Should -Not -Throw
        }
    }
}

Describe "Advanced Features Integration" {
    Context "ADQueryConfig with Advanced Features" {
        It "Config object serializes for parallel processing" {
            $config = [ADQueryConfig]::new()
            $config.PageSize = 500
            $config.ServerTimeoutMinutes = 5

            # Test that config can be converted to/from hashtable (for parallel passing)
            $summary = $config.GetSummary()

            $summary | Should -BeOfType [hashtable]
            $summary.PageSize | Should -Be 500
            $summary.ServerTimeout | Should -Be "5m"
        }

        It "Config cloning works for parallel scenarios" {
            $config = [ADQueryConfig]::new()
            $config.PageSize = 750
            $config.BatchSize = 5000

            $clone = $config.Clone()

            # Verify clone is independent
            $clone.PageSize | Should -Be 750
            $config.PageSize = 1000
            $clone.PageSize | Should -Be 750
        }
    }
}
