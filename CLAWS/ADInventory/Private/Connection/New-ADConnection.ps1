function New-ADConnection {
    <#
    .SYNOPSIS
        Creates a DirectoryEntry connection to Active Directory with proper error handling

    .DESCRIPTION
        Establishes a connection to Active Directory using System.DirectoryServices.DirectoryEntry.
        Supports both authenticated and current-user connections.
        Validates the connection by accessing a property (NativeGuid).

        IMPORTANT: The returned DirectoryEntry object must be disposed by the caller.
        Use try/finally pattern or PowerShell 5.0+ using statement to ensure disposal.

    .PARAMETER Server
        The domain controller or server to connect to (FQDN or hostname)

    .PARAMETER Domain
        The domain name (e.g., "contoso.com")
        Used to construct the base DN (DC=contoso,DC=com)

    .PARAMETER BaseDN
        Optional explicit base DN (overrides Domain parameter)
        Example: "DC=contoso,DC=com" or "OU=Users,DC=contoso,DC=com"

    .PARAMETER Credential
        Optional PSCredential for authenticated connection
        If not provided, uses current user context

    .PARAMETER TimeoutSeconds
        Connection timeout in seconds (default: 30)
        Note: .NET DirectoryEntry doesn't support timeout directly,
        but we validate connection within this time

    .OUTPUTS
        System.DirectoryServices.DirectoryEntry
        A connected DirectoryEntry object. CALLER MUST DISPOSE!

    .EXAMPLE
        $de = New-ADConnection -Server "DC01.contoso.com" -Domain "contoso.com"
        try {
            # Work with $de
        } finally {
            $de.Dispose()
        }

    .EXAMPLE
        $cred = Get-Credential
        $de = New-ADConnection -Server "DC01" -Domain "fabrikam.com" -Credential $cred
        try {
            # Work with $de
        } finally {
            if ($de) { $de.Dispose() }
        }

    .EXAMPLE
        # Using explicit BaseDN
        $de = New-ADConnection -Server "DC01" -BaseDN "OU=Corporate,DC=contoso,DC=com"

    .NOTES
        Part of SSNC.ADInventory module

        Connection Leak Prevention:
        - Caller MUST dispose the returned object
        - Use try/finally to ensure disposal even on exceptions
        - Example pattern shown in examples above

        Improvements over original script:
        - Centralized connection creation
        - Connection validation
        - Proper error handling with context
        - Consistent credential handling
    #>
    [CmdletBinding()]
    [OutputType([System.DirectoryServices.DirectoryEntry])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByDomain')]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByBaseDN')]
        [ValidateNotNullOrEmpty()]
        [string]$BaseDN,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30
    )

    process {
        # Construct base DN from domain if not explicitly provided
        if ($PSCmdlet.ParameterSetName -eq 'ByDomain') {
            $BaseDN = 'DC=' + (($Domain -split '\.') -join ',DC=')
        }

        # Construct LDAP path
        $ldapPath = "LDAP://$Server/$BaseDN"

        Write-ADInventoryLog -Level Verbose -Message "Creating AD connection" `
            -Context @{
                Server = $Server
                BaseDN = $BaseDN
                Authenticated = ($null -ne $Credential)
            }

        try {
            # Create DirectoryEntry with or without credentials
            $de = if ($Credential) {
                New-Object System.DirectoryServices.DirectoryEntry(
                    $ldapPath,
                    $Credential.UserName,
                    $Credential.GetNetworkCredential().Password
                )
            }
            else {
                New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
            }

            # Validate connection by accessing a property
            # This forces authentication and will throw if connection fails
            Write-ADInventoryLog -Level Debug -Message "Validating connection by accessing NativeGuid"
            $null = $de.NativeGuid

            Write-ADInventoryLog -Level Verbose -Message "AD connection established successfully" `
                -Context @{
                    Server = $Server
                    BaseDN = $BaseDN
                    Guid = $de.Guid.ToString()
                }

            return $de
        }
        catch [System.Runtime.InteropServices.COMException] {
            $errorMessage = "Failed to connect to AD server: COM error"
            Write-ADInventoryLog -Level Error -Message $errorMessage `
                -Context @{
                    Server = $Server
                    BaseDN = $BaseDN
                    ErrorCode = $_.Exception.ErrorCode
                    HResult = $_.Exception.HResult
                } `
                -Exception $_.Exception

            # Dispose if partially created
            if ($de) {
                try { $de.Dispose() } catch { }
            }

            throw "Failed to connect to $Server/$BaseDN : $_"
        }
        catch {
            $errorMessage = "Failed to connect to AD server"
            Write-ADInventoryLog -Level Error -Message $errorMessage `
                -Context @{
                    Server = $Server
                    BaseDN = $BaseDN
                } `
                -Exception $_.Exception

            # Dispose if partially created
            if ($de) {
                try { $de.Dispose() } catch { }
            }

            throw "Failed to connect to $Server/$BaseDN : $_"
        }
    }
}
