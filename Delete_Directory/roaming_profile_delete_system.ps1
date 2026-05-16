# Prompt for username
$username = Read-Host "Enter the username of the user whose roaming profile is to be deleted"

$profileRoot = "D:\IND_RoamingProfiles"
$profilePath = Join-Path $profileRoot ($username + ".v6")

if (-not (Test-Path $profilePath)) {
    Write-Host "Profile directory not found: $profilePath" -ForegroundColor Red
    exit 1
}

Write-Host "Profile found: $profilePath" -ForegroundColor Yellow

$taskName = "DeleteRoamingProfile_$username"

# SYSTEM deletion script (inline)
$psCommand = @"
if (Test-Path '$profilePath') {
    Remove-Item -Path '$profilePath' -Recurse -Force -ErrorAction SilentlyContinue
}
"@

$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$psCommand`""

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$task = New-ScheduledTask -Action $action -Principal $principal

# Register and run task
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

Start-ScheduledTask -TaskName $taskName

# Wait a few seconds to allow the scheduled task to start and deletion to begin
Start-Sleep -Seconds 5

# Wait until folder is gone (max 90 seconds)
$timeout = 90
while ((Test-Path $profilePath) -and $timeout -gt 0) {
    Start-Sleep -Seconds 3
    $timeout -= 3
    # Extra check: refresh folder info to avoid caching
    [System.IO.Directory]::RefreshCache()
}

# Cleanup scheduled task
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Final verification
if (-not (Test-Path $profilePath)) {
    Write-Host "Roaming profile for '$username' has been successfully deleted." -ForegroundColor Green
} else {
    Write-Host "FAILED to delete roaming profile for '$username'. Folder still exists." -ForegroundColor Red
}
