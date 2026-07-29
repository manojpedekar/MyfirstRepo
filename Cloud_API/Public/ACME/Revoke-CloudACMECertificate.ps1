function Revoke-CloudACMECertificate {
    <#
    .SYNOPSIS
        Revokes an ACME certificate.
    
    .DESCRIPTION
        Revokes a specified ACME certificate. Once revoked, the certificate cannot be
        used and will be added to certificate revocation lists (CRLs).
        
        By default, prompts for confirmation unless the -Force switch is used.
    
    .PARAMETER Id
        The unique identifier of the certificate to revoke. Required.
    
    .PARAMETER Reason
        The reason for revocation. Options include:
        - unspecified (default)
        - keycompromise
        - cacompromise
        - affiliationchanged
        - superseded
        - cessationofoperation
        - certificatehold
        - removefromcrl
        - privilegewithdrawn
        - aacompromise
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Revoke-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before revoking the certificate.
    
    .EXAMPLE
        PS> Revoke-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a" -Reason "keycompromise" -Force
        
        Revokes the certificate immediately due to key compromise.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CertificateId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('unspecified', 'keycompromise', 'cacompromise', 'affiliationchanged', 'superseded', 'cessationofoperation', 'certificatehold', 'removefromcrl', 'privilegewithdrawn', 'aacompromise')]
        [string]$Reason = 'unspecified',
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    try {
        # Get certificate details for the confirmation message
        $certificate = Get-CloudACMECertificate -Id $Id
        $certDomain = if ($certificate) { $certificate.domain } else { $Id }
        
        # Use ShouldProcess for confirmation
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("certificate for '$certDomain' ($Id)", 'Revoke')) {
            return $null
        }
        
        # Build request body
        $body = @{
            reason = $Reason
        }
        
        # Make API request
        $headers = New-CloudAPIHeaders -IncludeContentType
        $response = Invoke-CloudAPIRequest -Path "acme/certificates/$Id/revoke" -Method 'POST' -Headers $headers -Body $body
        
        return $response
    }
    catch {
        Write-Error "Failed to revoke ACME certificate: $($_.Exception.Message)"
        return $null
    }
}
