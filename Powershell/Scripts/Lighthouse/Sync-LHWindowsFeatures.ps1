
$ScriptBlock = {
    Param (
        [string[]]$FeatureList
    )

    # Install all features in one command
    Install-WindowsFeature -Name $FeatureList -IncludeManagementTools
}

#WJB on 02/13/2025


# Define source and destination domain credentials
#$SourceCred = Get-Credential -Message "Enter Source Domain Credentials"
#$DestCred = Get-Credential -Message "Enter Destination Domain Credentials"

$sourceCred = Get-Credential -UserName "svcwbeaton@lighthousepartners.com" -Message "Enter source domain credentials"
$destCred = Get-Credential -UserName "wbeaton-adm@sscclient161.ssncad.global" -Message "Enter destination domain credentials"

# Define source and destination server list using json to ensure that servers are always properly mapped

$json = @'
[
    {
        "SourceServer": "RRPRD-02.lighthousepartners.com",
        "DestServer": "10-102-0-26.sscclient161.ssncad.global"
    },
    {
        "SourceServer": "RRPRD-03.lighthousepartners.com",
        "DestServer": "10-102-0-25.sscclient161.ssncad.global"
    }
]
'@

# Convert JSON to PowerShell objects
$ServerMappings = $json | ConvertFrom-Json

ForEach ($Server In $ServerMappings) {
    $SourceServer = $Server.SourceServers
    $DestServer = $Server.DestServers
    
    Write-Host "Processing: $SourceServer -> $DestServer"
    
    # Get installed features from source server
    $SessionSource = New-PSSession -ComputerName $SourceServer -Credential $SourceCred #-Authentication Negotiate
    
    $InstalledFeatures = Invoke-Command -Session $SessionSource {
        Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name
    }
    Remove-PSSession $SessionSource
    
    If ($InstalledFeatures) {
        Write-Host "Features to install on $DestServer : $($InstalledFeatures.Name -join ', ')"
        
        # Install features on destination server
        $SessionDest = New-PSSession -ComputerName $DestServer -Credential $DestCred #-Authentication Negotiate
        
        # Execute the script block with the list of features
        Invoke-Command -Session $SessionDest -ScriptBlock $ScriptBlock -ArgumentList $InstalledFeatures.Name
        
        Remove-PSSession $SessionDest
        Write-Host "Feature replication completed for $DestServer."
    } Else {
        Write-Host "No features found on $SourceServer."
    }
    
}

#Test-NetConnection -ComputerName "100-98-0-23.sscclient161.ssncad.global" -Port 5985

