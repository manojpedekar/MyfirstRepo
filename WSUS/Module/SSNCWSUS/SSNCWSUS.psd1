@{
    RootModule        = 'SSNCWSUS.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'e5d83987-a60e-4e1c-9800-c66f012e01ee'
    Author            = 'Pete Demers'
    CompanyName       = 'SS&C'
    Copyright         = '(c) SS&C. All rights reserved.'
    Description       = 'SS&C-flavored WSUS administration: server setup, WID/SUSDB query building, target group + approval rule management, replica configuration, WSUS-Reports event log forwarding.'
    PowerShellVersion = '5.1'

    # Modules loaded lazily inside individual functions rather than declared here,
    # so the module imports cleanly on non-WSUS-server machines.
    RequiredModules   = @()

    FunctionsToExport = @(
        'Test-IsUsingWindowsInternalDatabase'
        'Build-SQLGetWSUSEvents'
        'Build-SetWIDServerName'
        'Build-vw_GetWSUSEvents'
        'Build-fn_GetSummarizationState'
        'Build-WIDMemoryLimitSQL'
        'Insert-NewWSUSEvents'
        'Invoke-WSUSQuery'
        'Get-WSUSConfig'
        'Test-IISWebsiteExists'
        'Install-WSUSFeatures'
        'Install-WSUSServer'
        'Set-SSNCReplicaWSUSSettings'
        'Add-TargetGroupToApprovalRule'
        'Remove-TargetGroupFromApprovalRule'
        'New-WSUSTargetGroup'
        'Replace-SpecialCharacters'
        'Publish-AppIDData'
        'Initialize-RawDrive'
        'Get-WSUSBaseline'
        'Initialize-WSUSDisks'
        'Update-CDROMDriveLetter'
        'Connect-WSUS'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @('WSUS', 'WindowsUpdate', 'SUSDB', 'SSNC')
        }
    }
}
