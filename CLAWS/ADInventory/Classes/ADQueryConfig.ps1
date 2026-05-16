<#
.SYNOPSIS
    Configuration class for Active Directory query operations

.DESCRIPTION
    Centralizes all AD query configuration settings including timeouts,
    page sizes, referral chasing, and credentials. Provides a single
    source of truth for query behavior across the module.

    IMPROVEMENTS over original script:
    - Line 370: PageSize hardcoded to 1000 - now configurable
    - No timeout configuration - now has server and client timeouts
    - Line 290: ReferralChasing set per-query - now centralized
    - Credentials passed inconsistently - now single config

.NOTES
    Part of SSNC.ADInventory module

    Usage:
        $config = [ADQueryConfig]::new()
        $config.PageSize = 500
        $config.Credential = Get-Credential

        $searcher = New-DirectorySearcher -DirectoryEntry $de `
            -Filter $filter `
            -PageSize $config.PageSize `
            -ServerTimeoutMinutes $config.ServerTimeoutMinutes
#>
class ADQueryConfig {
    # Query Performance
    [int]$PageSize = 1000
    [int]$ServerTimeoutMinutes = 10
    [int]$ClientTimeoutMinutes = 15

    # Connection Settings
    [int]$ConnectionTimeoutSeconds = 30
    [int]$MaxRetries = 3
    [int]$RetryDelaySeconds = 5

    # Referral Chasing
    [ValidateSet('None', 'Subordinate', 'All')]
    [string]$ReferralChasing = 'None'

    # Authentication
    [System.Management.Automation.PSCredential]$Credential = $null

    # DC Selection
    [int]$DCTestPort = 636  # LDAPS
    [int]$DCTestTimeout = 1000  # milliseconds
    [bool]$PreferLocalDC = $true

    # Batch Processing
    [int]$BatchSize = 5000
    [bool]$ShowProgress = $true

    # Logging
    [bool]$EnableVerboseLogging = $false
    [bool]$EnableDebugLogging = $false

    # Constructor - default settings
    ADQueryConfig() {
        Write-ADInventoryLog -Level Debug -Message "ADQueryConfig created with default settings"
    }

    # Constructor with custom page size
    ADQueryConfig([int]$pageSize) {
        $this.PageSize = $pageSize
        Write-ADInventoryLog -Level Debug -Message "ADQueryConfig created" `
            -Context @{ PageSize = $pageSize }
    }

    # Get searcher options as hashtable (for splatting)
    [hashtable] GetSearcherOptions() {
        return @{
            PageSize = $this.PageSize
            ServerTimeoutMinutes = $this.ServerTimeoutMinutes
            ClientTimeoutMinutes = $this.ClientTimeoutMinutes
            ReferralChasing = $this.ReferralChasing
        }
    }

    # Get connection options as hashtable
    [hashtable] GetConnectionOptions() {
        $options = @{
            TimeoutSeconds = $this.ConnectionTimeoutSeconds
        }

        if ($null -ne $this.Credential) {
            $options.Credential = $this.Credential
        }

        return $options
    }

    # Validate configuration
    [void] Validate() {
        $errors = [System.Collections.ArrayList]::new()

        if ($this.PageSize -lt 0 -or $this.PageSize -gt 5000) {
            [void]$errors.Add("PageSize must be between 0 and 5000")
        }

        if ($this.ServerTimeoutMinutes -lt 1 -or $this.ServerTimeoutMinutes -gt 60) {
            [void]$errors.Add("ServerTimeoutMinutes must be between 1 and 60")
        }

        if ($this.ClientTimeoutMinutes -lt 1 -or $this.ClientTimeoutMinutes -gt 60) {
            [void]$errors.Add("ClientTimeoutMinutes must be between 1 and 60")
        }

        if ($this.ClientTimeoutMinutes -lt $this.ServerTimeoutMinutes) {
            [void]$errors.Add("ClientTimeoutMinutes should be >= ServerTimeoutMinutes")
        }

        if ($this.ConnectionTimeoutSeconds -lt 1 -or $this.ConnectionTimeoutSeconds -gt 300) {
            [void]$errors.Add("ConnectionTimeoutSeconds must be between 1 and 300")
        }

        if ($this.BatchSize -lt 100 -or $this.BatchSize -gt 50000) {
            [void]$errors.Add("BatchSize must be between 100 and 50000")
        }

        if ($errors.Count -gt 0) {
            $errorMessage = "Configuration validation failed:`n  " + ($errors -join "`n  ")
            throw [System.ArgumentException]::new($errorMessage)
        }

        Write-ADInventoryLog -Level Debug -Message "Configuration validated successfully"
    }

    # Clone configuration
    [ADQueryConfig] Clone() {
        $clone = [ADQueryConfig]::new()

        $clone.PageSize = $this.PageSize
        $clone.ServerTimeoutMinutes = $this.ServerTimeoutMinutes
        $clone.ClientTimeoutMinutes = $this.ClientTimeoutMinutes
        $clone.ConnectionTimeoutSeconds = $this.ConnectionTimeoutSeconds
        $clone.MaxRetries = $this.MaxRetries
        $clone.RetryDelaySeconds = $this.RetryDelaySeconds
        $clone.ReferralChasing = $this.ReferralChasing
        $clone.Credential = $this.Credential
        $clone.DCTestPort = $this.DCTestPort
        $clone.DCTestTimeout = $this.DCTestTimeout
        $clone.PreferLocalDC = $this.PreferLocalDC
        $clone.BatchSize = $this.BatchSize
        $clone.ShowProgress = $this.ShowProgress
        $clone.EnableVerboseLogging = $this.EnableVerboseLogging
        $clone.EnableDebugLogging = $this.EnableDebugLogging

        return $clone
    }

    # Get configuration summary
    [hashtable] GetSummary() {
        return @{
            PageSize = $this.PageSize
            ServerTimeout = "$($this.ServerTimeoutMinutes)m"
            ClientTimeout = "$($this.ClientTimeoutMinutes)m"
            ReferralChasing = $this.ReferralChasing
            HasCredential = ($null -ne $this.Credential)
            BatchSize = $this.BatchSize
        }
    }

    # ToString for logging
    [string] ToString() {
        $summary = $this.GetSummary()
        $parts = $summary.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
        return "ADQueryConfig: " + ($parts -join ", ")
    }
}
