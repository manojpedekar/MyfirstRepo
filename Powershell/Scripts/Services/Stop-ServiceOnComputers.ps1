Function Stop-ServiceOnComputers {
    <#
    .SYNOPSIS
        Stops services on multiple computers based on full or partial service name.
    
    .DESCRIPTION
        This function searches for services by name (supports wildcards) on one or more
        computers, displays their current state, and stops them if they are running.
    
    .PARAMETER ServiceName
        Full or partial service name. Supports wildcards (*).
        Example: "spooler", "*print*", "win*"
    
    .PARAMETER ComputerName
        One or more computer names to target. Defaults to local computer.
    
    .PARAMETER Credential
        PSCredential object for authentication to remote computers.
    
    .PARAMETER Force
        Forces the service to stop even if it has dependent services.
    
    .PARAMETER WhatIf
        Shows what would happen if the function runs without actually stopping services.
    
    .PARAMETER Confirm
        Prompts for confirmation before stopping each service.
    
    .EXAMPLE
        Stop-ServiceOnComputers -ServiceName "spooler" -ComputerName "Server01", "Server02"
        
    .EXAMPLE
        Stop-ServiceOnComputers -ServiceName "*print*" -ComputerName (Get-Content C:\servers.txt) -Force
        
    .EXAMPLE
        $cred = Get-Credential
        Stop-ServiceOnComputers -ServiceName "MyService" -ComputerName "RemotePC" -Credential $cred
    
    .NOTES
        Created by:   DT234083
        Organization: SS&C
        Requires:     PowerShell 3.0+, Administrator privileges on target computers
    #>
    
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ServiceName,
        [Parameter(Mandatory = $true, Position = 1)]
        [string[]]$ComputerName,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    Begin {
        Write-Host "`n=== Service Stop Operation ===" -ForegroundColor Cyan
        Write-Host "Service Pattern: $ServiceName" -ForegroundColor White
        Write-Host "Target Computers: $($ComputerName.Count)`n" -ForegroundColor White
        
        # Initialize results array
        $Results = @()
    }
    
    Process {
        ForEach ($Computer In $ComputerName) {
            Write-Host "Processing: $Computer" -ForegroundColor Yellow
            Write-Host $("-" * 60) -ForegroundColor Gray
            
            # Build parameters for Get-Service
            $GetServiceParams = @{
                Name = $ServiceName
            }
            
            # Add ComputerName if not local
            If ($Computer -ne $env:COMPUTERNAME -and $Computer -ne 'localhost' -and $Computer -ne '.') {
                $GetServiceParams['ComputerName'] = $Computer
            }
            
            # Test connectivity first
            $pingResult = Test-Connection -ComputerName $Computer -Count 1 -Quiet -ErrorAction SilentlyContinue
            
            If (-not $pingResult) {
                Write-Warning "Unable to reach $Computer - Skipping"
                
                $Results += [PSCustomObject]@{
                    ComputerName   = $Computer
                    ServiceName    = $ServiceName
                    DisplayName    = 'N/A'
                    OriginalStatus = 'Unreachable'
                    FinalStatus    = 'Unreachable'
                    Success        = $false
                    Error          = 'Computer unreachable'
                }
                
                Write-Host ""
                Continue
            }
            
            # Get matching services
            Try {
                If ($Credential -and $Computer -ne $env:COMPUTERNAME) {
                    $Services = Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
                        Param ($svcName)
                        Get-Service -Name $svcName
                    } -ArgumentList $ServiceName -ErrorAction Stop
                } Else {
                    $Services = Get-Service @GetServiceParams
                }
                
                If (-not $Services) {
                    Write-Warning "No services matching '$ServiceName' found on $Computer"
                    
                    $Results += [PSCustomObject]@{
                        ComputerName   = $Computer
                        ServiceName    = $ServiceName
                        DisplayName    = 'N/A'
                        OriginalStatus = 'Not Found'
                        FinalStatus    = 'Not Found'
                        Success        = $false
                        Error          = 'Service not found'
                    }
                    
                    Write-Host ""
                    Continue
                }
                
                # Process each matching service
                ForEach ($Service In $Services) {
                    $OriginalStatus = $Service.Status
                    
                    Write-Host "  Service: $($Service.DisplayName)" -ForegroundColor Cyan
                    Write-Host "  Name: $($Service.Name)" -ForegroundColor White
                    Write-Host "  Current Status: $OriginalStatus" -ForegroundColor $(If ($OriginalStatus -eq 'Running') { 'Green' } Else { 'Yellow' })
                    
                    # Check for dependent services if Force is not used
                    If (-not $Force) {
                        $DependentServices = $Service.DependentServices | Where-Object { $_.Status -eq 'Running' }
                        If ($DependentServices) {
                            Write-Warning "  Service has $($DependentServices.Count) dependent service(s) running:"
                            $DependentServices | ForEach-Object {
                                Write-Host "    - $($_.DisplayName) ($($_.Name))" -ForegroundColor Yellow
                            }
                        }
                    }
                    
                    # Only stop if service is running
                    If ($OriginalStatus -eq 'Running') {
                        If ($PSCmdlet.ShouldProcess("$Computer\$($Service.Name)", "Stop Service")) {
                            Try {
                                Write-Host "  Stopping service..." -ForegroundColor Yellow -NoNewline
                                
                                If ($Credential -and $Computer -ne $env:COMPUTERNAME) {
                                    Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
                                        Param ($svcName,
                                            $useForce)
                                        $svc = Get-Service -Name $svcName
                                        If ($useForce) {
                                            Stop-Service -Name $svcName -Force -ErrorAction Stop
                                        } Else {
                                            Stop-Service -Name $svcName -ErrorAction Stop
                                        }
                                    } -ArgumentList $Service.Name, $Force -ErrorAction Stop
                                } Else {
                                    If ($Force) {
                                        Stop-Service -InputObject $Service -Force -ErrorAction Stop
                                    } Else {
                                        Stop-Service -InputObject $Service -ErrorAction Stop
                                    }
                                }
                                
                                # Verify service stopped
                                Start-Sleep -Seconds 2
                                $Service.Refresh()
                                
                                Write-Host " SUCCESS" -ForegroundColor Green
                                Write-Host "  New Status: $($Service.Status)" -ForegroundColor Green
                                
                                $Results += [PSCustomObject]@{
                                    ComputerName   = $Computer
                                    ServiceName    = $Service.Name
                                    DisplayName    = $Service.DisplayName
                                    OriginalStatus = $OriginalStatus
                                    FinalStatus    = $Service.Status
                                    Success        = $true
                                    Error          = $null
                                }
                                
                            } Catch {
                                Write-Host " FAILED" -ForegroundColor Red
                                Write-Warning "  Error: $($_.Exception.Message)"
                                
                                $Results += [PSCustomObject]@{
                                    ComputerName   = $Computer
                                    ServiceName    = $Service.Name
                                    DisplayName    = $Service.DisplayName
                                    OriginalStatus = $OriginalStatus
                                    FinalStatus    = $OriginalStatus
                                    Success        = $false
                                    Error          = $_.Exception.Message
                                }
                            }
                        }
                    } Else {
                        Write-Host "  Status: Service is already stopped" -ForegroundColor Gray
                        
                        $Results += [PSCustomObject]@{
                            ComputerName   = $Computer
                            ServiceName    = $Service.Name
                            DisplayName    = $Service.DisplayName
                            OriginalStatus = $OriginalStatus
                            FinalStatus    = $OriginalStatus
                            Success        = $true
                            Error          = 'Already stopped'
                        }
                    }
                    
                    Write-Host ""
                }
                
            } Catch {
                Write-Error "Failed to access services on $Computer : $($_.Exception.Message)"
                
                $Results += [PSCustomObject]@{
                    ComputerName   = $Computer
                    ServiceName    = $ServiceName
                    DisplayName    = 'N/A'
                    OriginalStatus = 'Error'
                    FinalStatus    = 'Error'
                    Success        = $false
                    Error          = $_.Exception.Message
                }
                
                Write-Host ""
            }
        }
    }
    
    End {
        # Summary Report
        Write-Host "`n=== Operation Summary ===" -ForegroundColor Cyan
        Write-Host $("=" * 60) -ForegroundColor Gray
        
        $SuccessCount = ($Results | Where-Object { $_.Success -and $_.OriginalStatus -eq 'Running' }).Count
        $AlreadyStoppedCount = ($Results | Where-Object { $_.Error -eq 'Already stopped' }).Count
        $FailedCount = ($Results | Where-Object { -not $_.Success -and $_.OriginalStatus -ne 'Already stopped' }).Count
        
        Write-Host "Services Stopped: $SuccessCount" -ForegroundColor Green
        Write-Host "Already Stopped: $AlreadyStoppedCount" -ForegroundColor Gray
        Write-Host "Failed: $FailedCount" -ForegroundColor $(If ($FailedCount -gt 0) { 'Red' } Else { 'Gray' })
        Write-Host ""
        
        # Return results object
        Return $Results
    }
}