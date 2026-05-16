<#
.SYNOPSIS
    Collects domain health information including SYSVOL replication method and GPO store health.

.DESCRIPTION
    Retrieves domain-scoped health data for an Active Directory domain:
    - SYSVOL Replication Method (FRS vs DFSR) and migration state
    - GPO Store Health (orphaned GPCs/GPTs, version mismatches)

    This function uses ADSI/LDAP directly and does not require the ActiveDirectory
    PowerShell module.

.PARAMETER Server
    The domain controller to query.

.PARAMETER DomainName
    The fully qualified domain name (FQDN) of the domain to query.

.PARAMETER Config
    Optional ADQueryConfig object with connection settings.

.OUTPUTS
    PSCustomObject with SYSVOL replication and GPO health properties.

.NOTES
    Part of SSNC.ADInventory module
    Used to populate domain health columns in AD_Domain table
#>
function Get-ADDomainHealthInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$DomainName,

        [Parameter()]
        [ADQueryConfig]$Config
    )

    $result = [PSCustomObject]@{
        # SYSVOL Replication Method
        SysvolReplicationMethod = $null
        SysvolMigrationState = $null
        DFSRExists = $null
        FRSExists = $null
        DFSRFlags = $null
        # GPO Store Health
        GPOTotalCount = $null
        GPOHealthyCount = $null
        GPOOrphanedGPCCount = $null
        GPOOrphanedGPTCount = $null
        GPOVersionMismatchCount = $null
        GPOOverallHealth = $null
        SYSVOLAccessible = $null
        DefaultDomainPolicyExists = $null
        DefaultDCPolicyExists = $null
    }

    try {
        # Get domain DN from RootDSE
        $rootDse = [ADSI]"LDAP://$Server/RootDSE"
        $domainDN = [string]$rootDse.defaultNamingContext

        # ====================
        # SYSVOL Replication Method
        # ====================
        $sysvolResult = Get-SysvolReplicationMethodInternal -Server $Server -DomainDN $domainDN
        $result.SysvolReplicationMethod = $sysvolResult.ActiveMethod
        $result.SysvolMigrationState = $sysvolResult.MigrationState
        $result.DFSRExists = $sysvolResult.DFSRExists
        $result.FRSExists = $sysvolResult.FRSExists
        $result.DFSRFlags = $sysvolResult.DFSRFlags

        # ====================
        # GPO Store Health
        # ====================
        $gpoResult = Get-GPOStoreHealthInternal -Server $Server -DomainName $DomainName -DomainDN $domainDN
        $result.GPOTotalCount = $gpoResult.TotalGPOCount
        $result.GPOHealthyCount = $gpoResult.HealthyGPOCount
        $result.GPOOrphanedGPCCount = $gpoResult.OrphanedGPCCount
        $result.GPOOrphanedGPTCount = $gpoResult.OrphanedGPTCount
        $result.GPOVersionMismatchCount = $gpoResult.VersionMismatchCount
        $result.GPOOverallHealth = $gpoResult.OverallHealth
        $result.SYSVOLAccessible = $gpoResult.SYSVOLAccessible
        $result.DefaultDomainPolicyExists = $gpoResult.DefaultDomainPolicyExists
        $result.DefaultDCPolicyExists = $gpoResult.DefaultDCPolicyExists

        Write-ADInventoryLog -Level Info -Message "Domain health info collected" `
            -Context @{
                Domain = $DomainName
                SysvolMethod = $result.SysvolReplicationMethod
                GPOOverallHealth = $result.GPOOverallHealth
            }
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to collect domain health info" `
            -Context @{ Domain = $DomainName; Server = $Server } `
            -Exception $_.Exception
    }

    return $result
}

<#
.SYNOPSIS
    Internal function to determine SYSVOL replication method.
#>
function Get-SysvolReplicationMethodInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$DomainDN
    )

    $result = @{
        ActiveMethod = 'Unknown'
        MigrationState = $null
        DFSRExists = $null
        FRSExists = $null
        DFSRFlags = $null
    }

    # Map flags to state names
    $MigrationStates = @{
        0  = 'Start'
        16 = 'Prepared'
        32 = 'Redirected'
        48 = 'Eliminated'
    }

    $DFSRPath = "CN=DFSR-GlobalSettings,CN=System,$DomainDN"
    $FRSPath  = "CN=Domain System Volume (SYSVOL share),CN=File Replication Service,CN=System,$DomainDN"

    # Check for DFSR
    try {
        $dfsrEntry = [ADSI]"LDAP://$Server/$DFSRPath"
        if ($dfsrEntry.distinguishedName) {
            $result.DFSRExists = $true
            # Get msDFSR-Flags attribute
            $flagsValue = $dfsrEntry.Properties['msDFSR-Flags']
            if ($flagsValue -and $flagsValue.Count -gt 0) {
                $result.DFSRFlags = [int]$flagsValue[0]
            }
        }
        else {
            $result.DFSRExists = $false
        }
    }
    catch {
        $result.DFSRExists = $false
    }

    # Check for FRS
    try {
        $frsEntry = [ADSI]"LDAP://$Server/$FRSPath"
        if ($frsEntry.distinguishedName) {
            $result.FRSExists = $true
        }
        else {
            $result.FRSExists = $false
        }
    }
    catch {
        $result.FRSExists = $false
    }

    # Determine state based on object existence and flags
    if (-not $result.DFSRExists -and -not $result.FRSExists) {
        $result.ActiveMethod = 'Unknown'
    }
    elseif (-not $result.DFSRExists -and $result.FRSExists) {
        $result.ActiveMethod = 'FRS'
        $result.MigrationState = 'Not Started'
    }
    elseif ($result.DFSRExists -and $result.FRSExists) {
        # Both exist - mid-migration or orphaned FRS objects
        if ($null -eq $result.DFSRFlags) {
            $result.ActiveMethod = 'Unknown'
        }
        elseif ($result.DFSRFlags -lt 32) {
            $result.ActiveMethod = 'FRS'
            $result.MigrationState = $MigrationStates[$result.DFSRFlags]
        }
        elseif ($result.DFSRFlags -eq 32) {
            $result.ActiveMethod = 'DFSR'
            $result.MigrationState = 'Redirected'
        }
        else {
            # Flags >= 48 but FRS still exists
            $result.ActiveMethod = 'DFSR'
            $result.MigrationState = 'Eliminated'
        }
    }
    elseif ($result.DFSRExists -and -not $result.FRSExists) {
        $result.ActiveMethod = 'DFSR'
        if ($null -eq $result.DFSRFlags) {
            $result.MigrationState = 'Native'
        }
        elseif ($result.DFSRFlags -eq 48) {
            $result.MigrationState = 'Eliminated'
        }
        else {
            $result.MigrationState = $MigrationStates[$result.DFSRFlags]
        }
    }

    return $result
}

<#
.SYNOPSIS
    Internal function to check GPO store health.
#>
function Get-GPOStoreHealthInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$DomainName,

        [Parameter(Mandatory)]
        [string]$DomainDN
    )

    # Default GPO GUIDs
    $DefaultDomainPolicyGuid = "31B2F340-816D-11D0-A060-00C04FD8D4E8"
    $DefaultDCPolicyGuid = "6AC1786C-016F-11D2-945F-00C04fB984F9"

    $result = @{
        TotalGPOCount = 0
        HealthyGPOCount = 0
        OrphanedGPCCount = 0
        OrphanedGPTCount = 0
        VersionMismatchCount = 0
        OverallHealth = 'Healthy'
        SYSVOLAccessible = $false
        DefaultDomainPolicyExists = $false
        DefaultDCPolicyExists = $false
    }

    $policiesDN = "CN=Policies,CN=System,$DomainDN"
    $sysvolPath = "\\$DomainName\SYSVOL\$DomainName\Policies"

    # Check SYSVOL accessibility
    $result.SYSVOLAccessible = Test-Path -Path $sysvolPath -ErrorAction SilentlyContinue

    # Get all GPCs from AD
    $gpcHash = @{}
    try {
        $policiesContainer = [ADSI]"LDAP://$Server/$policiesDN"
        if ($policiesContainer.distinguishedName) {
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($policiesContainer)
            $searcher.Filter = "(objectClass=groupPolicyContainer)"
            $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
            $searcher.PropertiesToLoad.AddRange(@("cn", "versionNumber"))
            $searcher.PageSize = 1000

            $gpcResults = $searcher.FindAll()

            foreach ($gpcResult in $gpcResults) {
                $props = $gpcResult.Properties
                $gpoGuid = ([string]$props["cn"][0]).Trim('{}').ToUpper()
                $versionNumber = if ($props["versionnumber"].Count -gt 0) { [int]$props["versionnumber"][0] } else { 0 }

                $gpcHash[$gpoGuid] = @{
                    ADVersion = $versionNumber
                    GPCExists = $true
                }
            }

            $gpcResults.Dispose()
            $searcher.Dispose()
        }
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to query GPCs from AD" `
            -Context @{ DomainDN = $DomainDN } `
            -Exception $_.Exception
    }

    # Get all GPTs from SYSVOL
    $gptHash = @{}
    if ($result.SYSVOLAccessible) {
        try {
            $gptFolders = Get-ChildItem -Path $sysvolPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\{[0-9A-Fa-f-]+\}$' }

            foreach ($folder in $gptFolders) {
                $gpoGuid = $folder.Name.Trim('{}').ToUpper()
                $gptIniPath = Join-Path -Path $folder.FullName -ChildPath "GPT.INI"

                $gptVersion = $null
                if (Test-Path -Path $gptIniPath) {
                    $gptIniContent = Get-Content -Path $gptIniPath -ErrorAction SilentlyContinue
                    $versionLine = $gptIniContent | Where-Object { $_ -match '^Version=' }
                    if ($versionLine -match 'Version=(\d+)') {
                        $gptVersion = [int]$Matches[1]
                    }
                }

                $gptHash[$gpoGuid] = @{
                    GPTVersion = $gptVersion
                }
            }
        }
        catch {
            Write-ADInventoryLog -Level Warning -Message "Failed to enumerate GPT folders" `
                -Context @{ SysvolPath = $sysvolPath } `
                -Exception $_.Exception
        }
    }

    # Cross-reference and identify issues
    $allGuids = @($gpcHash.Keys) + @($gptHash.Keys) | Sort-Object -Unique
    $orphanedGPCCount = 0
    $orphanedGPTCount = 0
    $versionMismatchCount = 0
    $healthyCount = 0
    $totalGPOCount = 0

    foreach ($guid in $allGuids) {
        $gpcExists = $gpcHash.ContainsKey($guid)
        $gptExists = $gptHash.ContainsKey($guid)

        if ($gpcExists) {
            $totalGPOCount++
        }

        if ($gpcExists -and -not $gptExists) {
            $orphanedGPCCount++
        }
        elseif (-not $gpcExists -and $gptExists) {
            $orphanedGPTCount++
        }
        elseif ($gpcExists -and $gptExists) {
            $adVersion = $gpcHash[$guid].ADVersion
            $gptVersion = $gptHash[$guid].GPTVersion

            if ($null -ne $adVersion -and $null -ne $gptVersion -and $adVersion -ne $gptVersion) {
                $versionMismatchCount++
            }
            else {
                $healthyCount++
            }
        }
    }

    $result.TotalGPOCount = $totalGPOCount
    $result.HealthyGPOCount = $healthyCount
    $result.OrphanedGPCCount = $orphanedGPCCount
    $result.OrphanedGPTCount = $orphanedGPTCount
    $result.VersionMismatchCount = $versionMismatchCount

    # Check default GPOs
    if ($gpcHash.ContainsKey($DefaultDomainPolicyGuid) -and $gptHash.ContainsKey($DefaultDomainPolicyGuid)) {
        $result.DefaultDomainPolicyExists = $true
    }
    if ($gpcHash.ContainsKey($DefaultDCPolicyGuid) -and $gptHash.ContainsKey($DefaultDCPolicyGuid)) {
        $result.DefaultDCPolicyExists = $true
    }

    # Determine overall health
    $criticalIssues = (-not $result.DefaultDomainPolicyExists) -or
                      (-not $result.DefaultDCPolicyExists) -or
                      (-not $result.SYSVOLAccessible)

    $warningIssues = ($orphanedGPCCount -gt 0) -or ($orphanedGPTCount -gt 0) -or ($versionMismatchCount -gt 0)

    if ($criticalIssues) {
        $result.OverallHealth = 'Critical'
    }
    elseif ($warningIssues) {
        $result.OverallHealth = 'Warning'
    }
    else {
        $result.OverallHealth = 'Healthy'
    }

    return $result
}
