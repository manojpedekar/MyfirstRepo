<#
    .SYNOPSIS
        A brief description of the Update-WIDServer.ps1 file.
    
    .DESCRIPTION
        A description of the file.
    
    .PARAMETER MemoryInGB
        A description of the MemoryInGB parameter.
    
    .PARAMETER DBServiceName
        A description of the DBServiceName parameter.
    
    .NOTES
        ===========================================================================
        Created with:     SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
        Created on:       12/13/2024 3:17 PM
        Created by:       DT234083
        Organization:     SS&C
        Filename:
        ===========================================================================
#>
Param
(
    [Parameter(Mandatory = $false)]
    [int]$MemoryInGB = 16,
    [string]$DBServiceName = 'MSSQL$MICROSOFT##WID'
)
Import-Module .\SSNCWSUS.psm1

###########################################
##                 VARS                  ##
###########################################


###########################################
##               SCRIPT                  ##
###########################################


Invoke-WSUSQuery -Query (Build-SetWIDServerName) -Database master
Invoke-WSUSQuery -Query (Build-WIDMemoryLimitSQL -MemoryInGB $MemoryInGB) -Database master

Invoke-WSUSQuery -Query (Build-fn_GetSummarizationState) -Database SUSDB
Invoke-WSUSQuery -Query (Build-vw_GetWSUSEvents) -Database SUSDB

Restart-Service $DBServiceName


# Initialize 
# Install



