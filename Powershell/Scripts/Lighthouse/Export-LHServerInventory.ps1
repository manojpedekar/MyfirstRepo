<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	2/13/2025 1:10 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	12/26/2024 10:49 AM
	 Created by:   	DT234083
	 Organization: 	
	 Filename:     	CollectLHInventory.ps1
	===========================================================================
	.DESCRIPTION
		A refactored version of the InstalledSoftware class.
#>

Class Program {
    Static [version]$Version = [version]"1.0.0"
    
    [string]$DisplayName
    [string]$DisplayVersion
    [string]$Publisher
    [string]$InstallDate
    [string]$UninstallString
    [string]$QuietUninstallString
    [string]$BundleProviderKey
    [int]$EstimatedSize
    [string]$Size
    
    Program($properties) {
        $this.DisplayName = $properties.DisplayName
        $this.DisplayVersion = $properties.DisplayVersion
        $this.Publisher = $properties.Publisher
        $this.InstallDate = $properties.InstallDate
        $this.UninstallString = $properties.UninstallString
        $this.QuietUninstallString = $properties.QuietUninstallString
        $this.BundleProviderKey = $properties.BundleProviderKey
        $this.EstimatedSize = $properties.EstimatedSize
        $this.Size = If ($properties.EstimatedSize) {
            $appsize = $properties.EstimatedSize * 1KB
            Switch ($appsize) {
                { $_ -ge 1GB } { "{0:N2} GB" -f ($_ / 1GB); Break }
                { $_ -ge 1MB } { "{0:N2} MB" -f ($_ / 1MB); Break }
                default { "{0:N2} KB" -f ($_ / 1KB) }
            }
        } Else {
            "Unknown"
        }
    }
    
    Static [string] GetVersion() {
        Return [Program]::Version.ToString()
    }
    
    [void] Uninstall() {
        If ([string]::IsNullOrWhiteSpace($this.UninstallString)) {
            Write-Warning "UninstallString is empty or null for program: $($this.DisplayName)"
            Return
        }
        Try {
            Write-Output "Executing uninstall for: $($this.DisplayName)"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$($this.UninstallString)`"" -NoNewWindow -Wait
            Write-Output "Uninstall process for $($this.DisplayName) completed."
        } Catch {
            Write-Error "Failed to uninstall $($this.DisplayName): $_"
        }
    }
    
    Static [array] GetInstalledPrograms() {
        $InstalldApps = [System.Collections.ArrayList]::new()
        
        $uninstallKeys = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        ForEach ($key In $uninstallKeys) {
            If (Test-Path $key) {
                $regInstalledApps = Get-ItemProperty $key | Where-Object { $_.DisplayName -ne $null }
                ForEach ($App In $regInstalledApps) {
                    $InstalldApps.Add([Program]::new($App)) | Out-Null
                }
            }
        }
        Return $InstalldApps
    }
    
    [array] FindProgram([string]$name) {
        Return $this | Where-Object { $_.DisplayName -like "*$name*" }
    }
}

$StorageShare = "\\server.lighthousepartners.com\sharename"

$LHInventory = [PSCustomObject]@{
    Features = Get-WindowsFeature | ? {$_.InstallState -eq 'Installed'}
    ENVVARS = Get-ChildItem Env:
    SoftwareInventory  = [Program]::GetInstalledPrograms()
}

Export-Clixml -Path (Join-Path -Path $StorageShare -ChildPath "$($env:COMPUTERNAME).xml") -InputObject $LHInventory

