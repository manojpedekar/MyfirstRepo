<#
    .SYNOPSIS
        Bulk-applies a standard set of GLOBEOP\perm-* groups to every SMB
        share on the local fileserver, using a hardcoded mapping of share
        name -> group set.

    .DESCRIPTION
        FROZEN HISTORICAL RECORD. Part of a deployable kit
        (Set-GlobeopFileServerPerms/) originally executed 2022-12 against
        43 GLOBEOP fileservers (see ComputerList.txt) to normalize share
        permissions across the estate.

        How the kit was deployed (per distribute.ps1 +
        StartPermissionUpdate.cmd):
          1. From an admin workstation, distribute.ps1 reads
             ComputerList.txt and copies the whole UpdatePerms folder to
             \\<server>\C$\temp\UpdatePerms\ on each target.
          2. StartPermissionUpdate.cmd is then launched on each server;
             it runs C:\temp\UpdatePerms\PsExec.exe -i -s to invoke this
             script as LOCAL SYSTEM in an interactive PowerShell window.
          3. The script iterates Get-SmbShare on the local server, finds
             the matching perm-* groups in $ListofGroups, and adds the
             corresponding ACEs (FC/RW/MD/RO).

        Note: PsExec.exe is NOT in this repo (it was a Sysinternals
        binary that was removed during the build-artifact cleanup). Any
        re-deployment must stage PsExec separately.

        Do not re-run without confirming the $ListofGroups still matches
        AD reality, that ComputerList.txt still reflects the desired
        target set, and that BUILTIN\Administrators is the correct
        new owner.
#>

#C:\temp\PSTools\PsExec.exe -i -s powershell.exe -accepteula

#region Setup
#$host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.size(150, 2000)
#$host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.size(150, 75)

$ListofGroups = @('perm-YKT3FLSPRD2-fs-HFS Restore-FC',
	'perm-YKT3FLSPRD2-fs-HFS Restore-RO',
	'perm-YKT3FLSPRD2-fs-HFS Restore-RW',
	'perm-HRS1FLSPRD15-fs-Acquired Clients-FC',
	'perm-HRS1FLSPRD15-fs-Acquired Clients-RO',
	'perm-HRS1FLSPRD15-fs-Acquired Clients-RW',
	'perm-HRS1FLSPRD15-fs-Development-FC',
	'perm-HRS1FLSPRD15-fs-Development-RO',
	'perm-HRS1FLSPRD15-fs-Development-RW',
	'perm-HRS1FLSPRD15-fs-Dublin Post Log-FC',
	'perm-HRS1FLSPRD15-fs-Dublin Post Log-RO',
	'perm-HRS1FLSPRD15-fs-Dublin Post Log-RW',
	'perm-HRS1FLSPRD15-fs-FundServices-FC',
	'perm-HRS1FLSPRD15-fs-FundServices-RO',
	'perm-HRS1FLSPRD15-fs-FundServices-RW',
	'perm-HRS1FLSPRD15-fs-HR-FC',
	'perm-HRS1FLSPRD15-fs-HR-RO',
	'perm-HRS1FLSPRD15-fs-HR-RW',
	'perm-HRS1FLSPRD15-fs-hrsBadgePrinter-FC',
	'perm-HRS1FLSPRD15-fs-hrsBadgePrinter-RO',
	'perm-HRS1FLSPRD15-fs-hrsBadgePrinter-RW',
	'perm-HRS1FLSPRD15-fs-INDHR-FC',
	'perm-HRS1FLSPRD15-fs-INDHR-RO',
	'perm-HRS1FLSPRD15-fs-INDHR-RW',
	'perm-HRS1FLSPRD15-fs-Legal-FC',
	'perm-HRS1FLSPRD15-fs-Legal-RO',
	'perm-HRS1FLSPRD15-fs-Legal-RW',
	'perm-HRS1FLSPRD15-fs-ManagedServices-FC',
	'perm-HRS1FLSPRD15-fs-ManagedServices-RO',
	'perm-HRS1FLSPRD15-fs-ManagedServices-RW',
	'perm-HRS1FLSPRD15-fs-Mstar-FC',
	'perm-HRS1FLSPRD15-fs-Mstar-RO',
	'perm-HRS1FLSPRD15-fs-Mstar-RW',
	'perm-HRS1FLSPRD15-fs-Operations2-FC',
	'perm-HRS1FLSPRD15-fs-Operations2-RO',
	'perm-HRS1FLSPRD15-fs-Operations2-RW',
	'perm-HRS1FLSPRD15-fs-Partner_SSNC-FC',
	'perm-HRS1FLSPRD15-fs-Partner_SSNC-RO',
	'perm-HRS1FLSPRD15-fs-Partner_SSNC-RW',
	'perm-HRS1FLSPRD15-fs-PE Migration Checklist-FC',
	'perm-HRS1FLSPRD15-fs-PE Migration Checklist-RO',
	'perm-HRS1FLSPRD15-fs-PE Migration Checklist-RW',
	'perm-HRS1FLSPRD15-fs-Projects-FC',
	'perm-HRS1FLSPRD15-fs-Projects-RO',
	'perm-HRS1FLSPRD15-fs-Projects-RW',
	'perm-HRS1FLSPRD15-fs-QA-FC',
	'perm-HRS1FLSPRD15-fs-QA-RO',
	'perm-HRS1FLSPRD15-fs-QA-RW',
	'perm-HRS1FLSPRD15-fs-Systems-FC',
	'perm-HRS1FLSPRD15-fs-Systems-RO',
	'perm-HRS1FLSPRD15-fs-Systems-RW',
	'perm-HRS1FLSPRD15-fs-TidalCiti-FC',
	'perm-HRS1FLSPRD15-fs-TidalCiti-RO',
	'perm-HRS1FLSPRD15-fs-TidalCiti-RW',
	'perm-HRS1FLSPRD4-fs-aml_pythagoras-FC',
	'perm-HRS1FLSPRD4-fs-aml_pythagoras-RO',
	'perm-HRS1FLSPRD4-fs-aml_pythagoras-RW',
	'perm-HRS1FLSPRD4-fs-AutoGenevaReports-FC',
	'perm-HRS1FLSPRD4-fs-AutoGenevaReports-RO',
	'perm-HRS1FLSPRD4-fs-AutoGenevaReports-RW',
	'perm-HRS1FLSPRD4-fs-CIFS_Cloud-FC',
	'perm-HRS1FLSPRD4-fs-CIFS_Cloud-RO',
	'perm-HRS1FLSPRD4-fs-CIFS_Cloud-RW',
	'perm-HRS1FLSPRD4-fs-Collateral-FC',
	'perm-HRS1FLSPRD4-fs-Collateral-RO',
	'perm-HRS1FLSPRD4-fs-Collateral-RW',
	'perm-HRS1FLSPRD4-fs-Operations-FC',
	'perm-HRS1FLSPRD4-fs-Operations-RO',
	'perm-HRS1FLSPRD4-fs-Operations-RW',
	'perm-HRS1FLSPRD4-fs-TradeDetail-FC',
	'perm-HRS1FLSPRD4-fs-TradeDetail-RO',
	'perm-HRS1FLSPRD4-fs-TradeDetail-RW',
	'perm-LDN1FLSPRD3-fs-Admin-FC',
	'perm-LDN1FLSPRD3-fs-Admin-RO',
	'perm-LDN1FLSPRD3-fs-Admin-RW',
	'perm-LDN1FLSPRD3-fs-CSO-FC',
	'perm-LDN1FLSPRD3-fs-CSO-RO',
	'perm-LDN1FLSPRD3-fs-CSO-RW',
	'perm-LDN1FLSPRD3-fs-EAS_TEMP-FC',
	'perm-LDN1FLSPRD3-fs-EAS_TEMP-RO',
	'perm-LDN1FLSPRD3-fs-EAS_TEMP-RW',
	'perm-LDN1FLSPRD3-fs-Home1-FC',
	'perm-LDN1FLSPRD3-fs-Home1-RO',
	'perm-LDN1FLSPRD3-fs-Home1-RW',
	'perm-LDN1FLSPRD3-fs-Home2-FC',
	'perm-LDN1FLSPRD3-fs-Home2-RO',
	'perm-LDN1FLSPRD3-fs-Home2-RW',
	'perm-LDN1FLSPRD3-fs-Home3-FC',
	'perm-LDN1FLSPRD3-fs-Home3-RO',
	'perm-LDN1FLSPRD3-fs-Home3-RW',
	'perm-LDN1FLSPRD3-fs-ldn1_exuser_archive-FC',
	'perm-LDN1FLSPRD3-fs-ldn1_exuser_archive-RO',
	'perm-LDN1FLSPRD3-fs-ldn1_exuser_archive-RW',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive-FC',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive-RO',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive-RW',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive2-FC',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive2-RO',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive2-RW',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive3-FC',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive3-RO',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive3-RW',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive4-FC',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive4-RO',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive4-RW',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive5-FC',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive5-RO',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive5-RW',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive6-FC',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive6-RO',
	'perm-LDN1FLSPRD3-fs-Onlineldn1emailarchive6-RW',
	'perm-LDN1FLSPRD3-fs-OVF_Files-FC',
	'perm-LDN1FLSPRD3-fs-OVF_Files-RO',
	'perm-LDN1FLSPRD3-fs-OVF_Files-RW',
	'perm-LDN1FLSPRD3-fs-SSCHome-FC',
	'perm-LDN1FLSPRD3-fs-SSCHome-RO',
	'perm-LDN1FLSPRD3-fs-SSCHome-RW',
	'perm-LDN1FLSPRD3-fs-UKMarketingArchive-FC',
	'perm-LDN1FLSPRD3-fs-UKMarketingArchive-RO',
	'perm-LDN1FLSPRD3-fs-UKMarketingArchive-RW',
	'perm-LDN1FLSPRD3-fs-UK_OpsArchive-FC',
	'perm-LDN1FLSPRD3-fs-UK_OpsArchive-RO',
	'perm-LDN1FLSPRD3-fs-UK_OpsArchive-RW',
	'perm-LDN1FLSPRD5-fs-Convergence-FC',
	'perm-LDN1FLSPRD5-fs-Convergence-RO',
	'perm-LDN1FLSPRD5-fs-Convergence-RW',
	'perm-LDN1FLSPRD5-fs-Departments-FC',
	'perm-LDN1FLSPRD5-fs-Departments-RO',
	'perm-LDN1FLSPRD5-fs-Departments-RW',
	'perm-LDN1FLSPRD5-fs-Depositary-FC',
	'perm-LDN1FLSPRD5-fs-Depositary-RO',
	'perm-LDN1FLSPRD5-fs-Depositary-RW',
	'perm-LDN1FLSPRD5-fs-Dubai-FC',
	'perm-LDN1FLSPRD5-fs-Dubai-RO',
	'perm-LDN1FLSPRD5-fs-Dubai-RW',
	'perm-LDN1FLSPRD5-fs-GDPR-FC',
	'perm-LDN1FLSPRD5-fs-GDPR-RO',
	'perm-LDN1FLSPRD5-fs-GDPR-RW',
	'perm-LDN1FLSPRD5-fs-GoBook-FC',
	'perm-LDN1FLSPRD5-fs-GoBook-RO',
	'perm-LDN1FLSPRD5-fs-GoBook-RW',
	'perm-LDN1FLSPRD5-fs-IRE_HR_Legal-FC',
	'perm-LDN1FLSPRD5-fs-IRE_HR_Legal-RO',
	'perm-LDN1FLSPRD5-fs-IRE_HR_Legal-RW',
	'perm-LDN1FLSPRD5-fs-lsanders-FC',
	'perm-LDN1FLSPRD5-fs-lsanders-RO',
	'perm-LDN1FLSPRD5-fs-lsanders-RW',
	'perm-LDN1FLSPRD5-fs-Lux CITI Employees-FC',
	'perm-LDN1FLSPRD5-fs-Lux CITI Employees-RO',
	'perm-LDN1FLSPRD5-fs-Lux CITI Employees-RW',
	'perm-LDN1FLSPRD5-fs-Procedures-FC',
	'perm-LDN1FLSPRD5-fs-Procedures-RO',
	'perm-LDN1FLSPRD5-fs-Procedures-RW',
	'perm-LDN1FLSPRD5-fs-SAS Docs-FC',
	'perm-LDN1FLSPRD5-fs-SAS Docs-RO',
	'perm-LDN1FLSPRD5-fs-SAS Docs-RW',
	'perm-LDN1FLSPRD5-fs-UKDevelopment-FC',
	'perm-LDN1FLSPRD5-fs-UKDevelopment-RO',
	'perm-LDN1FLSPRD5-fs-UKDevelopment-RW',
	'perm-LDN1FLSPRD5-fs-UKHR_Finance_Shares-FC',
	'perm-LDN1FLSPRD5-fs-UKHR_Finance_Share-RO',
	'perm-LDN1FLSPRD5-fs-UKHR_Finance_Share-RW',
	'perm-LDN1FLSPRD5-fs-UKLegal-FC',
	'perm-LDN1FLSPRD5-fs-UKLegal-RO',
	'perm-LDN1FLSPRD5-fs-UKLegal-RW',
	'perm-LDN1FLSPRD5-fs-UKMarketing-FC',
	'perm-LDN1FLSPRD5-fs-UKMarketing-RO',
	'perm-LDN1FLSPRD5-fs-UKMarketing-RW',
	'perm-LDN1FLSPRD5-fs-UKOperations-FC',
	'perm-LDN1FLSPRD5-fs-UKOperations-RO',
	'perm-LDN1FLSPRD5-fs-UKOperations-RW',
	'perm-LDN1FLSPRD5-fs-UKRisk-FC',
	'perm-LDN1FLSPRD5-fs-UKRisk-RO',
	'perm-LDN1FLSPRD5-fs-UKRisk-RW',
	'perm-MUM1FLSPRD11-fs-GFSTIPL-FC',
	'perm-MUM1FLSPRD11-fs-GFSTIPL-RO',
	'perm-MUM1FLSPRD11-fs-GFSTIPL-RW',
	'perm-MUM1FLSPRD11-fs-INDHR-FC',
	'perm-MUM1FLSPRD11-fs-INDHR-RO',
	'perm-MUM1FLSPRD11-fs-INDHR-RW',
	'perm-MUM1FLSPRD11-fs-INDOperation-FC',
	'perm-MUM1FLSPRD11-fs-INDOperation-RO',
	'perm-MUM1FLSPRD11-fs-INDOperation-RW',
	'perm-MUM1FLSPRD11-fs-INDOperation2-FC',
	'perm-MUM1FLSPRD11-fs-INDOperation2-RO',
	'perm-MUM1FLSPRD11-fs-INDOperation2-RW',
	'perm-MUM1FLSPRD11-fs-ManojBroadbandclaims-FC',
	'perm-MUM1FLSPRD11-fs-ManojBroadbandclaims-RO',
	'perm-MUM1FLSPRD11-fs-ManojBroadbandclaims-RW',
	'perm-MUM1FLSPRD11-fs-Vaccination reimbursement claims-FC',
	'perm-MUM1FLSPRD11-fs-Vaccination reimbursement claims-RO',
	'perm-MUM1FLSPRD11-fs-Vaccination reimbursement claims-RW',
	'perm-HRS3PEFLSDRS1-fs-WDX-FC',
	'perm-HRS3PEFLSDRS1-fs-WDX-RO',
	'perm-HRS3PEFLSDRS1-fs-WDX-RW',
	'perm-HRS3PEFLSDRS1-fs-BloombergData-FC',
	'perm-HRS3PEFLSDRS1-fs-BloombergData-RO',
	'perm-HRS3PEFLSDRS1-fs-BloombergData-RW',
	'perm-HRS3PEFLSDRS1-fs-NYCOperations-FC',
	'perm-HRS3PEFLSDRS1-fs-NYCOperations-RO',
	'perm-HRS3PEFLSDRS1-fs-NYCOperations-RW',
	'perm-YKT3GFSFLSPRD1-GFS-RO',
	'perm-YKT3GFSFLSPRD1-GFS-RW',
	'perm-YKT3GFSFLSPRD1-GFS-FC',
	'perm-YKT3GFSFLSPRD1-GFS_Dept-RO',
	'perm-YKT3GFSFLSPRD1-GFS_Dept-RW',
	'perm-YKT3GFSFLSPRD1-GFS_Dept-FC',
	'perm-YKT3GFSFLSPRD1-GRU-RO',
	'perm-YKT3GFSFLSPRD1-GRU-RW',
	'perm-YKT3GFSFLSPRD1-GRU-FC',
	'perm-HRS1HDSPRD2-fs-HOME-fc',
	'perm-HRS1HDSPRD2-fs-HOME-ro',
	'perm-HRS1HDSPRD2-fs-HOME-md',
	'perm-HRS1HDSPRD3-fs-HOME-fc',
	'perm-HRS1HDSPRD3-fs-HOME-ro',
	'perm-HRS1HDSPRD3-fs-HOME-md',
	'perm-HRS1HDSPRD4-fs-HOME-fc',
	'perm-HRS1HDSPRD4-fs-HOME-ro',
	'perm-HRS1HDSPRD4-fs-HOME-md',
	'perm-HRS3GFSFLSDRS1-fs-GFS_Dept-fc',
	'perm-HRS3GFSFLSDRS1-fs-GFS_Dept-md',
	'perm-HRS3GFSFLSDRS1-fs-GFS_Dept-ro',
	'perm-LDN1FLSPRD3-fs-Ldn1 EmailArchive-fc',
	'perm-LDN1FLSPRD3-fs-Ldn1 EmailArchive-md',
	'perm-LDN1FLSPRD3-fs-Ldn1 EmailArchive-ro',
	'perm-LUX1FLSPRD1-fs-Luxembourg Restricted-fc',
	'perm-LUX1FLSPRD1-fs-Luxembourg Restricted-md',
	'perm-LUX1FLSPRD1-fs-Luxembourg Restricted-ro',
	'perm-LUX1FLSPRD1-fs-Scripts-fc',
	'perm-LUX1FLSPRD1-fs-Scripts-md',
	'perm-LUX1FLSPRD1-fs-Scripts-ro',
	'perm-MUM1FLSPRD10-fs-INDOperation07-fc',
	'perm-MUM1FLSPRD10-fs-INDOperation07-md',
	'perm-MUM1FLSPRD10-fs-INDOperation07-ro',
	'perm-MUM1FLSPRD10-fs-INDOperation09-fc',
	'perm-MUM1FLSPRD10-fs-INDOperation09-md',
	'perm-MUM1FLSPRD10-fs-INDOperation09-ro',
	'perm-MUM1FLSPRD10-fs-INDOperation11-fc',
	'perm-MUM1FLSPRD10-fs-INDOperation11-md',
	'perm-MUM1FLSPRD10-fs-INDOperation11-ro',
	'perm-MUM1FLSPRD10-fs-INDOperation15-fc',
	'perm-MUM1FLSPRD10-fs-INDOperation15-md',
	'perm-MUM1FLSPRD10-fs-INDOperation15-ro',
	'perm-MUM1FLSPRD10-fs-INDOperation16-fc',
	'perm-MUM1FLSPRD10-fs-INDOperation16-md',
	'perm-MUM1FLSPRD10-fs-INDOperation16-ro',
	'perm-MUM1FLSPRD10-fs-INDOperation17-fc',
	'perm-MUM1FLSPRD10-fs-INDOperation17-md',
	'perm-MUM1FLSPRD10-fs-INDOperation17-ro',
	'perm-MUM1FLSPRD10-fs-MyIdeas 2016 - Idea Documents-fc',
	'perm-MUM1FLSPRD10-fs-MyIdeas 2016 - Idea Documents-md',
	'perm-MUM1FLSPRD10-fs-MyIdeas 2016 - Idea Documents-ro',
	'perm-MUM1FLSPRD10-fs-Software-fc',
	'perm-MUM1FLSPRD10-fs-Software-md',
	'perm-MUM1FLSPRD10-fs-Software-ro',
	'perm-MUM1FLSPRD11-fs-GFSTIPL-Finance-fc',
	'perm-MUM1FLSPRD11-fs-GFSTIPL-Finance-md',
	'perm-MUM1FLSPRD11-fs-GFSTIPL-Finance-ro',
	'perm-MUM1FLSPRD12-fs-INDAdmin-fc',
	'perm-MUM1FLSPRD12-fs-INDAdmin-md',
	'perm-MUM1FLSPRD12-fs-INDAdmin-ro',
	'perm-MUM1FLSPRD12-fs-INDDevelopment-fc',
	'perm-MUM1FLSPRD12-fs-INDDevelopment-md',
	'perm-MUM1FLSPRD12-fs-INDDevelopment-ro',
	'perm-MUM1FLSPRD12-fs-INDFinance-fc',
	'perm-MUM1FLSPRD12-fs-INDFinance-md',
	'perm-MUM1FLSPRD12-fs-INDFinance-ro',
	'perm-MUM1FLSPRD12-fs-INDLegal-fc',
	'perm-MUM1FLSPRD12-fs-INDLegal-md',
	'perm-MUM1FLSPRD12-fs-INDLegal-ro',
	'perm-MUM1FLSPRD12-fs-INDOperation-fc',
	'perm-MUM1FLSPRD12-fs-INDOperation-md',
	'perm-MUM1FLSPRD12-fs-INDOperation-ro',
	'perm-MUM1FLSPRD15-fs-INDOperation-fc',
	'perm-MUM1FLSPRD15-fs-INDOperation-md',
	'perm-MUM1FLSPRD15-fs-INDOperation-ro',
	'perm-MUM1FLSPRD2-fs-Home2-fc',
	'perm-MUM1FLSPRD2-fs-Home2-md',
	'perm-MUM1FLSPRD2-fs-Home2-ro',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive10HSM-fc',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive10HSM-md',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive10HSM-ro',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive11HSM-fc',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive11HSM-md',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive11HSM-ro',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive25HSM-fc',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive25HSM-md',
	'perm-MUM1FLSPRD9-fs-Mum1 EmailArchive25HSM-ro',
	'perm-MUM1FLSPRD9-fs-Mum1 SQL Backup-fc',
	'perm-MUM1FLSPRD9-fs-Mum1 SQL Backup-md',
	'perm-MUM1FLSPRD9-fs-Mum1 SQL Backup-ro',
	'perm-MUM1FLSPRD9-fs-MUM2 EmailArchive12-fc',
	'perm-MUM1FLSPRD9-fs-MUM2 EmailArchive12-md',
	'perm-MUM1FLSPRD9-fs-MUM2 EmailArchive12-ro',
	'perm-MUM1FLSPRD9-fs-Software-fc',
	'perm-MUM1FLSPRD9-fs-Software-md',
	'perm-MUM1FLSPRD9-fs-Software-ro',
	'perm-MUM2FLSDRS8-fs-INDOperation12-fc',
	'perm-MUM2FLSDRS8-fs-INDOperation12-md',
	'perm-MUM2FLSDRS8-fs-INDOperation12-ro',
	'perm-MUM2FLSDRS8-fs-INDOperation13-fc',
	'perm-MUM2FLSDRS8-fs-INDOperation13-md',
	'perm-MUM2FLSDRS8-fs-INDOperation13-ro',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive 20HSM-fc',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive 20HSM-md',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive 20HSM-ro',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive17HSM-fc',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive17HSM-md',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive17HSM-ro',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive18HSM-fc',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive18HSM-md',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive18HSM-ro',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive19HSM-fc',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive19HSM-md',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive19HSM-ro',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive21HSM-fc',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive21HSM-md',
	'perm-MUM2FLSDRS8-fs-Mum1 EmailArchive21HSM-ro',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive21HSM-fc',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive21HSM-md',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive21HSM-ro',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive28HSM-fc',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive28HSM-md',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive28HSM-ro',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive29HSM-fc',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive29HSM-md',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive29HSM-ro',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive30HSM-fc',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive30HSM-md',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive30HSM-ro',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive31HSM-fc',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive31HSM-md',
	'perm-MUM2FLSDRS8-fs-MUM2 EmailArchive31HSM-ro',
	'perm-MUM2FLSPRD2-fs-Home2-fc',
	'perm-MUM2FLSPRD2-fs-Home2-md',
	'perm-MUM2FLSPRD2-fs-Home2-ro',
	'perm-MUM2FLSPRD4-fs-Home4-fc',
	'perm-MUM2FLSPRD4-fs-Home4-md',
	'perm-MUM2FLSPRD4-fs-Home4-ro',
	'perm-MUM2FLSPRD5-fs-Home5-fc',
	'perm-MUM2FLSPRD5-fs-Home5-md',
	'perm-MUM2FLSPRD5-fs-Home5-ro',
	'perm-MUM2FLSPRD6-fs-Home6-fc',
	'perm-MUM2FLSPRD6-fs-Home6-md',
	'perm-MUM2FLSPRD6-fs-Home6-ro',
	'perm-MUM4FLSPRD1-fs-Home1-fc',
	'perm-MUM4FLSPRD1-fs-Home1-md',
	'perm-MUM4FLSPRD1-fs-Home1-ro',
	'perm-MUM4FLSPRD1-fs-Home2-fc',
	'perm-MUM4FLSPRD1-fs-Home2-md',
	'perm-MUM4FLSPRD1-fs-Home2-ro',
	'perm-MUM4FLSPRD2-fs-Home3-fc',
	'perm-MUM4FLSPRD2-fs-Home3-md',
	'perm-MUM4FLSPRD2-fs-Home3-ro',
	'perm-MUM4FLSPRD2-fs-Home4-fc',
	'perm-MUM4FLSPRD2-fs-Home4-md',
	'perm-MUM4FLSPRD2-fs-Home4-ro',
	'perm-MUM4FLSPRD3-fs-Home5-fc',
	'perm-MUM4FLSPRD3-fs-Home5-md',
	'perm-MUM4FLSPRD3-fs-Home5-ro',
	'perm-MUM4FLSPRD3-fs-Home6-fc',
	'perm-MUM4FLSPRD3-fs-Home6-md',
	'perm-MUM4FLSPRD3-fs-Home6-ro',
	'perm-NYCRC012K3-fs-CLIENT-fc',
	'perm-NYCRC012K3-fs-CLIENT-md',
	'perm-NYCRC012K3-fs-CLIENT-ro',
	'perm-NYCRC012K3-fs-Crestwood-fc',
	'perm-NYCRC012K3-fs-Crestwood-md',
	'perm-NYCRC012K3-fs-Crestwood-ro',
	'perm-NYCRC012K3-fs-DP-fc',
	'perm-NYCRC012K3-fs-DP-md',
	'perm-NYCRC012K3-fs-DP-ro',
	'perm-NYCRC012K3-fs-EzeCastle-fc',
	'perm-NYCRC012K3-fs-EzeCastle-md',
	'perm-NYCRC012K3-fs-EzeCastle-ro',
	'perm-NYCRC012K3-fs-HISTORY-fc',
	'perm-NYCRC012K3-fs-HISTORY-md',
	'perm-NYCRC012K3-fs-HISTORY-ro',
	'perm-NYCRC012K3-fs-LongPond-fc',
	'perm-NYCRC012K3-fs-LongPond-md',
	'perm-NYCRC012K3-fs-LongPond-ro',
	'perm-NYCRC012K3-fs-Mudrick-fc',
	'perm-NYCRC012K3-fs-Mudrick-md',
	'perm-NYCRC012K3-fs-Mudrick-ro',
	'perm-NYCRC012K3-fs-Recon Data Files-fc',
	'perm-NYCRC012K3-fs-Recon Data Files-md',
	'perm-NYCRC012K3-fs-Recon Data Files-ro',
	'perm-NYCRC012K3-fs-Risk-fc',
	'perm-NYCRC012K3-fs-Risk-md',
	'perm-NYCRC012K3-fs-Risk-ro',
	'perm-SIN2FS01-fs-Restricted-fc',
	'perm-SIN2FS01-fs-Restricted-md',
	'perm-SIN2FS01-fs-Restricted-ro',
	'perm-YKT1FLSPRD17-fs-Enterprise Vault Stores-fc',
	'perm-YKT1FLSPRD17-fs-Enterprise Vault Stores-md',
	'perm-YKT1FLSPRD17-fs-Enterprise Vault Stores-ro',
	'perm-YKT1FLSPRD1-fs-SSCGO-fc',
	'perm-YKT1FLSPRD1-fs-SSCGO-md',
	'perm-YKT1FLSPRD1-fs-SSCGO-ro',
	'perm-YKT1FLSPRD2-fs-NYCOperations-fc',
	'perm-YKT1FLSPRD2-fs-NYCOperations-md',
	'perm-YKT1FLSPRD2-fs-NYCOperations-ro',
	'perm-YKT1HDSPRD1-fs-Home-fc',
	'perm-YKT1HDSPRD1-fs-Home-md',
	'perm-YKT1HDSPRD1-fs-Home-ro',
	'perm-YKT1HDSPRD2-fs-Home-fc',
	'perm-YKT1HDSPRD2-fs-Home-md',
	'perm-YKT1HDSPRD2-fs-Home-ro',
	'perm-YKT1HDSPRD3-fs-Home-fc',
	'perm-YKT1HDSPRD3-fs-Home-md',
	'perm-YKT1HDSPRD3-fs-Home-ro',
	'perm-YKT1HDSPRD4-fs-Home-fc',
	'perm-YKT1HDSPRD4-fs-Home-md',
	'perm-YKT1HDSPRD4-fs-Home-ro',
	'perm-YKT1HDSPRD5-fs-Home-fc',
	'perm-YKT1HDSPRD5-fs-Home-md',
	'perm-YKT1HDSPRD5-fs-Home-ro',
	'perm-YKT1OFSPRD1-fs-Admin-fc',
	'perm-YKT1OFSPRD1-fs-Admin-md',
	'perm-YKT1OFSPRD1-fs-Admin-ro',
	'perm-YKT1OFSPRD1-fs-Backups-fc',
	'perm-YKT1OFSPRD1-fs-Backups-md',
	'perm-YKT1OFSPRD1-fs-Backups-ro',
	'perm-YKT1OFSPRD1-fs-CNF_PSTs-fc',
	'perm-YKT1OFSPRD1-fs-CNF_PSTs-md',
	'perm-YKT1OFSPRD1-fs-CNF_PSTs-ro',
	'perm-YKT1OFSPRD1-fs-Development-fc',
	'perm-YKT1OFSPRD1-fs-Development-md',
	'perm-YKT1OFSPRD1-fs-Development-ro',
	'perm-YKT1OFSPRD1-fs-emailrestore-fc',
	'perm-YKT1OFSPRD1-fs-emailrestore-md',
	'perm-YKT1OFSPRD1-fs-emailrestore-ro',
	'perm-YKT1OFSPRD1-fs-FundServices-fc',
	'perm-YKT1OFSPRD1-fs-FundServices-md',
	'perm-YKT1OFSPRD1-fs-FundServices-ro',
	'perm-YKT1OFSPRD1-fs-GFS_Archive-fc',
	'perm-YKT1OFSPRD1-fs-GFS_Archive-md',
	'perm-YKT1OFSPRD1-fs-GFS_Archive-ro',
	'perm-YKT1OFSPRD1-fs-HFS_Dept-fc',
	'perm-YKT1OFSPRD1-fs-HFS_Dept-md',
	'perm-YKT1OFSPRD1-fs-HFS_Dept-ro',
	'perm-YKT1OFSPRD1-fs-HR-fc',
	'perm-YKT1OFSPRD1-fs-HR-md',
	'perm-YKT1OFSPRD1-fs-HR-ro',
	'perm-YKT1OFSPRD1-fs-Infor-fc',
	'perm-YKT1OFSPRD1-fs-Infor-md',
	'perm-YKT1OFSPRD1-fs-Infor-ro',
	'perm-YKT1OFSPRD1-fs-InforOSplatformUAT-fc',
	'perm-YKT1OFSPRD1-fs-InforOSplatformUAT-md',
	'perm-YKT1OFSPRD1-fs-InforOSplatformUAT-ro',
	'perm-YKT1OFSPRD1-fs-isi_omr-fc',
	'perm-YKT1OFSPRD1-fs-isi_omr-md',
	'perm-YKT1OFSPRD1-fs-isi_omr-ro',
	'perm-YKT1OFSPRD1-fs-Legal-fc',
	'perm-YKT1OFSPRD1-fs-Legal-md',
	'perm-YKT1OFSPRD1-fs-Legal-ro',
	'perm-YKT1OFSPRD1-fs-ManagedServices-fc',
	'perm-YKT1OFSPRD1-fs-ManagedServices-md',
	'perm-YKT1OFSPRD1-fs-ManagedServices-ro',
	'perm-YKT1OFSPRD1-fs-Projects-fc',
	'perm-YKT1OFSPRD1-fs-Projects-md',
	'perm-YKT1OFSPRD1-fs-Projects-ro',
	'perm-YKT1OFSPRD1-fs-QA-fc',
	'perm-YKT1OFSPRD1-fs-QA-md',
	'perm-YKT1OFSPRD1-fs-QA-ro',
	'perm-YKT1OFSPRD1-fs-Systems-fc',
	'perm-YKT1OFSPRD1-fs-Systems-md',
	'perm-YKT1OFSPRD1-fs-Systems-ro',
	'perm-YKT1OFSPRD1-fs-Temp-fc',
	'perm-YKT1OFSPRD1-fs-Temp-md',
	'perm-YKT1OFSPRD1-fs-Temp-ro',
	'perm-YKT1OFSPRD1-fs-UserArchiveData-fc',
	'perm-YKT1OFSPRD1-fs-UserArchiveData-md',
	'perm-YKT1OFSPRD1-fs-UserArchiveData-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Clients-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Clients-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Clients-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Dept-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Dept-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Dept-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_ETL-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_ETL-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_ETL-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Files-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Files-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Files-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_IT-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_IT-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_IT-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Projects-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Projects-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Projects-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Systems-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Systems-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Systems-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Transfer-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Transfer-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_Transfer-ro',
	'perm-YKT3CFSFLSPRD1-fs-CFS_UserPickup-fc',
	'perm-YKT3CFSFLSPRD1-fs-CFS_UserPickup-md',
	'perm-YKT3CFSFLSPRD1-fs-CFS_UserPickup-ro',
	'perm-YKT3CFSFLSPRD1-fs-GFASTraining-fc',
	'perm-YKT3CFSFLSPRD1-fs-GFASTraining-md',
	'perm-YKT3CFSFLSPRD1-fs-GFASTraining-ro',
	'perm-YKT3FLSPRD1-fs-TA-fc',
	'perm-YKT3FLSPRD1-fs-TA-md',
	'perm-YKT3FLSPRD1-fs-TA-ro',
	'perm-YKT3FLSPRD2-fs-HFS_Dept-fc',
	'perm-YKT3FLSPRD2-fs-HFS_Dept-md',
	'perm-YKT3FLSPRD2-fs-HFS_Dept-ro',
	'perm-YKT3GFS202PRD1-fs-Data-fc',
	'perm-YKT3GFS202PRD1-fs-Data-md',
	'perm-YKT3GFS202PRD1-fs-Data-ro',
	'perm-YKT3GFSATMDEV1-fs-ACD Data Agent-fc',
	'perm-YKT3GFSATMDEV1-fs-ACD Data Agent-md',
	'perm-YKT3GFSATMDEV1-fs-ACD Data Agent-ro',
	'perm-YKT3GFSATMDEV1-fs-AppsRoot-fc',
	'perm-YKT3GFSATMDEV1-fs-AppsRoot-md',
	'perm-YKT3GFSATMDEV1-fs-AppsRoot-ro',
	'perm-YKT3GFSATMDEV1-fs-AutoDrop-fc',
	'perm-YKT3GFSATMDEV1-fs-AutoDrop-md',
	'perm-YKT3GFSATMDEV1-fs-AutoDrop-ro',
	'perm-YKT3GFSATMDEV1-fs-AutomateRoot-fc',
	'perm-YKT3GFSATMDEV1-fs-AutomateRoot-md',
	'perm-YKT3GFSATMDEV1-fs-AutomateRoot-ro',
	'perm-YKT3GFSATMDEV1-fs-CFS_Sugar-fc',
	'perm-YKT3GFSATMDEV1-fs-CFS_Sugar-md',
	'perm-YKT3GFSATMDEV1-fs-CFS_Sugar-ro',
	'perm-YKT3GFSATMDEV1-fs-Driver-fc',
	'perm-YKT3GFSATMDEV1-fs-Driver-md',
	'perm-YKT3GFSATMDEV1-fs-Driver-ro',
	'perm-YKT3GFSATMDEV1-fs-Gbs-fc',
	'perm-YKT3GFSATMDEV1-fs-Gbs-md',
	'perm-YKT3GFSATMDEV1-fs-Gbs-ro',
	'perm-YKT3GFSATMDEV1-fs-Geneva_BUS-fc',
	'perm-YKT3GFSATMDEV1-fs-Geneva_BUS-md',
	'perm-YKT3GFSATMDEV1-fs-Geneva_BUS-ro',
	'perm-YKT3GFSATMDEV1-fs-JavaRoot-fc',
	'perm-YKT3GFSATMDEV1-fs-JavaRoot-md',
	'perm-YKT3GFSATMDEV1-fs-JavaRoot-ro',
	'perm-YKT3GFSATMDEV1-fs-Omgeo-fc',
	'perm-YKT3GFSATMDEV1-fs-Omgeo-md',
	'perm-YKT3GFSATMDEV1-fs-Omgeo-ro',
	'perm-YKT3GFSATMDEV1-fs-PerlRoot-fc',
	'perm-YKT3GFSATMDEV1-fs-PerlRoot-md',
	'perm-YKT3GFSATMDEV1-fs-PerlRoot-ro',
	'perm-YKT3GFSATMDEV1-fs-UAT18-fc',
	'perm-YKT3GFSATMDEV1-fs-UAT18-md',
	'perm-YKT3GFSATMDEV1-fs-UAT18-ro',
	'perm-YKT3GFSATMDEV1-fs-UserData-fc',
	'perm-YKT3GFSATMDEV1-fs-UserData-md',
	'perm-YKT3GFSATMDEV1-fs-UserData-ro',
	'perm-YKT3GFSATMDEV1-fs-WebRoot-fc',
	'perm-YKT3GFSATMDEV1-fs-WebRoot-md',
	'perm-YKT3GFSATMDEV1-fs-WebRoot-ro',
	'perm-YKT3GFSATMPRD1-fs-ACD Data Agent-fc',
	'perm-YKT3GFSATMPRD1-fs-ACD Data Agent-md',
	'perm-YKT3GFSATMPRD1-fs-ACD Data Agent-ro',
	'perm-YKT3GFSATMPRD1-fs-AppsRoot-fc',
	'perm-YKT3GFSATMPRD1-fs-AppsRoot-md',
	'perm-YKT3GFSATMPRD1-fs-AppsRoot-ro',
	'perm-YKT3GFSATMPRD1-fs-AutoDrop-fc',
	'perm-YKT3GFSATMPRD1-fs-AutoDrop-md',
	'perm-YKT3GFSATMPRD1-fs-AutoDrop-ro',
	'perm-YKT3GFSATMPRD1-fs-AutomateRoot-fc',
	'perm-YKT3GFSATMPRD1-fs-AutomateRoot-md',
	'perm-YKT3GFSATMPRD1-fs-AutomateRoot-ro',
	'perm-YKT3GFSATMPRD1-fs-JavaRoot-fc',
	'perm-YKT3GFSATMPRD1-fs-JavaRoot-md',
	'perm-YKT3GFSATMPRD1-fs-JavaRoot-ro',
	'perm-YKT3GFSATMPRD1-fs-Omgeo-fc',
	'perm-YKT3GFSATMPRD1-fs-Omgeo-md',
	'perm-YKT3GFSATMPRD1-fs-Omgeo-ro',
	'perm-YKT3GFSATMPRD1-fs-PerlRoot-fc',
	'perm-YKT3GFSATMPRD1-fs-PerlRoot-md',
	'perm-YKT3GFSATMPRD1-fs-PerlRoot-ro',
	'perm-YKT3GFSATMPRD1-fs-WebRoot-fc',
	'perm-YKT3GFSATMPRD1-fs-WebRoot-md',
	'perm-YKT3GFSATMPRD1-fs-WebRoot-ro',
	'perm-YKT3GFSGNVUAT2-fs-data-fc',
	'perm-YKT3GFSGNVUAT2-fs-data-md',
	'perm-YKT3GFSGNVUAT2-fs-data-ro',
	'perm-YKT3GFSINVDEV1-fs-Investran-fc',
	'perm-YKT3GFSINVDEV1-fs-Investran-md',
	'perm-YKT3GFSINVDEV1-fs-Investran-ro',
	'perm-YKT3GFSINVPRD1-fs-Investran-fc',
	'perm-YKT3GFSINVPRD1-fs-Investran-md',
	'perm-YKT3GFSINVPRD1-fs-Investran-ro',
	'perm-YKT3GFSSQLDEV2-fs-Input-fc',
	'perm-YKT3GFSSQLDEV2-fs-Input-md',
	'perm-YKT3GFSSQLDEV2-fs-Input-ro',
	'perm-YKT3GFSSQLDEV2-fs-MantraApp-fc',
	'perm-YKT3GFSSQLDEV2-fs-MantraApp-md',
	'perm-YKT3GFSSQLDEV2-fs-MantraApp-ro',
	'perm-YKT3GFSSQLDEV2-fs-MantraSSIS-fc',
	'perm-YKT3GFSSQLDEV2-fs-MantraSSIS-md',
	'perm-YKT3GFSSQLDEV2-fs-MantraSSIS-ro',
	'perm-YKT3GFSSQLPRD2-fs-DB_LOGSHIP-fc',
	'perm-YKT3GFSSQLPRD2-fs-DB_LOGSHIP-md',
	'perm-YKT3GFSSQLPRD2-fs-DB_LOGSHIP-ro',
	'perm-YKT3GFSSQLPRD2-fs-MantraApp-fc',
	'perm-YKT3GFSSQLPRD2-fs-MantraApp-md',
	'perm-YKT3GFSSQLPRD2-fs-MantraApp-ro',
	'perm-YKT3GFSSQLPRD2-fs-MantraSSIS-fc',
	'perm-YKT3GFSSQLPRD2-fs-MantraSSIS-md',
	'perm-YKT3GFSSQLPRD2-fs-MantraSSIS-ro',
	'perm-YKT3GFSSQLUAT2-fs-MantraApp-fc',
	'perm-YKT3GFSSQLUAT2-fs-MantraApp-md',
	'perm-YKT3GFSSQLUAT2-fs-MantraApp-ro',
	'perm-YKT3GFSSQLUAT2-fs-MantraSSIS-fc',
	'perm-YKT3GFSSQLUAT2-fs-MantraSSIS-md',
	'perm-YKT3GFSSQLUAT2-fs-MantraSSIS-ro',
	'perm-YKT3GFSSQLUAT2-fs-PED_TEST-fc',
	'perm-YKT3GFSSQLUAT2-fs-PED_TEST-md',
	'perm-YKT3GFSSQLUAT2-fs-PED_TEST-ro',
	'perm-YKT3GFSSQLUAT2-fs-PG_SHARE-fc',
	'perm-YKT3GFSSQLUAT2-fs-PG_SHARE-md',
	'perm-YKT3GFSSQLUAT2-fs-PG_SHARE-ro',
	'perm-YKT3PEFLSPRD2-fs-PE_Dept-fc',
	'perm-YKT3PEFLSPRD2-fs-PE_Dept-md',
	'perm-YKT3PEFLSPRD2-fs-PE_Dept-ro')

Function Test-ACEExists {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		[System.Security.AccessControl.FileSystemAccessRule]$ACE,
		[Parameter(Mandatory = $true)]
		[System.Security.AccessControl.DirectorySecurity]$ACL
	)
	
	# Check if the ACE already exists in the ACL
	$aceExists = $ACL.Access | Where-Object {
		$_.IdentityReference -eq $ACE.IdentityReference -and
		$_.FileSystemRights -eq $ACE.FileSystemRights -and
		$_.AccessControlType -eq $ACE.AccessControlType -and
		$_.InheritanceFlags -eq $ACE.InheritanceFlags
	}
	
	# Return bool value represeting the existence of the ACE
	Return [bool]($aceExists)
}


#Set vars
$inheritance = "ContainerInherit, ObjectInherit"
$type = "Allow"
$propagation = "None"

$Shares = get-smbshare | Where-Object { $_.name -notlike "*$" }
$NewOwner = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList 'BUILTIN\Administrators'
#endregion 

#region Script
ForEach ($Share In $Shares) {
	
	
	Remove-Variable -Name smbaccess -ErrorAction SilentlyContinue
	$smbaccess = Get-SmbShareAccess $Share.Name | Where-Object { $_.AccountName -eq 'Everyone' }
	
	If ($smbaccess) {
		Write-Host "Validating Share Access $($Share.Name)"
		Grant-SmbShareAccess -Name $Share.Name -AccountName "SSNC-CORP\Domain Users" -ScopeName $smbaccess.ScopeName -AccessRight $smbaccess.AccessRight -Force
	}
	
	Write-Host "Starting $($Share.Name)" -ForegroundColor Green
	
	Remove-Variable -Name ACL -ErrorAction SilentlyContinue
	
	#get the folder ACLs
	$SetACL = $false
	$ACLUpdate = $false
	$ACL = Get-Acl -Path $Share.Path
	
	If ($ACL.Owner -ne "BUILTIN\Administrators") {
		Write-Host " -- Updating owner on $($Share.Name)" -ForegroundColor Yellow
		$ACL.SetOwner($NewOwner)
		$SetACL = $true
	}
	
	#Gat a list of groups for the share
	$Groups = $ListofGroups | Where-Object { $_ -like "perm-$ENV:COMPUTERNAME-fs-$($Share.Name)-*" }
	$Groups = $ListofGroups | Where-Object { $_ -like "perm-$ENV:COMPUTERNAME-$($Share.Name)-*" }
	
	#Loop through the groups 
	ForEach ($Group In $Groups) {
		$identity = "GLOBEOP\$Group"
		Switch ($Group) {
			{ $_ -like "*-FC" } {
				$rights = "FullControl"
				$ACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
			}
			{ $_ -like "*-RW" } {
				$rights = "Modify, Synchronize"
				$ACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
			}
			{ $_ -like "*-MD" } {
				$rights = "Modify, Synchronize"
				$ACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
			}
			{ $_ -like "*-RO" } {
				$rights = "ReadAndExecute, Synchronize"
				$ACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
			}
			default {
				#<code>
			}
		}
		
		$ACLUpdate = Test-ACEExists -ACE $ACE -ACL $ACL
		
		If (-not $ACLUpdate) {
			#add the new ACE to the ACL list
			Write-Host " -- Adding ACE for $identity on $($Share.Name)" -ForegroundColor Yellow
			$ACL.AddAccessRule($ACE)
			$SetACL = $true
		}
		
	}
	
	If ($SetACL -eq $true) {
		Write-Host " -- Setting new ACLs on $($Share.Name)" -ForegroundColor Yellow
		Start-Job -ArgumentList $Share.Path, $ACL -ScriptBlock { Param ($p1, $p2) Set-Acl -Path $p1 -AclObject $p2 } -Name $Share.Name 
	}
	
	If ($SetACL -eq $false) { Write-Host " -- No new ACE entries for $($Share.Name) -- No Action Taken" -ForegroundColor Red} 
	
}
#endregion

#
#get-job | Where-Object { $_.state -eq "Completed" -and $_.HasMoreData -eq $false } | remove-job; get-job
#
##region validation
#$Shares = get-smbshare | Where-Object { $_.name -notlike "*$" }
#$Results = ForEach ($Share In $Shares) {
#	$ACL = Get-Acl $Share.Path
#	$MatchingACE = $ACL | Select-Object -ExpandProperty Access | Where-Object { $_.IdentityReference -like "GLOBEOP\perm-$ENV:COMPUTERNAME-fs-$($Share.Name)-*" }
#	
#	$Stats = New-Object psobject -Property @{
#		Computer = $env:COMPUTERNAME
#		ShareName = $Share.Name
#		ACL = $ACL
#		MatchingACEList  = $MatchingACE
#		MatchingACECount = $MatchingACE.count
#	}
#	
#	$Stats
#	
#}
#
#$Results | ? {$_.MatchingACECount -lt 3}
#
##endregion
#
#
#
#get-smbshare | Where-Object { $_.name -notlike "*$" } | Get-SmbShareAccess
#
#<#
#	$identity = $UserToUpdate.CorpUser
#	$rights = 'FullControl' #Other options: [enum]::GetValues('System.Security.AccessControl.FileSystemRights')
#	$inheritance = 'ContainerInherit, ObjectInherit' #Other options: [enum]::GetValues('System.Security.AccessControl.Inheritance')
#	$propagation = 'None' #Other options: [enum]::GetValues('System.Security.AccessControl.PropagationFlags')
#	$type = 'Allow' #Other options: [enum]::GetValues('System.Securit y.AccessControl.AccessControlType')
#	$ACE = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $rights, $inheritance, $propagation, $type)
#
##>
#
#
#$list =@()
#Set-Location c:\temp
#$Shares = get-smbshare | Where-Object { $_.name -notlike "*$" }
#$Results = ForEach ($Share In $Shares) {
#	$ACL = Get-Acl $Share.Path
#	$MatchingACE = $ACL | Select-Object -ExpandProperty Access | Where-Object { $_.IdentityReference -like "GLOBEOP\*" -and $_.IsInherited -eq $false -and $_.IdentityReference -notlike "*-ADM" -and $_.IdentityReference -notin ("GLOBEOP\Domain Admins", "GLOBEOP\backup", "GLOBEOP\ctxadmin", "GLOBEOP\abridger", "GLOBEOP\bpang", "GLOBEOP\DACSAdmin", "GLOBEOP\Secadmin", "GLOBEOP\SIAdmin", "GLOBEOP\lsimons", "GLOBEOP\heshah") }
#	
#	ForEach ($ACE In $MatchingACE) {
#		$list += New-Object psobject -Property @{
#			Computer  = $env:COMPUTERNAME
#			ShareName = $Share.Name
#			IdentityReference = $ACE.IdentityReference
#			FileSystemRights = $ACE.FileSystemRights
#			IsInherited = $ACE.IsInherited
#		}
#	}
#}
#
#$ExportFile = "c:\temp\$($env:COMPUTERNAME)_Share_Perms.csv"
#$list | Export-Csv $ExportFile -NoTypeInformation
#start c:\temp
#