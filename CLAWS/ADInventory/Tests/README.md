# AD Inventory Tests

This directory contains unit and integration tests for the SSNC.ADInventory module.

## Prerequisites

```powershell
# Install Pester (PowerShell testing framework)
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck

# Verify installation
Get-Module -Name Pester -ListAvailable
```

## Running Tests

### Run All Tests
```powershell
# From the ADInventory directory
Invoke-Pester -Path .\Tests\

# With detailed output
Invoke-Pester -Path .\Tests\ -Output Detailed
```

### Run Unit Tests Only
```powershell
Invoke-Pester -Path .\Tests\Unit\
```

### Run Specific Test File
```powershell
Invoke-Pester -Path .\Tests\Unit\Transform.Tests.ps1
```

### Run with Code Coverage
```powershell
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = ".\Private\Transform\*.ps1"
$config.Run.Path = ".\Tests\Unit\Transform.Tests.ps1"
Invoke-Pester -Configuration $config
```

## Test Structure

### Unit Tests (`./Unit/`)
- Test individual functions in isolation
- No external dependencies (AD, database)
- Fast execution
- High code coverage target (80%+)

**Current Tests:**
- `Transform.Tests.ps1` - Data conversion functions (SID, GUID, DateTime)

**Planned:**
- `Utility.Tests.ps1` - Logging and property access functions
- `SQLite.Tests.ps1` - Database operations (mocked)

### Integration Tests (`./Integration/`)
- Test components working together
- May require test AD environment
- Slower execution
- Validates end-to-end scenarios

**Planned:**
- `ADConnection.Tests.ps1` - AD connectivity (requires test domain)
- `LDAPQuery.Tests.ps1` - LDAP query operations
- `FullInventory.Tests.ps1` - Complete inventory workflow

## Writing New Tests

### Test Template
```powershell
#Requires -Modules Pester

BeforeAll {
    # Import functions to test
    . "$PSScriptRoot/../../Private/YourCategory/YourFunction.ps1"
    . "$PSScriptRoot/../../Private/Utility/Write-ADInventoryLog.ps1"  # If needed
}

Describe "YourFunction" {
    Context "Valid Inputs" {
        It "Does what it should" {
            $result = YourFunction -Parameter "value"
            $result | Should -Be "expected"
        }
    }

    Context "Invalid Inputs" {
        It "Handles errors gracefully" {
            { YourFunction -Parameter $null } | Should -Throw
        }
    }
}
```

### Best Practices

1. **Arrange-Act-Assert Pattern**
   ```powershell
   It "Converts SID correctly" {
       # Arrange
       $sidBytes = @(1, 2, 0, 0, ...)

       # Act
       $result = ConvertTo-SidString -Value $sidBytes

       # Assert
       $result | Should -Be "S-1-5-32-544"
   }
   ```

2. **Test Edge Cases**
   - Null inputs
   - Empty strings/arrays
   - Invalid formats
   - Boundary values

3. **Use Descriptive Test Names**
   - Good: `It "Returns null for invalid byte array length"`
   - Bad: `It "Test 1"`

4. **Mock External Dependencies**
   ```powershell
   BeforeAll {
       Mock Invoke-SqliteQuery { return @() }
   }
   ```

5. **Clean Up After Tests**
   ```powershell
   AfterEach {
       # Clean up test files, connections, etc.
   }
   ```

## Continuous Integration

Tests should run automatically on:
- Pull request creation
- Commits to feature branches
- Before merging to main

**Target Metrics:**
- Unit test coverage: ≥ 80%
- All tests pass: 100%
- No skipped tests in CI

## Test Data

For tests requiring AD data:
- Use mock objects (preferred for unit tests)
- Use test domain with known data (for integration tests)
- Never use production data

## Troubleshooting

### Tests not found
```powershell
# Ensure you're in the correct directory
Get-Location
# Should be: .../ADInventory/
```

### Import errors
```powershell
# Check function file paths in BeforeAll
Test-Path "$PSScriptRoot/../../Private/Transform/ConvertTo-SidString.ps1"
```

### Pester version issues
```powershell
# Uninstall old Pester versions
Get-Module Pester -ListAvailable | Uninstall-Module -Force
# Install Pester 5.x
Install-Module -Name Pester -MinimumVersion 5.0 -Force
```

## References

- [Pester Documentation](https://pester.dev/)
- [PowerShell Testing Best Practices](https://pester.dev/docs/usage/mocking)
- [Test-Driven Development](https://en.wikipedia.org/wiki/Test-driven_development)

---

**Last Updated:** 2025-12-01
**Test Framework:** Pester 5.x+
**Coverage Goal:** 80%+
