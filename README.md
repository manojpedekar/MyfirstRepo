# Windows_Powershell
Windows admin regular scripts
This is will be more organized repo as we have done testing before.

#shorter the pwd path in the terminal
function prompt { "$(Split-Path -Leaf (Get-Location))> " }

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Confirm:$false -Force
