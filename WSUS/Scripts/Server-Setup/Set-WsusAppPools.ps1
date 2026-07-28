#Requires -RunAsAdministrator

# WSUS/IIS management relies on the WebAdministration module and its IIS:\ provider,
# which only work natively in Windows PowerShell 5.1 (Desktop edition). Under
# PowerShell 7+ (Core) the module loads via a compatibility remoting session that
# returns deserialized objects and exposes no IIS:\ drive, so the script fails.
# Re-launch under Windows PowerShell 5.1 if we detect the Core edition.
If ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Warning "Detected PowerShell $($PSVersionTable.PSVersion) (Core). Re-launching under Windows PowerShell 5.1..."
    $ps51 = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    If (-not (Test-Path $ps51)) {
        Throw "Windows PowerShell 5.1 not found at '$ps51'. Please run this script with powershell.exe (not pwsh)."
    }
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    Exit $LASTEXITCODE
}

Function Set-WSUSAppPools {
    <#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2022 v5.8.201
	 Created on:   	6/9/2022 3:19 PM
	 Created by:   	DT234083
	 Organization: 	SS&C 
	 Filename:     	Set-WSUS-AppPools.ps1
	===========================================================================
	.DESCRIPTION
		This script will create individual app pools for each WSUS web app 
		This script also implements Microsoft Best Practices for WSUS
	.LINK
		https://learn.microsoft.com/en-us/troubleshoot/mem/configmgr/windows-server-update-services-best-practices
    #>

    [CmdletBinding()]
    Param (
        [int]$RootWsusPool = 2,
        [int]$WsusReportingWebServiceInGB = 2,
        [int]$WsusClientWebServiceInGB = 16,
        [int]$WsusSimpleAuthWebServiceInGB = 1,
        [int]$WsusServerSyncWebServiceInGB = 4,
        [int]$WsusDssAuthWebServiceInGB = 1,
        [int]$WsusInventoryInGB = 1,
        [int]$WsusApiRemoting30InGB = 2
    )
    
    Try {
        # Attempt to load the module, throw error if not found
        Import-Module -Name WebAdministration -ErrorAction Stop
        Write-Verbose "Successfully loaded WebAdministration module"
    } Catch {
        # Throw a terminating error with a custom message
        Throw "Failed to load required module 'WebAdministration': $($_.Exception.Message)"
    }
    
    # Verify WSUS Administration site exists
    Try {
        $wsusSite = Get-Website -Name "WSUS Administration" -ErrorAction Stop
        If (-not $wsussite) {
            Throw "WSUS Administration site not found"
        }
        Write-Verbose "WSUS Administration site found"
    } Catch {
        Throw "Failed to verify WSUS Administration site: $($_.Exception.Message)"
    }
    
    $WsusPools = @"
[
    {
        "NewAppPool": "WsusPool",
        "WebApplication": "WsusPool",
        "MemoryLimit": $($RootWsusPool)
    },
    {
        "NewAppPool": "WsusReportingWebService",
        "WebApplication": "ReportingWebService",
        "MemoryLimit": $($WsusReportingWebServiceInGB)
    },
    {
        "NewAppPool": "WsusClientWebService",
        "WebApplication": "ClientWebService",
        "MemoryLimit": $($WsusClientWebServiceInGB)
    },
    {
        "NewAppPool": "WsusSimpleAuthWebService",
        "WebApplication": "SimpleAuthWebService",
        "MemoryLimit": $($WsusSimpleAuthWebServiceInGB)
    },
    {
        "NewAppPool": "WsusServerSyncWebService",
        "WebApplication": "ServerSyncWebService",
        "MemoryLimit": $($WsusServerSyncWebServiceInGB)
    },
    {
        "NewAppPool": "WsusDssAuthWebService",
        "WebApplication": "DssAuthWebService",
        "MemoryLimit": $($WsusDssAuthWebServiceInGB)
    },
    {
        "NewAppPool": "WsusInventory",
        "WebApplication": "Inventory",
        "MemoryLimit": $($WsusInventoryInGB)
    },
    {
        "NewAppPool": "WsusApiRemoting30",
        "WebApplication": "ApiRemoting30",
        "MemoryLimit": $($WsusApiRemoting30InGB)
    }
]
"@ | ConvertFrom-Json
    
    ForEach ($WsusPool In $WsusPools) {
        Try {
            # Check if the application pool exists (use WebAdministration provider for
            # consistency with the create path so $pool | Set-Item works)
            $pool = Get-Item "IIS:\AppPools\$($WsusPool.NewAppPool)" -ErrorAction SilentlyContinue
            
            # Convert GB to KB
            $MemoryLimit = $WsusPool.MemoryLimit * 1024 * 1024
            
            If (-not $pool) {
                # Pool does not exist, so create a new one
                Write-Verbose "Creating new application pool: $($WsusPool.NewAppPool)"
                
                $newpool = New-WebAppPool -Name $WsusPool.NewAppPool -ErrorAction Stop
                $newpool.processModel.identityType = "NetworkService"
                $newpool.processModel.idleTimeout = "0"
                $newpool.queueLength = 2000
                $newpool.processModel.pingingEnabled = $false
                $newpool.recycling.periodicRestart.time = "0.00:00:00"
                $newpool.recycling.periodicRestart.privateMemory = [int]$MemoryLimit
                $newpool | Set-Item -ErrorAction Stop
                
                Write-Host "Created application pool: $($WsusPool.NewAppPool) with memory limit $($WsusPool.MemoryLimit) GB" -ForegroundColor Green
            } Else {
                # Pool exists, update its configuration
                Write-Verbose "Updating existing application pool: $($WsusPool.NewAppPool)"
                
                $updated = $false
                
                # Update identity type
                If ($pool.processModel.identityType -ne "NetworkService") {
                    $pool.processModel.identityType = "NetworkService"
                    $updated = $true
                }
                
                # Update idle timeout
                If ($pool.processModel.idleTimeout -ne "0") {
                    $pool.processModel.idleTimeout = "0"
                    $updated = $true
                }
                
                # Update queue length
                If ($pool.queueLength -ne 2000) {
                    $pool.queueLength = 2000
                    $updated = $true
                }
                
                # Update pinging
                If ($pool.processModel.pingingEnabled -ne $false) {
                    $pool.processModel.pingingEnabled = $false
                    $updated = $true
                }
                
                # Update periodic restart time
                If ($pool.recycling.periodicRestart.time -ne "0.00:00:00") {
                    $pool.recycling.periodicRestart.time = "0.00:00:00"
                    $updated = $true
                }
                
                # Update memory limit
                If ([int64]$pool.recycling.periodicRestart.privateMemory -ne [int64]$MemoryLimit) {
                    $pool.recycling.periodicRestart.privateMemory = [int]$MemoryLimit
                    $updated = $true
                }
                
                If ($updated) {
                    $pool | Set-Item -ErrorAction Stop
                    Write-Host "Updated application pool: $($WsusPool.NewAppPool) with memory limit $($WsusPool.MemoryLimit) GB" -ForegroundColor Yellow
                } Else {
                    Write-Verbose "No changes needed for application pool: $($WsusPool.NewAppPool)"
                }
            }
            
            # Update the application to use the pool (skip root WsusPool)
            If ($WsusPool.WebApplication -ne 'WsusPool') {
                Try {
                    $appPath = "IIS:\Sites\WSUS Administration\$($WsusPool.WebApplication)"
                    
                    # Verify the application exists
                    If (Test-Path $appPath) {
                        $currentPool = Get-ItemProperty $appPath -Name applicationPool -ErrorAction Stop
                        
                        If ($currentPool.Value -ne $WsusPool.NewAppPool) {
                            Set-ItemProperty $appPath -Name applicationPool -Value $WsusPool.NewAppPool -ErrorAction Stop
                            Write-Host "Assigned $($WsusPool.WebApplication) to pool: $($WsusPool.NewAppPool)" -ForegroundColor Cyan
                        } Else {
                            Write-Verbose "$($WsusPool.WebApplication) already assigned to $($WsusPool.NewAppPool)"
                        }
                    } Else {
                        Write-Warning "Web application not found: $($WsusPool.WebApplication)"
                    }
                } Catch {
                    Write-Error "Failed to update web application $($WsusPool.WebApplication): $($_.Exception.Message)"
                }
            }
            
        } Catch {
            Write-Error "Failed to process application pool $($WsusPool.NewAppPool): $($_.Exception.Message)"
            Continue
        }
    }
    
    Write-Host "`nWSUS Application Pool configuration completed" -ForegroundColor Green
}

# Run the function when the script is executed directly
Set-WSUSAppPools -Verbose