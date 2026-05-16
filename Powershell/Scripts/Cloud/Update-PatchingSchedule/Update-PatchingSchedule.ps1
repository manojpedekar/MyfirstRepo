<#
    .SYNOPSIS
        Sets per-instance patching schedules on SS&C cloud instances from a
        CSV input, falling back to per-environment defaults when no override
        is specified.

    .DESCRIPTION
        For each row in the input CSV, the script:
          1. Looks up the current cloud instance via Get-Instance.
          2. Records the existing patchingGroup as CloudValue.
          3. Chooses the schedule to apply, in priority order:
             a. The row's DesiredSched, if it is a valid schedule.
             b. The current patchingGroup, if it is a valid schedule.
             c. The default schedule for the row's Environment column.
             d. The default schedule for the SubProject's Environment.
          4. If the chosen schedule differs from the current schedule,
             calls Set-Instance to apply it.

        Originally maintained as a self-contained script with inline copies
        of helper functions. Refactored 2026-05-11 to use the Cloud-API
        module - the module's Get-Instance, Get-SubProject, and Set-Instance
        cover the same API surface under cleaner names.

    .PARAMETER InputCsv
        Path to the input CSV. See README.md for schema. Defaults to
        .\CloudNeedPatchSched.csv.

    .EXAMPLE
        .\Update-PatchingSchedule.ps1 -InputCsv C:\temp\sched-update.csv
#>

Param (
	[string]$InputCsv = ".\CloudNeedPatchSched.csv"
)

Import-Module Cloud-API

$ErrorList = [System.Collections.ArrayList]@()

$Computers = Import-Csv $InputCsv

# Valid patching schedules at the SS&C Cloud portal
$ValidSchedules = @(
	'1st-sun-3am-5am',
	'1st-sun-12am-4am',
	'1st-sun-2am-5am',
	'2nd-sun-12am-4am',
	'2nd-sun-2am-5am',
	'3rd-tues-6pm-10pm',
	'3rd-tues-10pm-4am',
	'3rd-thurs-6pm-10pm',
	'3rd-thurs-10pm-4am',
	'3rd-sat-10pm-4am',
	'3rd-sun-2am-5am',
	'4th-sun-2am-5am',
	'self-managed'
)

# Default patching schedules per environment
$DefaultSchedules = @("environment,schedule",
	"dev,3rd-tues-10pm-4am",
	"devtest,3rd-tues-10pm-4am",
	"nonprod,3rd-tues-10pm-4am",
	"prod,4th-sun-2am-5am",
	"qa,3rd-tues-10pm-4am",
	"sandbox,3rd-tues-10pm-4am",
	"uat,3rd-tues-10pm-4am"
) | ConvertFrom-Csv

$i = 0
ForEach ($Computer In $Computers) {
	$i++
	Write-Host "$i -- $($Computer.vm_name)"
	Try {

		# Clear the AssignedSchedule var
		$AssignedSchedule = $null

		# Get the current cloud instance details
		$CloudInstance = Get-Instance -instanceId $Computer.vm_name

		# Record the current patch schedule
		$Computer.CloudValue = $CloudInstance.patchingGroup

		If ($CloudInstance.patchingGroup -in $ValidSchedules) {
			# The current schedule is a valid schedule
			$AssignedSchedule = $CloudInstance.patchingGroup
		}

		If ($Computer.DesiredSched -in $ValidSchedules) {
			# The desired schedule is set and valid - use it
			# (overrides the existing patching group)
			$AssignedSchedule = $Computer.DesiredSched
		}

		If ($AssignedSchedule -eq $null -and $Computer.Environment -ne $null) {
			# No schedule yet. Look up the default by the input row's environment.
			$AssignedSchedule = ($DefaultSchedules | Where-Object { $_.Environment -eq $Computer.Environment }).schedule
		}

		If ($AssignedSchedule -eq $null) {
			# Still nothing. Look up the SubProject's environment and apply
			# its default.
			$SubProjectDetails = Get-SubProject -subprojectId $CloudInstance.subprojectId

			# Record the vm environment tag from the subproject
			$Computer.Environment = $SubProjectDetails.Environment

			$AssignedSchedule = ($DefaultSchedules | Where-Object { $_.Environment -eq $SubProjectDetails.Environment }).schedule
		}

		# If the schedules do not match, push the change to the cloud
		If ($CloudInstance.patchingGroup -ne $AssignedSchedule -and $AssignedSchedule -ne $null) {
			$Computer.DesiredSched = $AssignedSchedule
			$Computer.SetResult = Set-Instance -instanceId $CloudInstance.id -patchingGroup $AssignedSchedule
		}
	} Catch {
		[void]$ErrorList.add($Computer)
	}
}
