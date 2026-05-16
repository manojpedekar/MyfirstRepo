
## DESCRIPTION
This module is a set of functions to interact with the SS&C Cloud API. Each function inside performs one task as simply as possible.

The goal of this module is to create an API 'provider' to be used in future scripting for the Windows team. But, this module can be used standalone if desired. 

**This module is still a work in progress**

### Getting Function information

Functions in the module are documented to provide needed information when using Get-Help. These functions also try to stay within the [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7.5) available.

To list all available commands within this module, run the below after loading: 
```
get-command -Module Cloud-API
```

If you need further information regarding a command, run 'Get-Help' like the below example: 

```
Get-Help Get-instance
```
```

NAME
    Get-Instance

SYNOPSIS
    This module is used to get instance information from the SS&C Cloud locations. You can get all instances for an entire 'deployment-zone' or just a single instance. See SYNTAX for all options.

        NOTES: Requesting single instance information will return more detailed results than getting them at the sub-project level or higher. Recommended to get at sub-project level as a set $variable, then Get-Instance -instanceId $variable.id, for example to get deeper details.


SYNTAX
    Get-Instance [[-instanceId] <String>] [[-projectId] <String>] [[-accountId] <String>] [[-subprojectId] <String>] [[-deploymentZoneId] <String>] [<CommonParameters>]


DESCRIPTION


RELATED LINKS

REMARKS
    To see the examples, type: "Get-Help Get-Instance -Examples"
    For more information, type: "Get-Help Get-Instance -Detailed"
    For technical information, type: "Get-Help Get-Instance -Full"
```


## API Key Requirements

This module, when loaded, will attempt to import your API key from an encrypted file located at the root of your user directory. **If this file does not exist, the module will prompt you to input your API Key.** 

To setup an encrypted API key file: 

1. Open a Powershell window and load the below function.
    ```   
    function Protect-String {
        param (
            [string]$StringtoEncrypt,
            [switch]$Computer
        )

        if ($Computer) {
            $key = "LocalMachine"
        } else {
            $key = "CurrentUser"
        }
        $data = [System.Text.Encoding]::UTF8.GetBytes($StringtoEncrypt)
        $data = [System.Security.Cryptography.ProtectedData]::Protect($data, $null, [System.Security.Cryptography.DataProtectionScope]::$key)
        [Convert]::ToBase64String($data)
    }
    ```

2. Next, modify then run the below command to create your encrypted file. 
    ```
    Protect-String "YOUR_API_KEY" > "C:\Users\$($env:Username)\cloudapi.key"
    ```

3. Finally, import the module 
    ```
    Import-Module C:\path\to\Cloud-API.psm1'
    ```


## Basic Usage/Tutorial

Below gives a brief introduction to some of my common uses for this module. Please view the actual functions in the module to all functionality. 

#### Get-Instance

Grabs instance information. Either a single instance or all within a sub-project, account, or deployment-zone.
   
   * Single Instance 
        ```
        Get-Instance -instanceId "i-55c319eb-5944-4d00-a927-02e2eff4430a"
        ```

        ```
        id                   : i-55c319eb-5944-4d00-a927-02e2eff4430a
        createdDate          : 9/18/2025 4:09:23 PM
        createdBy            : tnewnham@innovestsystems.com
        projectId            : project-84193807-a81d-4b9b-895b-6c8d8292b55a
        subprojectId         : subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73
        deploymentZoneId     : deploymentzone-na-central-kc
        imageId              : ssnc-cloud-w2k25-base
        name                 : demo
        ip                   : 10.222.14.205
        dns                  : 10-222-14-205.ssnc-corp.cloud
        site                 : na-central-kc
        state                : available
        migrated             : False
        tasksStatus          : COMPLETED
        storageConfiguration : DEFAULT
        workloadType         : CLOUD_WINDOWS
        osType               : Windows
        osVersion            : Windows Server 2025
        hostname             : 10-222-14-205
        gateway              : 10.222.14.1
        powerState           : poweredOn
        cpu                  : 2
        memory               : 4
        baseDisk             : 100
        guestFullName        : Microsoft Windows Server 2016 (64-bit)
        guestState           : running
        toolsStatus          : toolsOk
        toolsRunningStatus   : guestToolsRunning
        mask                 : 255.255.255.0
        vlan                 : 285
        patchingGroup        : 1st-mon-2am-6am
        scheduledForPatching : True
        lastPatchedDate      : 9/18/2025 4:09:23 PM
        lastOsPatchedDate    : 9/18/2025 4:09:23 PM
        domainDelegation     : cloudad.ssncad.global
        ownerId              : user-7e75ddcb-3ec8-4aaa-8d6b-6575678d562e
        imageName            : Windows Server 2025
        deploymentZoneName   : na-central-kc
        securityGroups       : {@{id=securitygroup-ab1620d4-6e5b-44e0-adec-1f8a33aa3d2d; name=Secondary IP ip-f7b076d9-3c40-4710-8da3-b126e3ffc6ca Group; type=SecondaryIP; ip=; fqdn=; cmdb=31320; networkingTenantId=ssnc}, @{id=securitygroup-6da71de1-87be-467f-ac65-f151c5f88277; name=test5;
                            type=SecurityGroup; ip=; fqdn=; cmdb=31320; networkingTenantId=ssnc}, @{id=securitygroup-773e6409-249f-4965-b4ec-8de7cf6908f3; name=Secondary IP ip-89ef8db8-cb50-43d1-8187-0f83ccbcca65 Group; type=SecondaryIP; ip=; fqdn=; cmdb=31320; networkingTenantId=ssnc}}
        tags                 : {}
        enterpriseDatabase   : False
        enterpriseCluster    : False
        ```


   * Sub-Project
  
        ```
        Get-Instance -subprojectId "subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73"
        ```

        ```
        id                   : i-55c319eb-5944-4d00-a927-02e2eff4430a
        createdDate          : 9/18/2025 4:09:23 PM
        createdBy            : tnewnham@innovestsystems.com
        projectId            : project-84193807-a81d-4b9b-895b-6c8d8292b55a
        subprojectId         : subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73
        deploymentZoneId     : deploymentzone-na-central-kc
        imageId              : ssnc-cloud-w2k25-base
        name                 : demo
        ip                   : 10.222.14.205
        dns                  : 10-222-14-205.ssnc-corp.cloud
        site                 : na-central-kc
        state                : available
        migrated             : False
        tasksStatus          : COMPLETED
        storageConfiguration : DEFAULT
        workloadType         : CLOUD_WINDOWS
        osType               : Windows
        osVersion            : Windows Server 2025

        id                   : i-de3a497c-a96b-408b-83fc-857a5963f677
        createdDate          : 9/18/2025 8:19:01 AM
        createdBy            : tnewnham@innovestsystems.com
        projectId            : project-84193807-a81d-4b9b-895b-6c8d8292b55a
        subprojectId         : subproject-e54bdd6e-228c-443f-b5ce-f7c8bfa25a73
        deploymentZoneId     : deploymentzone-na-central-kc
        imageId              : ssnc-cloud-w2k25-base
        name                 : server1
        ip                   : 10.173.18.167
        dns                  : 10-173-18-167.ssnc-corp.cloud
        site                 : na-central-kc
        state                : available
        migrated             : False
        tasksStatus          : COMPLETED
        storageConfiguration : DEFAULT
        workloadType         : CLOUD_WINDOWS
        osType               : Windows
        osVersion            : Windows Server 2025
        ```

#### More to come...