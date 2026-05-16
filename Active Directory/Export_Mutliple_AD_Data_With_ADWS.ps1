# ------------- CONFIGURATION -----------------

# 1. Define the list of domains you want to query
$Domains = @(
"ad.dstsystems.com"
"sscdirect.com"
)

# 2. Define the output file path
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$outputCsv = "C:\temp\Manoj\MultiDomain_AD_Objects_testv1_$timestamp.csv"

# ----------------------------------------------

Write-Host "`n🚀 Starting multi-domain cluster object query..." -ForegroundColor Cyan

# Use an array to store results from all domains
$AllResults = @()

foreach ($domain in $Domains) {
    Write-Host "`n=== Querying domain: **$domain** ===" -ForegroundColor Yellow

    try {
        # Perform the query against the current domain
        $DomainResults = Get-ADComputer -Server $domain `
            -Properties operatingsystem, serviceprincipalname `
            -LDAPFilter '(operatingsystem=*Server*)' -ErrorAction Stop |
        
        # Select and calculate properties
        Select-Object @{l='Domain'; e={$domain}}, Name, OperatingSystem, Enabled, 
            @{l='ClusterObject'; e={if (($_.serviceprincipalname -join '') -like '*MSClusterVirtualServer*'){$true}else{$false}}}
        
        # Add the domain results to the main array
        $AllResults += $DomainResults
        
        Write-Host "✅ Successfully queried $domain. Found $($DomainResults.Count) computer objects." -ForegroundColor Green

    } catch {
        Write-Host "🛑 Failed to query $domain. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Export combined results to a single CSV
if ($AllResults.Count -gt 0) {
    $AllResults | Export-Csv -Path $outputCsv -NoTypeInformation -Encoding UTF8
    
    Write-Host "`n✅ Export complete!" -ForegroundColor Green
    Write-Host "💾 All domain results saved to: **$outputCsv**" -ForegroundColor Yellow
} else {
    Write-Host "`n⚠️ No results were collected. Check domain names and connectivity." -ForegroundColor Yellow
}
