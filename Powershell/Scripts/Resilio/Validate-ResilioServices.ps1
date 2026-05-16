Function Test-IsAdministrator {
    Try {
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
        Return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } Catch {
        Write-Error "Failed to determine elevation status: $_"
        Return $false
    }
}

Function Write-ServiceLog {
    Param
    (
        [string]$Message,
        [int]$EventID,
        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
        [string]$EntryType = 'Information',
        [string]$logName = 'ServiceMonitor',
        [string]$source = 'ServiceMonitorScript'
    )
    
    # Ensure the custom source and log exist
    If (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
        New-EventLog -LogName $logName -Source $source
    }
    
    $eventLogParams = @{
        LogName   = $logName
        Source    = $source
        EntryType = $EntryType
        EventId   = $EventID
        Message   = $Message
    }
    
    Write-EventLog @eventLogParams
}

Function Start-ServiceWithRetry {
    Param (
        [Parameter(Mandatory)]
        [string]$ServiceName,
        [int]$maxAttempts = 3,
        [int]$WaitSeconds = 2
    )
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    If (-not $service) {
        $msg = "Service '$ServiceName' not found."
        Write-Error $msg
        Write-ServiceLog -Message $msg -EventID 1001 -EntryType 'Error'
        Exit 1
    }
    
    If ($service.Status -eq 'Running') {
        $msg = "Service '$ServiceName' is already running."
        Write-Output $msg
        Write-ServiceLog -Message $msg -EventID 1002
        Return
    }
    
    $attempt = 0
    
    While ($attempt -lt $maxAttempts) {
        $attempt++
        $msg = "Attempt $attempt : Starting service '$ServiceName'..."
        Write-Output $msg
        Write-ServiceLog -Message $msg -EventID 1003
        
        Try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            Start-Sleep -Seconds $WaitSeconds
            $service.Refresh()
            
            If ($service.Status -eq 'Running') {
                $msg = "Service '$ServiceName' started successfully."
                Write-Output $msg
                Write-ServiceLog -Message $msg -EventID 1004
                Return
            }
        } Catch {
            $msg = "Attempt $attempt failed for service '$ServiceName': $_"
            Write-Warning $msg
            Write-ServiceLog -Message $msg -EventID 1005 -EntryType 'Warning'
        }
        
        Start-Sleep -Seconds $WaitSeconds
        $service.Refresh()
    }
    
    $msg = "Failed to start service '$ServiceName' after $maxAttempts attempts."
    Write-Error $msg
    Write-ServiceLog -Message $msg -EventID 1006 -EntryType 'Error'
    Exit 1
}

Function Ensure-ResilioTaskExists {
    Param (
        [string]$TaskName = "\Validate Resilio Services",
        [string]$TaskXmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>2025-07-12T10:30:43.9931406</Date>
    <Author>sscclient161\s234083-adm</Author>
    <Description>This scheduled task will execute a script to validate if the Resilio services are running.  Results are logged to the Windows Event Log 'ServiceMonitor'</Description>
    <URI>\Validate Resilio Services</URI>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
        <Duration>P1D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2025-07-12T10:35:00</StartBoundary>
      <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-file C:\Scripts\Validate-ResilioServices.ps1</Arguments>
      <WorkingDirectory>C:\Scripts</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
    )
    
    Try {
        $existing = Get-ScheduledTask -TaskName ($TaskName -replace '^\\') -ErrorAction SilentlyContinue
        If ($existing) {
            $msg = "Scheduled task '$TaskName' already exists."
            Write-Host $msg
            #Write-ServiceLog -Message $msg -EventID 1000
            Return
        }
        
        # Write XML to temporary file
        $tempXml = [System.IO.Path]::GetTempFileName() + ".xml"
        $TaskXmlContent | Out-File -FilePath $tempXml -Encoding Unicode
        
        # Register the task
        Register-ScheduledTask -Xml (Get-Content $tempXml | Out-String) -TaskName ($TaskName -replace '^\\') -Force
        
        $msg = "Scheduled task '$TaskName' has been created successfully."
        Write-Host $msg
        Write-ServiceLog -Message $msg -EventID 1007
        Remove-Item $tempXml -Force
    } Catch {
        $msg = "Failed to create scheduled task '$TaskName': $_"
        Write-Error $msg
        Write-ServiceLog -Message $msg -EventID 1008 -EntryType Error
    }
}

$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

If (!(Test-IsAdministrator)) {
    Write-Host "Not running as administrator."
    exit 1
}

If ($identity.Name -ne 'NT AUTHORITY\SYSTEM') {
    # prevents runing the schedule task setup if running as system.  The assumption is the task is already setup and functional.
    # only the scheduled task should be running as system.  An engineer will be setting up the task using an admin account
    Ensure-ResilioTaskExists
}

If ($identity.Name -eq 'NT AUTHORITY\SYSTEM') {
    # Wildcard pattern for services to monitor to ensure we check all instances of the service
    $ServicesToMonitor = "connectsvc*"
    
    ForEach ($ServiceToMonitor In (Get-Service -Name $ServicesToMonitor)) {
        Start-ServiceWithRetry -ServiceName $ServiceToMonitor.Name
    }
}

