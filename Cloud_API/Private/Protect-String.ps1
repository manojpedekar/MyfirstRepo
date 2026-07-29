function Protect-String {
    <#
    .SYNOPSIS
        Encrypts a string using Windows Data Protection API (DPAPI).
    
    .DESCRIPTION
        Encrypts a string using Windows DPAPI and returns the Base64-encoded result.
        This function is used to encrypt and store the API key securely.
    
    .PARAMETER StringtoEncrypt
        The plain text string to encrypt.
    
    .PARAMETER Computer
        If specified, uses LocalMachine scope instead of CurrentUser scope.
        LocalMachine scope allows any user on the computer to decrypt the string.
    
    .EXAMPLE
        PS> Protect-String -StringtoEncrypt "my-api-key"
        AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA...
        
        Encrypts the API key and returns the Base64-encoded result.
    
    .EXAMPLE
        PS> Protect-String -StringtoEncrypt "my-api-key" > "C:\Users\$($env:Username)\cloudapi.key"
        
        Encrypts the API key and saves it to a file.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$StringtoEncrypt,
        
        [switch]$Computer
    )

    if ($Computer) {
        $key = "LocalMachine"
    } else {
        $key = "CurrentUser"
    }
    
    try {
        $data = [System.Text.Encoding]::UTF8.GetBytes($StringtoEncrypt)
        $data = [System.Security.Cryptography.ProtectedData]::Protect($data, $null, [System.Security.Cryptography.DataProtectionScope]::$key)
        [Convert]::ToBase64String($data)
    }
    catch {
        Write-Error "Failed to encrypt string: $($_.Exception.Message)"
        return $null
    }
}
