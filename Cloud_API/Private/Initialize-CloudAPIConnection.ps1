function Initialize-CloudAPIConnection {
    <#
    .SYNOPSIS
        Initializes the Cloud API connection by loading or prompting for the API key.
    
    .DESCRIPTION
        Attempts to load the API key from an encrypted file at the configured path.
        If the file doesn't exist, prompts the user to enter their API key.
        The API key is stored in the script-level variable $script:CloudAPIKey.
    
    .PARAMETER KeyFilePath
        Optional. Override the default key file path.
    
    .EXAMPLE
        PS> Initialize-CloudAPIConnection
        
        Initializes the connection using the default key file or prompts for the key.
    
    .EXAMPLE
        PS> Initialize-CloudAPIConnection -KeyFilePath "C:\Custom\Path\api.key"
        
        Initializes the connection using a custom key file path.
    
    .NOTES
        Author: SS&C Cloud Team
        Version: 2.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$KeyFilePath = $script:ModuleConfig.KeyFilePath
    )
    
    try {
        if (Test-Path $KeyFilePath) {
            Write-Verbose "Loading API key from encrypted file: $KeyFilePath"
            $encryptedKey = Get-Content $KeyFilePath -ErrorAction Stop
            
            if ([string]::IsNullOrWhiteSpace($encryptedKey)) {
                Write-Warning "Key file exists but is empty. Prompting for API key."
                $script:CloudAPIKey = Read-Host "To use this module, provide your Cloud API key" -AsSecureString | ConvertFrom-SecureString -AsPlainText
            } else {
                $decryptedKey = Unprotect-String -StringtoDecrypt $encryptedKey
                if ($null -eq $decryptedKey) {
                    Write-Warning "Failed to decrypt API key. Prompting for new key."
                    $script:CloudAPIKey = Read-Host "To use this module, provide your Cloud API key" -AsSecureString | ConvertFrom-SecureString -AsPlainText
                } else {
                    $script:CloudAPIKey = $decryptedKey
                    Write-Verbose "API key loaded successfully"
                }
            }
        } else {
            Write-Verbose "Key file not found at: $KeyFilePath"
            $script:CloudAPIKey = Read-Host "To use this module, provide your Cloud API key" -AsSecureString | ConvertFrom-SecureString -AsPlainText
        }
    }
    catch {
        Write-Error "Failed to initialize Cloud API connection: $($_.Exception.Message)"
        $script:CloudAPIKey = $null
    }
}
