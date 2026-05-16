function ConvertTo-SafeLdapFilter {
    <#
    .SYNOPSIS
        Escapes special characters in LDAP filter values to prevent injection

    .DESCRIPTION
        Escapes special LDAP characters in user-provided values to prevent LDAP injection attacks.
        This is critical when building LDAP filters with user input.

        ADDRESSES security issue from original script (line 371):
        - Original: User-provided filter with no validation or escaping
        - Fixed: Proper escaping of special characters

        Special LDAP characters that must be escaped:
        - \ (backslash) -> \5c
        - * (asterisk) -> \2a
        - ( (left paren) -> \28
        - ) (right paren) -> \29
        - NUL (\0) -> \00

    .PARAMETER Value
        The value to escape for use in an LDAP filter

    .PARAMETER AllowWildcards
        If specified, allows * wildcards in the value (does not escape them)
        Use with caution - only for controlled search scenarios

    .OUTPUTS
        String with special characters escaped

    .EXAMPLE
        $username = "admin*user"
        $safeValue = ConvertTo-SafeLdapFilter -Value $username
        $filter = "(samAccountName=$safeValue)"
        # Results in: (samAccountName=admin\2auser)

    .EXAMPLE
        # Search with wildcards (controlled)
        $searchTerm = "John*"
        $safeValue = ConvertTo-SafeLdapFilter -Value $searchTerm -AllowWildcards
        $filter = "(cn=$safeValue)"
        # Results in: (cn=John*) - wildcard preserved

    .EXAMPLE
        # Build safe filter with user input
        $userInput = Read-Host "Enter username"
        $safeInput = ConvertTo-SafeLdapFilter -Value $userInput
        $filter = "(&(objectClass=user)(samAccountName=$safeInput))"

    .NOTES
        Part of SSNC.ADInventory module

        LDAP Injection Prevention:
        This function is critical for preventing LDAP injection attacks.
        Always use when incorporating user input into LDAP filters.

        Example Attack (without escaping):
        User input: "admin*)(objectClass=*"
        Unsafe filter: (samAccountName=admin*)(objectClass=*)
        Result: Returns all objects instead of just matching users

        With escaping:
        Safe filter: (samAccountName=admin\2a)(objectClass=\2a)
        Result: Searches for literal "admin*)(objectClass=*" username

        Reference:
        - RFC 4515 (LDAP String Representation of Search Filters)
        - OWASP LDAP Injection Prevention
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0
        )]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [switch]$AllowWildcards
    )

    process {
        if ([string]::IsNullOrEmpty($Value)) {
            return $Value
        }

        # Escape backslash first (it's the escape character)
        $escaped = $Value -replace '\\', '\5c'

        # Escape parentheses
        $escaped = $escaped -replace '\(', '\28'
        $escaped = $escaped -replace '\)', '\29'

        # Escape NUL character
        $escaped = $escaped -replace "`0", '\00'

        # Escape asterisk (unless wildcards allowed)
        if (-not $AllowWildcards) {
            $escaped = $escaped -replace '\*', '\2a'
        }

        Write-ADInventoryLog -Level Debug -Message "LDAP value escaped" `
            -Context @{
                Original = $Value
                Escaped = $escaped
                AllowWildcards = $AllowWildcards.IsPresent
            }

        return $escaped
    }
}

function Test-LdapFilterSyntax {
    <#
    .SYNOPSIS
        Validates LDAP filter syntax

    .DESCRIPTION
        Performs basic validation of LDAP filter syntax to catch common errors
        before attempting queries. Does not guarantee the filter is semantically
        correct, but catches obvious syntax problems.

    .PARAMETER Filter
        The LDAP filter to validate

    .OUTPUTS
        Boolean - $true if filter appears syntactically valid, $false otherwise

    .EXAMPLE
        if (Test-LdapFilterSyntax -Filter "(objectClass=user)") {
            # Filter is valid
        }

    .EXAMPLE
        $filter = "(&(objectClass=user)(cn=John*))"
        if (-not (Test-LdapFilterSyntax -Filter $filter)) {
            throw "Invalid LDAP filter syntax"
        }

    .NOTES
        Part of SSNC.ADInventory module

        Validation Checks:
        - Balanced parentheses
        - Starts with (
        - Contains at least one operator (=, <=, >=, ~=)
        - No empty filter

        This is a basic syntactic check. The LDAP server will perform
        full semantic validation when the query is executed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Filter
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Filter)) {
            Write-ADInventoryLog -Level Debug -Message "LDAP filter is empty"
            return $false
        }

        try {
            # Check starts with (
            if (-not $Filter.StartsWith('(')) {
                Write-ADInventoryLog -Level Debug -Message "LDAP filter does not start with (" `
                    -Context @{ Filter = $Filter }
                return $false
            }

            # Check parentheses are balanced
            $openCount = ($Filter.ToCharArray() | Where-Object { $_ -eq '(' }).Count
            $closeCount = ($Filter.ToCharArray() | Where-Object { $_ -eq ')' }).Count

            if ($openCount -ne $closeCount) {
                Write-ADInventoryLog -Level Debug -Message "LDAP filter has unbalanced parentheses" `
                    -Context @{
                        Filter = $Filter
                        OpenCount = $openCount
                        CloseCount = $closeCount
                    }
                return $false
            }

            # Check contains at least one comparison operator
            if ($Filter -notmatch '(=|<=|>=|~=)') {
                Write-ADInventoryLog -Level Debug -Message "LDAP filter contains no comparison operators" `
                    -Context @{ Filter = $Filter }
                return $false
            }

            Write-ADInventoryLog -Level Debug -Message "LDAP filter syntax appears valid" `
                -Context @{ Filter = $Filter }

            return $true
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Error validating LDAP filter" `
                -Context @{ Filter = $Filter } `
                -Exception $_.Exception

            return $false
        }
    }
}
