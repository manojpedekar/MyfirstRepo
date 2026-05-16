#Requires -Modules Pester

<#
.SYNOPSIS
    Unit tests for AD configuration and domain enumeration

.DESCRIPTION
    Pester tests for ADQueryConfig class and domain/trust enumeration functions.

.NOTES
    Run with: Invoke-Pester -Path .\ADConfiguration.Tests.ps1
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
    . (Join-Path $ldapPath "ConvertTo-SafeLdapFilter.ps1")
}

Describe "ADQueryConfig" {
    Context "Construction" {
        It "Creates with default values" {
            $config = [ADQueryConfig]::new()

            $config.PageSize | Should -Be 1000
            $config.ServerTimeoutMinutes | Should -Be 10
            $config.ClientTimeoutMinutes | Should -Be 15
            $config.ReferralChasing | Should -Be 'None'
        }

        It "Creates with custom page size" {
            $config = [ADQueryConfig]::new(500)

            $config.PageSize | Should -Be 500
        }

        It "Has null credential by default" {
            $config = [ADQueryConfig]::new()

            $config.Credential | Should -BeNullOrEmpty
        }
    }

    Context "Validation" {
        It "Validates successfully with default values" {
            $config = [ADQueryConfig]::new()

            { $config.Validate() } | Should -Not -Throw
        }

        It "Throws on invalid PageSize (too large)" {
            $config = [ADQueryConfig]::new()
            $config.PageSize = 10000

            { $config.Validate() } | Should -Throw "*PageSize*"
        }

        It "Throws on invalid PageSize (negative)" {
            $config = [ADQueryConfig]::new()
            $config.PageSize = -1

            { $config.Validate() } | Should -Throw "*PageSize*"
        }

        It "Throws when ClientTimeout < ServerTimeout" {
            $config = [ADQueryConfig]::new()
            $config.ServerTimeoutMinutes = 15
            $config.ClientTimeoutMinutes = 10

            { $config.Validate() } | Should -Throw "*ClientTimeout*"
        }

        It "Throws on invalid BatchSize" {
            $config = [ADQueryConfig]::new()
            $config.BatchSize = 60000

            { $config.Validate() } | Should -Throw "*BatchSize*"
        }
    }

    Context "Methods" {
        It "GetSearcherOptions returns hashtable" {
            $config = [ADQueryConfig]::new()
            $options = $config.GetSearcherOptions()

            $options | Should -BeOfType [hashtable]
            $options.PageSize | Should -Be 1000
            $options.ServerTimeoutMinutes | Should -Be 10
            $options.ReferralChasing | Should -Be 'None'
        }

        It "GetConnectionOptions returns hashtable" {
            $config = [ADQueryConfig]::new()
            $options = $config.GetConnectionOptions()

            $options | Should -BeOfType [hashtable]
            $options.TimeoutSeconds | Should -Be 30
        }

        It "GetConnectionOptions includes credential if set" {
            $config = [ADQueryConfig]::new()
            $config.Credential = New-Object System.Management.Automation.PSCredential(
                "testuser",
                (ConvertTo-SecureString "testpass" -AsPlainText -Force)
            )

            $options = $config.GetConnectionOptions()

            $options.Credential | Should -Not -BeNullOrEmpty
        }

        It "Clone creates independent copy" {
            $config = [ADQueryConfig]::new()
            $config.PageSize = 500
            $config.BatchSize = 1000

            $clone = $config.Clone()

            $clone.PageSize | Should -Be 500
            $clone.BatchSize | Should -Be 1000

            # Modify original
            $config.PageSize = 2000

            # Clone should be unchanged
            $clone.PageSize | Should -Be 500
        }

        It "GetSummary returns hashtable" {
            $config = [ADQueryConfig]::new()
            $summary = $config.GetSummary()

            $summary | Should -BeOfType [hashtable]
            $summary.PageSize | Should -Be 1000
            $summary.ServerTimeout | Should -Be "10m"
            $summary.HasCredential | Should -Be $false
        }

        It "ToString returns formatted string" {
            $config = [ADQueryConfig]::new()
            $str = $config.ToString()

            $str | Should -Match "ADQueryConfig"
            $str | Should -Match "PageSize"
        }
    }
}

Describe "ConvertTo-SafeLdapFilter" {
    Context "Special Character Escaping" {
        It "Escapes backslash" {
            $result = ConvertTo-SafeLdapFilter -Value "test\value"
            $result | Should -Be "test\5cvalue"
        }

        It "Escapes asterisk" {
            $result = ConvertTo-SafeLdapFilter -Value "test*value"
            $result | Should -Be "test\2avalue"
        }

        It "Escapes left parenthesis" {
            $result = ConvertTo-SafeLdapFilter -Value "test(value"
            $result | Should -Be "test\28value"
        }

        It "Escapes right parenthesis" {
            $result = ConvertTo-SafeLdapFilter -Value "test)value"
            $result | Should -Be "test\29value"
        }

        It "Escapes NUL character" {
            $result = ConvertTo-SafeLdapFilter -Value "test`0value"
            $result | Should -Be "test\00value"
        }

        It "Escapes multiple special characters" {
            $result = ConvertTo-SafeLdapFilter -Value "test*\()"
            $result | Should -Be "test\2a\5c\28\29"
        }

        It "Preserves wildcards when AllowWildcards specified" {
            $result = ConvertTo-SafeLdapFilter -Value "test*value" -AllowWildcards
            $result | Should -Be "test*value"
        }

        It "Escapes backslash even with AllowWildcards" {
            $result = ConvertTo-SafeLdapFilter -Value "test\*value" -AllowWildcards
            $result | Should -Be "test\5c*value"
        }
    }

    Context "LDAP Injection Prevention" {
        It "Prevents wildcard injection attack" {
            $malicious = "admin*)(objectClass=*"
            $result = ConvertTo-SafeLdapFilter -Value $malicious
            $result | Should -Be "admin\2a\29\28objectClass=\2a"
        }

        It "Prevents filter closing attack" {
            $malicious = "test)(|(password=*"
            $result = ConvertTo-SafeLdapFilter -Value $malicious
            $result | Should -Be "test\29\28|\28password=\2a"
        }

        It "Handles empty string" {
            $result = ConvertTo-SafeLdapFilter -Value ""
            $result | Should -Be ""
        }

        It "Handles null-like input gracefully" {
            $result = ConvertTo-SafeLdapFilter -Value ""
            $result | Should -Be ""
        }
    }

    Context "Pipeline Support" {
        It "Works with pipeline input" {
            $result = "test*value" | ConvertTo-SafeLdapFilter
            $result | Should -Be "test\2avalue"
        }

        It "Processes multiple pipeline values" {
            $results = @("test*", "admin()", "user\name") | ConvertTo-SafeLdapFilter
            $results.Count | Should -Be 3
            $results[0] | Should -Be "test\2a"
            $results[1] | Should -Be "admin\28\29"
            $results[2] | Should -Be "user\5cname"
        }
    }
}

Describe "Test-LdapFilterSyntax" {
    Context "Valid Filters" {
        It "Validates simple filter" {
            $result = Test-LdapFilterSyntax -Filter "(objectClass=user)"
            $result | Should -Be $true
        }

        It "Validates AND filter" {
            $result = Test-LdapFilterSyntax -Filter "(&(objectClass=user)(cn=John))"
            $result | Should -Be $true
        }

        It "Validates OR filter" {
            $result = Test-LdapFilterSyntax -Filter "(|(cn=John)(cn=Jane))"
            $result | Should -Be $true
        }

        It "Validates NOT filter" {
            $result = Test-LdapFilterSyntax -Filter "(!(objectClass=computer))"
            $result | Should -Be $true
        }

        It "Validates wildcard" {
            $result = Test-LdapFilterSyntax -Filter "(cn=John*)"
            $result | Should -Be $true
        }

        It "Validates complex nested filter" {
            $filter = "(&(objectClass=user)(|(cn=John*)(cn=Jane*)))"
            $result = Test-LdapFilterSyntax -Filter $filter
            $result | Should -Be $true
        }
    }

    Context "Invalid Filters" {
        It "Rejects empty string" {
            $result = Test-LdapFilterSyntax -Filter ""
            $result | Should -Be $false
        }

        It "Rejects filter without opening paren" {
            $result = Test-LdapFilterSyntax -Filter "objectClass=user)"
            $result | Should -Be $false
        }

        It "Rejects filter with unbalanced parens (too many open)" {
            $result = Test-LdapFilterSyntax -Filter "((objectClass=user)"
            $result | Should -Be $false
        }

        It "Rejects filter with unbalanced parens (too many close)" {
            $result = Test-LdapFilterSyntax -Filter "(objectClass=user))"
            $result | Should -Be $false
        }

        It "Rejects filter without comparison operator" {
            $result = Test-LdapFilterSyntax -Filter "(objectClass)"
            $result | Should -Be $false
        }
    }
}
