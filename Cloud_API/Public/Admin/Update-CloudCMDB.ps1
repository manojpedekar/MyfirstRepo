function Update-CloudCMDB {
    <#
    .SYNOPSIS
        Updates a CMDB server configuration item record.

    .DESCRIPTION
        Updates properties of an existing server configuration item (CI) in the CMDB.
        Only provided properties will be updated; existing properties not
        specified will remain unchanged.
        Note: This function specifically updates server CIs in the CMDB.

    .PARAMETER ServerId
        The server ID to update (mandatory). This is specifically for server-type CIs.

    .PARAMETER Properties
        Hashtable of properties to update (mandatory).

    .PARAMETER Description
        Updated description for the CI.

    .PARAMETER Owner
        Updated owner information.

    .PARAMETER Tags
        Hashtable of tags to set on the CI.

    .EXAMPLE
        PS> Update-CloudCMDB -ServerId "server-12345" -Description "Web server for production app"

        Updates the description of a server CI.

    .EXAMPLE
        PS> Update-CloudCMDB -ServerId "server-12345" -Properties @{'Environment' = 'Production'; 'Tier' = 'Frontend'}

        Updates custom properties of a server CI.

    .EXAMPLE
        PS> Update-CloudCMDB -ServerId "server-12345" -Tags @{'CostCenter' = 'IT-123'; 'Project' = 'CloudMigration'}

        Updates tags on a server CI.

    .OUTPUTS
        PSCustomObject. Returns $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CIId', 'ConfigurationItemId')]
        [string]$ServerId,

        [Parameter(Mandatory=$false)]
        [hashtable]$Properties,

        [Parameter(Mandatory=$false)]
        [string]$Description,

        [Parameter(Mandatory=$false)]
        [string]$Owner,

        [Parameter(Mandatory=$false)]
        [hashtable]$Tags
    )

    process {
        try {
            # Validate at least one update parameter is provided
            if (-not $Properties -and -not $Description -and -not $Owner -and -not $Tags) {
                Write-Warning "No update parameters specified. Please provide at least one property to update."
                return $null
            }

            if (-not $PSCmdlet.ShouldProcess("CMDB record '$ServerId'", 'Update')) {
                return $null
            }

            $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

            # Build request body dynamically
            $body = @{}

            if ($Properties) { $body['properties'] = $Properties }
            if ($Description) { $body['description'] = $Description }
            if ($Owner) { $body['owner'] = $Owner }
            if ($Tags) { $body['tags'] = $Tags }

            Write-Verbose "Updating CMDB record: $ServerId"

            $response = Invoke-CloudAPIRequest -Path "cmdb/servers/$ServerId" -Method 'PUT' -Headers $headers -Body $body

            return $response
        }
        catch {
            Write-Error "Failed to update CMDB record: $($_.Exception.Message)"
            return $null
        }
    }
}
