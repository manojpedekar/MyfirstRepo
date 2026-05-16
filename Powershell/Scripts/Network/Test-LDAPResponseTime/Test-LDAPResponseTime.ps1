<#
    .SYNOPSIS
        Measure the response time of LDAP queries to the DCs and load balancers within a given domain.
    
    .DESCRIPTION
        Measure the response time of LDAP queries to the DCs and load balancers within a given domain.
    
    .PARAMETER TargetDomain
        The domain name of the devices to be tested.  This parameter only accepts one value.
        
        If present the file <WorkingDir>\Config\<domainname>.cfg will be loaded to test specific devices.
        
        This value will be used to produce a list of all domain controllers with in the domain.
    
    .PARAMETER LDAPUserToQuery
        Name of the user to query in the domain.  The default value is 'krbtgt'.
    
    .PARAMETER WorkingDir
        The directory where the results should be stored.  The default value is $PSScriptRoot.
        
        This directory will be where the following folders will automaticlly be created:  CONFIG, LOGS, OUTPUUT.
    
    .PARAMETER numberoftests
        The number of tiimes each system should bbe tested.  Default value: 5
    
    .PARAMETER SecondsBetweenTests
        The number of seconds to wait between each system test.
    
    .PARAMETER SendToSQL
        When used, the results will be sent to a database.
        
        If specified, the following parameters are mandatory:  SQLServer, SQLDB, SQLTable, SQLSchema.
    
    .PARAMETER SQLServer
        Name of the SQL Server.
    
    .PARAMETER SQLDB
        Name of the SQL database.
    
    .PARAMETER SQLTable
        Name of the SQL table.
    
    .PARAMETER SQLSchema
        Name of the SQL schems.  Default is 'dbo'.
    
    .PARAMETER LDAPPort
        Port to use when querying LDAP. Default is 636.
    
    .PARAMETER SQLPort
        Port to use when connecting to SQL server.  Default is 1433.
    
    .NOTES
        ===========================================================================
        Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.248
        Created on:   	12/20/2024 7:57 AM
        Created by:   	DT234083
        Organization: 	SS&C
        Filename:     	Test-LDAPResponseTime.ps1
        ===========================================================================
        
        The configuration file is a specific file per domain that contains the Load Balancer DNS names as these cannot be pulled from AD
#>
[CmdletBinding()]
Param
(
    [string]$TargetDomain,
    [string]$LDAPUserToQuery = "krbtgt",
    [string]$WorkingDir = $PSScriptRoot,
    [int]$NumberOfTests = 1,
    [int]$SecondsBetweenTests = 1,
    [switch]$SendToSQL,
    [string]$SQLServer = "dskcbisql01.ad.dstsystems.com",
    [string]$SQLDB = "InfrasrtructureInventory",
    [string]$SQLTable = "tb_LDAPResults",
    [string]$SQLSchema = "dbo",
    [int]$LDAPPort = 636,
    [int]$SQLPort = 1433
)

$ScriptVariables = @('TargetDomain', 'LDAPUserToQuery', 'WorkingDir', 'NumberOfTests', 'SecondsBetweenTests', 'SendToSQL', 'SQLServer', 'SQLDB', 'SQLTable', 'SQLSchema', 'LDAPPort', 'SQLPort')

# Check if $TargetDomain is null or empty
If ([string]::IsNullOrEmpty($TargetDomain)) {
    Write-Host "Error: The TargetDomain parameter is required and cannot be empty."
    Write-Host "Usage: .\Test-LDAPResponseTime.ps1 -TargetDomain 'yourdomain.com'"
    Exit 1
}

If ($SendToSQL -and
    (
        [string]::IsNullOrEmpty($SQLServer) -or
        [string]::IsNullOrEmpty($SQLDB) -or
        [string]::IsNullOrEmpty($SQLTable) -or
        [string]::IsNullOrEmpty($SQLSchema)
    )
){
    Write-Warning "SQL Parameters Missing.  -SendToSQL switch used, all SQL parameters are required"
    Exit 1
}

Write-Verbose "Testing DNS Resolution on $TargetDomain"
If (-not(Resolve-DnsName $TargetDomain -ErrorAction SilentlyContinue -DnsOnly)) {
    Write-Warning "DNS Error!  Can not resolve $TargetDomain. Exiting!"
    Exit 1
} Else {
    Write-Verbose "DNS Name Resolution Sucessful: $TargetDomain"
}

###########################################
##               CLASSES                 ##
###########################################
. (Join-Path $PSScriptRoot "class_Test-LDAPResponseTime.ps1")

###########################################
##                 VARS                  ##
###########################################
$TestParams = [LDAPTestParams]::new($TargetDomain, $workingDir, $LDAPUserToQuery, $NumberOfTests)

#array to store results
$TestSystems = New-Object System.Collections.Generic.List[Object]
$ResultsTable = [DatatableManager]::new()

###########################################
##              FUNCTIONS                ##
###########################################
. (Join-Path $PSScriptRoot "Process-Systems.ps1")

###########################################
##               SCRIPT                  ##
###########################################

# Begin logging
Start-Transcript -Path $TestParams.logfileFN

# Display all variables if verbose is specified
If ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    Write-Host "Script Variables"
    Write-Host "------------------------------------------------"
    Get-Variable $ScriptVariables
    Write-Host " "
    Write-Host "Calculated Script Variables"
    Write-Host "------------------------------------------------"
    $TestParams
}

# Read the content of a file and process each line.  Empty or null lines are ignored
If (Test-Path $TestParams.ConfigfileFN) {
    Process-Systems -Records (Get-Content $TestParams.ConfigfileFN) -RecordType "FromFile" | ForEach-Object{
        [void]$TestSystems.Add($_)
        Write-Verbose "File Target Added: $($_.Name)"
    }
} Else {
    Write-Warning "Missing Config: $($TestParams.ConfigfileFN)"
}

Process-Systems -Records (Get-ADDomainController -server $TargetDomain -filter * | Select-Object -ExpandProperty Name) -RecordType "DC" | ForEach-Object{
    [void]$TestSystems.Add($_)
    Write-Verbose "DC Query Target Added: $($_.Name)"
}

If ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $TestSystems | Format-Table -AutoSize
}

$NumberofSystems = $TestSystems.Count
# Run the tests
For ($i = 1; $i -le $NumberOfTests; $i++) {
    $SystemLoop = 0
    
    ForEach ($System In $TestSystems) {
        $SystemLoop++
        Write-Verbose "Loop $i of $NumberOfTests - System $SystemLoop of $NumberofSystems - Testing: $($System.Name)"

        $QueryResults = [LDAPQueryTest]::new(
            $TestParams.LDAPUserToQuery,
            $System.Name,
            $TestParams.TargetDomain,
            $LDAPPort
        )
        
        $ThisResult = [LDAPTestRecord]::NewDataRow(
            $System.Name,
            $System.DeviceType,
            $QueryResults.ResponseTime,
            $QueryResults.Status,
            $TestParams.TestLocation,
            $ResultsTable.DataTable
        )
                
        If ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
            $ThisResult
        }
                       
        Start-Sleep -Seconds $SecondsBetweenTests
    }
}

$ResultsTable.ExportToCSV($TestParams.DatafileFN)

If ($SendToSQL) {
    $ResultsTable.SQLBulkInsert(
        $SQLServer,
        $SQLDB,
        $SQLTable,
        $SQLSchema,
        $SQLPort
    )
}

# Check logfile size and roll if needed
$Log = Get-ChildItem -Path $TestParams.DatafileFN
If ($Log.Length -ge $TestParams.Datafilesize) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($log)
    $extension = [System.IO.Path]::GetExtension($log)
    $newName = "{0}_{1}_{2}" -f $baseName, (Get-Date -Format "yyyy-MM-ddTHH-mm-ss"), $extension
    Rename-Item -Path $Log -NewName $newName
}

Stop-Transcript