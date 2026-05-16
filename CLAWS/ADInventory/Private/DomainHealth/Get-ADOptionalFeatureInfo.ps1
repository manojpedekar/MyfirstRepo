<#
.SYNOPSIS
    Retrieves the optional features available and enabled in an Active Directory forest.

.DESCRIPTION
    Queries the msDS-EnabledFeature attribute on the Partitions container and the
    Optional Features container to determine which optional AD features are available
    and which have been enabled for the forest.

    This function uses ADSI/LDAP directly and does not require the ActiveDirectory
    PowerShell module.

.PARAMETER Server
    The domain controller to query.

.PARAMETER ForestName
    The forest name for which to collect optional features.

.PARAMETER Config
    Optional ADQueryConfig object with connection settings.

.OUTPUTS
    Array of PSCustomObject with feature information, each containing:
    - ForestName: Forest name
    - FeatureName: Common name of the feature
    - FeatureGUID: The msDS-OptionalFeatureGUID value
    - IsEnabled: Boolean indicating if the feature is currently enabled
    - RequiredForestLevel: Minimum forest functional level required (integer)
    - RequiredForestLevelName: Friendly name of required level
    - RequiredDomainLevel: Minimum domain functional level required (integer)
    - Description: Human-readable description of the feature
    - DistinguishedName: Full DN of the feature object

.NOTES
    Part of SSNC.ADInventory module
    Forest-scoped data - collect once per forest
#>
function Get-ADOptionalFeatureInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,

        [Parameter(Mandatory)]
        [string]$ForestName,

        [Parameter()]
        [ADQueryConfig]$Config
    )

    # Known feature descriptions
    $FeatureDescriptions = @{
        'Recycle Bin Feature' = 'Preserves deleted AD objects with full attribute fidelity for recovery. Deleted objects can be restored without authoritative restore.'
        'Privileged Access Management Feature' = 'Enables time-bound (expiring) group membership and shadow security principals for just-in-time privileged access scenarios.'
    }

    # Forest functional level mappings
    $ForestLevelNames = @{
        0 = 'Windows 2000'
        1 = 'Windows Server 2003 Interim'
        2 = 'Windows Server 2003'
        3 = 'Windows Server 2008'
        4 = 'Windows Server 2008 R2'
        5 = 'Windows Server 2012'
        6 = 'Windows Server 2012 R2'
        7 = 'Windows Server 2016'
    }

    $features = [System.Collections.ArrayList]::new()

    try {
        # Bind to RootDSE to get configuration DN
        $rootDse = [ADSI]"LDAP://$Server/RootDSE"
        $configDn = [string]$rootDse.configurationNamingContext

        # Build paths
        $partitionsDn = "CN=Partitions,$configDn"
        $optionalFeaturesDn = "CN=Optional Features,CN=Directory Service,CN=Windows NT,CN=Services,$configDn"

        # Get enabled features from Partitions container
        $partitionsEntry = [ADSI]"LDAP://$Server/$partitionsDn"
        $enabledFeatureDNs = @($partitionsEntry.Properties["msDS-EnabledFeature"])

        # Normalize to array of strings
        $enabledFeatureList = [System.Collections.ArrayList]::new()
        foreach ($dn in $enabledFeatureDNs) {
            if ($dn) {
                [void]$enabledFeatureList.Add([string]$dn)
            }
        }

        # Query the Optional Features container to get all available features
        $optionalFeaturesEntry = [ADSI]"LDAP://$Server/$optionalFeaturesDn"
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($optionalFeaturesEntry)
        $searcher.Filter = "(objectClass=msDS-OptionalFeature)"
        $searcher.SearchScope = [System.DirectoryServices.SearchScope]::OneLevel
        $searcher.PropertiesToLoad.AddRange(@(
            "cn",
            "distinguishedName",
            "msDS-OptionalFeatureGUID",
            "msDS-RequiredForestBehaviorVersion",
            "msDS-RequiredDomainBehaviorVersion"
        ))

        $searchResults = $searcher.FindAll()

        foreach ($result in $searchResults) {
            $props = $result.Properties

            $featureName = [string]$props["cn"][0]
            $featureDN = [string]$props["distinguishedname"][0]

            # Get the GUID
            $featureGuid = $null
            $featureGuidBytes = $props["msds-optionalfeatureguid"]
            if ($featureGuidBytes -and $featureGuidBytes.Count -gt 0) {
                try {
                    $featureGuid = ([guid]$featureGuidBytes[0]).ToString()
                }
                catch {
                    # GUID conversion failed - leave as null
                }
            }

            # Get required levels
            $requiredForestLevel = $null
            if ($props["msds-requiredforestbehaviorversion"] -and $props["msds-requiredforestbehaviorversion"].Count -gt 0) {
                $requiredForestLevel = [int]$props["msds-requiredforestbehaviorversion"][0]
            }

            $requiredDomainLevel = $null
            if ($props["msds-requireddomainbehaviorversion"] -and $props["msds-requireddomainbehaviorversion"].Count -gt 0) {
                $requiredDomainLevel = [int]$props["msds-requireddomainbehaviorversion"][0]
            }

            # Check if enabled (forest scope)
            $isEnabled = $enabledFeatureList -contains $featureDN

            # Get description
            $description = $FeatureDescriptions[$featureName]
            if (-not $description) {
                $description = "No description available for this feature."
            }

            # Get friendly forest level name
            $requiredForestLevelName = $ForestLevelNames[$requiredForestLevel]
            if (-not $requiredForestLevelName -and $null -ne $requiredForestLevel) {
                $requiredForestLevelName = "Unknown ($requiredForestLevel)"
            }

            [void]$features.Add([PSCustomObject]@{
                ForestName              = $ForestName
                FeatureName             = $featureName
                FeatureGUID             = $featureGuid
                IsEnabled               = $isEnabled
                RequiredForestLevel     = $requiredForestLevel
                RequiredForestLevelName = $requiredForestLevelName
                RequiredDomainLevel     = $requiredDomainLevel
                Description             = $description
                DistinguishedName       = $featureDN
            })
        }

        $searchResults.Dispose()
        $searcher.Dispose()

        Write-ADInventoryLog -Level Info -Message "Optional features collected" `
            -Context @{
                ForestName = $ForestName
                FeatureCount = $features.Count
                EnabledCount = ($features | Where-Object { $_.IsEnabled }).Count
            }
    }
    catch {
        Write-ADInventoryLog -Level Warning -Message "Failed to collect optional features" `
            -Context @{ ForestName = $ForestName; Server = $Server } `
            -Exception $_.Exception
    }

    return @($features)
}
