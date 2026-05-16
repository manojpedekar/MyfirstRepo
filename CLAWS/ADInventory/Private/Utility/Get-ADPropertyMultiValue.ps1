function Get-ADPropertyMultiValue {
    <#
    .SYNOPSIS
        Safely extracts all values from AD multi-valued property

    .DESCRIPTION
        Gets all values from an AD SearchResult multi-valued property collection.
        Returns empty array if the property doesn't exist or has no values.
        This is a safe wrapper that handles missing properties gracefully.

    .PARAMETER Properties
        The Properties collection from a DirectorySearcher SearchResult object
        (e.g., $result.Properties)

    .PARAMETER PropertyName
        The name of the property to retrieve (case-insensitive)

    .OUTPUTS
        System.Array
        Returns array of all property values or empty array if not found

    .EXAMPLE
        Get-ADPropertyMultiValue -Properties $result.Properties -PropertyName 'memberOf'
        Gets all group memberships

    .EXAMPLE
        $props = $searchResult.Properties
        $proxyAddresses = Get-ADPropertyMultiValue -Properties $props -PropertyName 'proxyAddresses'

    .NOTES
        Part of SSNC.ADInventory module
        Replaces: _GPM function from original script

        Improvements:
        - Proper parameter validation
        - No dependency on script-scoped variables
        - Better error handling
        - Supports pipeline
        - Always returns array (never null)
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [ValidateNotNull()]
        [System.Collections.Specialized.StringDictionary]$Properties,

        [Parameter(
            Mandatory = $true,
            Position = 1,
            ValueFromPipeline = $true
        )]
        [ValidateNotNullOrEmpty()]
        [string]$PropertyName
    )

    process {
        try {
            if ($Properties.Contains($PropertyName) -and $Properties[$PropertyName].Count -gt 0) {
                return @($Properties[$PropertyName])
            }
            else {
                return @()
            }
        }
        catch {
            Write-Verbose "Error accessing property '$PropertyName': $_"
            return @()
        }
    }
}
