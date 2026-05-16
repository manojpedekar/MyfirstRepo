# Cloud

Scripts that exercise the SS&C Cloud portal API.

All scripts here are thin wrappers around the `Cloud-API` module
under `Powershell/Modules/Cloud-API/`. Import the module
(`Import-Module Cloud-API`) and the module prompts for an API key on
first use.

## Contents

- `Update-PatchingSchedule/` - sets per-instance patching schedules
  from a CSV input, falling back to per-environment defaults when no
  override is given. See its README for the input CSV schema.

## History

Several one-off scripts that originally lived here were moved to
`Powershell/Scripts/ScriptGarage/` as FROZEN HISTORICAL RECORDs:

- `Add-ResilioConsoleAccess.ps1` (was `Add-CloudSecurityRule.ps1`)
- `New-LHSQLVolumes.ps1` (was `New-CloudDisk.ps1`)
- `Open-LHDevToProdRDP.ps1` (was `New-NetAccess.ps1`)
- `Set-SkylineBackupPolicy.ps1` (was `PowerOnSSCCLient01.ps1`)

The `Fix-CloudIDGrain` Salt formula that lived here was moved to
`SaltStates/Fix-CloudIDGrain/`.
