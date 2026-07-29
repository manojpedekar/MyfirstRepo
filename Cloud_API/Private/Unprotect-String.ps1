function Unprotect-String {
    <#
    .SYNOPSIS
        Decrypts a string that was encrypted using Protect-String.
    
    .DESCRIPTION
        Decrypts a Base64-encoded encrypted string using Windows Data Protection API (DPAPI).
        This function is used to decrypt the stored API key.
    
    .PARAMETER StringtoDecrypt
        The Base64-encoded encrypted string to decrypt.
    
    .PARAMETER Computer
        If specified, uses LocalMachine scope instead of CurrentUser scope.
    
    .EXAMPLE
        PS> $decrypted = Unprotect-String -StringtoDecrypt "AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA..."
        
        Decrypts the specified string.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$StringtoDecrypt,
        
        [switch]$Computer
    )

    if ($Computer) {
        $key = "LocalMachine"
    } else {
        $key = "CurrentUser"
    }
    
    try {
        $data = [Convert]::FromBase64String($StringtoDecrypt)
        $data = [System.Security.Cryptography.ProtectedData]::Unprotect($data, $null, [System.Security.Cryptography.DataProtectionScope]::$key)
        [System.Text.Encoding]::UTF8.GetString($data)
    }
    catch {
        Write-Error "Failed to decrypt string: $($_.Exception.Message)"
        return $null
    }
}
