function Remove-CloudACMECertificate {
    <#
    .SYNOPSIS
        Removes an ACME certificate.
    
    .DESCRIPTION
        Deletes a specified ACME certificate from the system. By default, prompts for
        confirmation unless the -Force switch is used.
        
        WARNING: This action is irreversible. The certificate will be permanently deleted.
    
    .PARAMETER Id
        The unique identifier of the certificate to remove. Required.
    
    .PARAMETER Force
        If specified, bypasses the confirmation prompt.
    
    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
        PS> Remove-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a"
        
        Prompts for confirmation before removing the certificate.
    
    .EXAMPLE
        PS> Remove-CloudACMECertificate -Id "cert-55c319eb-5944-4d00-a927-02e2eff4430a" -Force
        
        Removes the certificate without prompting.
    
    .OUTPUTS
        PSCustomObject. Returns $null on error or if cancelled.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('CertificateId')]
        [string]$Id,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    process {
        try {
            # Get certificate details for the confirmation message
            $certificate = Get-CloudACMECertificate -Id $Id
            $certDomain = if ($certificate) { $certificate.domain } else { $Id }
            
            # Use ShouldProcess for confirmation
            if (-not $Force -and -not $PSCmdlet.ShouldProcess("certificate for '$certDomain' ($Id)", 'Remove')) {
                return $null
            }
            
            $headers = New-CloudAPIHeaders
            $response = Invoke-CloudAPIRequest -Path "acme/certificates/$Id" -Method 'DELETE' -Headers $headers
            
            return $response
        }
        catch {
            Write-Error "Failed to remove ACME certificate: $($_.Exception.Message)"
            return $null
        }
    }
}
