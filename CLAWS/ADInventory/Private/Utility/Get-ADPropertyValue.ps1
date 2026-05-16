function Get-ADPropertyValue {
    <#
    .SYNOPSIS
        Safely extracts first value from AD property collection

    .DESCRIPTION
        Gets the first value from an AD SearchResult property collection.
        Returns null if the property doesn't exist or has no values.
        This is a safe wrapper that handles missing properties gracefully.

    .PARAMETER Properties
        The Properties collection from a DirectorySearcher SearchResult object
        (e.g., $result.Properties)

    .PARAMETER PropertyName
        The name of the property to retrieve (case-insensitive)

    .OUTPUTS
        System.Object
        Returns the first value of the property or $null if not found

    .EXAMPLE
        Get-ADPropertyValue -Properties $result.Properties -PropertyName 'displayName'
        Gets the displayName attribute value

    .EXAMPLE
        $props = $searchResult.Properties
        $email = Get-ADPropertyValue -Properties $props -PropertyName 'mail'

    .NOTES
        Part of SSNC.ADInventory module
        Replaces: _GP function from original script

        Improvements:
        - Proper parameter validation
        - No dependency on script-scoped variables
        - Better error handling
        - Supports pipeline
    #>
    [CmdletBinding()]
    [OutputType([object])]
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
                return $Properties[$PropertyName][0]
            }
            else {
                return $null
            }
        }
        catch {
            Write-Verbose "Error accessing property '$PropertyName': $_"
            return $null
        }
    }
}
