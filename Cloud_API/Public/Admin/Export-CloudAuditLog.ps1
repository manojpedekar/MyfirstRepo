function Export-CloudAuditLog {
    <#
    .SYNOPSIS
        Exports audit logs to a file.

    .DESCRIPTION
        Exports audit logs for a specified date range to a file in CSV or JSON format.
        This is useful for compliance reporting and external analysis.

    .PARAMETER StartDate
        The start date for the audit log export (mandatory).

    .PARAMETER EndDate
        The end date for the audit log export (mandatory).

    .PARAMETER Format
        The export format: 'CSV' or 'JSON'. Default is 'JSON'.

    .PARAMETER OutputPath
        The full path to the output file (mandatory).

    .PARAMETER ResourceType
        Filter by resource type.

    .PARAMETER UserId
        Filter by user ID.

    .EXAMPLE
        PS> Export-CloudAuditLog -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -OutputPath "C:\Logs\audit.json"

        Exports the last 30 days of audit logs to a JSON file.

    .EXAMPLE
        PS> Export-CloudAuditLog -StartDate '2024-01-01' -EndDate '2024-01-31' -Format 'CSV' -OutputPath "C:\Logs\january_audit.csv"

        Exports January audit logs to a CSV file.

    .OUTPUTS
        System.IO.FileInfo. Returns the exported file info, or $null on error.

    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [datetime]$StartDate,

        [Parameter(Mandatory=$true)]
        [datetime]$EndDate,

        [Parameter(Mandatory=$false)]
        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'JSON',

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            $parent = Split-Path -Parent $_
            if ($parent -and -not (Test-Path $parent)) {
                throw "Parent directory does not exist: $parent"
            }
            return $true
        })]
        [string]$OutputPath,

        [Parameter(Mandatory=$false)]
        [string]$ResourceType,

        [Parameter(Mandatory=$false)]
        [string]$UserId
    )

    try {
        # Validate date range
        if ($StartDate -gt $EndDate) {
            Write-Error "StartDate must be before EndDate"
            return $null
        }

        if (-not $PSCmdlet.ShouldProcess("audit logs to '$OutputPath'", 'Export')) {
            return $null
        }

        $headers = New-CloudAPIHeaders -IncludeContentType -IncludeAccept

        # Build request body
        $body = @{
            startDate = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            endDate = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            format = $Format.ToLower()
        }

        if ($ResourceType) { $body['resourceType'] = $ResourceType }
        if ($UserId) { $body['userId'] = $UserId }

        Write-Verbose "Exporting audit logs from $StartDate to $EndDate in $Format format"

        $response = Invoke-CloudAPIRequest -Path 'admin/audit-logs/export' -Method 'POST' -Headers $headers -Body $body

        if ($response -and $response.content) {
            # Write to file based on format
            if ($Format -eq 'JSON') {
                $response.content | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            }
            else {
                # Convert to CSV
                $response.content | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            }

            Write-Verbose "Audit logs exported to: $OutputPath"
            return Get-Item -Path $OutputPath
        }
        else {
            Write-Warning "No audit log data returned for export"
            return $null
        }
    }
    catch {
        Write-Error "Failed to export audit logs: $($_.Exception.Message)"
        return $null
    }
}
