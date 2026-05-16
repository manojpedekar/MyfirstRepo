<#
    .SYNOPSIS
        A brief description of the ssnc_winbootstrap_automated_v2.ps1 file.
    
    .DESCRIPTION
        A description of the file.
    
    .PARAMETER version
        Option 1 means case insensitive
        Supports new version and latest
        Doesn't support versions prior to "YYYY.M.R-B"
    
    .PARAMETER pythonVersion
        Doesn't support Python versions prior to "2017.7.0"
    
    .PARAMETER runservice
        A description of the runservice parameter.
    
    .PARAMETER minion
        A description of the minion parameter.
    
    .PARAMETER master
        A description of the master parameter.
    
    .PARAMETER repourl
        A description of the repourl parameter.
    
    .PARAMETER ConfigureOnly
        A description of the ConfigureOnly parameter.
    
    .PARAMETER Datacenter
        A description of the Datacenter parameter.
    
    .PARAMETER AppID
        A description of the AppID parameter.
    
    .PARAMETER BackupSchedule
        A description of the BackupSchedule parameter.
    
    .PARAMETER Environment
        A description of the Environment parameter.
    
    .PARAMETER Org
        A description of the Org parameter.
    
    .NOTES
        ===========================================================================
        Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
        Created on:   	2/17/2025 8:22 AM
        Created by:   	DT234083
        Organization: 	SS&C
        Filename:
        ===========================================================================
#>
[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [ValidatePattern('^(\d{4}(\.\d{1,2}){0,2}(\-\d{1})?)|(latest)$')]
    [string]$version = '3005.1-4',
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [ValidateSet('2', '3')]
    [string]$pythonVersion = "3",
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [boolean]$runservice = $true,
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [string]$minion = {$computerInfo = Get-WmiObject Win32_ComputerSystem
        If ($computerInfo.PartOfDomain) {
            "$env:COMPUTERNAME.$($computerInfo.Domain)"
        } Else {
            $env:COMPUTERNAME
        }
    },
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [string]$master = "kc-saltmaster-06.ssnc-corp.cloud",
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [string]$repourl = "https://artifactory.ssnc.dev/artifactory/es-salt-local/salt/windowsminion/",
    [Parameter(Mandatory = $false,
               ValueFromPipeline = $true)]
    [switch]$ConfigureOnly,
    [string]$Datacenter = 'not-specified',
    [string]$AppID = '9999',
    [string]$PatchSchedule = 'self-managed',
    [string]$Environment = 'not-specified',
    [string]$Org = 'not-specified'
)

###########################################
##                 VARS                  ##
###########################################
$ConfiguredAnything = $False
$DomainCSVURL = "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fdomains%2FREPLACEME&isNativeBrowsing=true"

# Directories used during Install
$TempDir = "C:\Temp"
$ScriptDir = Join-Path -Path $TempDir -ChildPath "Bootstrap"

$computersystem = Get-WmiObject Win32_ComputerSystem
$ComputerInfo = [pscustomobject]@{
    'ComputerName'   = $env:COMPUTERNAME
    'ComputerDomain' = $computersystem.Domain
    'PartOfDomain'   = $computersystem.PartOfDomain
    'fqdn'           = [System.Net.Dns]::GetHostByName(($env:COMPUTERNAME)).Hostname
    'Manufacturer'   = $computersystem.Manufacturer
    'Model'          = $computersystem.Model
    'CSVFile'        = $computersystem.Domain.replace(".", "_") + '.csv'
    'DomainAnswerFile' = Join-Path -Path $ScriptDir -ChildPath ($computersystem.Domain.replace(".", "_") + '.csv')
    'URL' = $DomainCSVURL -replace "REPLACEME", $ComputerInfo.CSVFile
}


#===============================================================================
# Set install paths
#===============================================================================
If ($version -lt "3004" -and $version -gt "1") {
    $RootDir = "C:\Salt"
    $Progcmd = "C:\Salt\salt-call.bat"
} Else {
    $RootDir = "C:\Programdata\Salt Project\Salt"
    $Progcmd = "C:\Program Files\Salt Project\Salt\salt-call.bat"
}
$ConfDir = "$RootDir\conf"
$PkiDir = "$ConfDir\pki\minion"

# this list could be expanded to support additional properties as well as being a file generated nightly or based on other changes
# if this were its own file stored on artifactory, we should just download and consume it

$DCData = @"
[
    {
        "DC": "Advent",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-01.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fadventyktgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Harrison",
        "dcgrain": "harrison",
        "saltmaster": "kc-saltmaster-02.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fhrsgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Yorktown",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-03.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fyktgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]    },
    {
        "DC": "Windsor",
        "dcgrain": "windsor",
        "saltmaster": "kc-saltmaster-04.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fwctgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]    },
    {
        "DC": "St. Louis",
        "dcgrain": "st_louis",
        "saltmaster": "kc-saltmaster-05.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fstlgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]    },
    {
        "DC": "Winchester",
        "dcgrain": "winchester",
        "saltmaster": "kc-saltmaster-06.ssnc-corp.cloud",
                "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fwdcgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "London",
        "dcgrain": "london",
        "saltmaster": "kc-saltmaster-07.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fldngrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Malad",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-08.ssnc-corp.cloud",
                "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fmaladgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Airoli",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-09.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fairoligrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Asia",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-10.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fasiagrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "North America",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-11.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fnorthamericagrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Stockholm",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-12.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Fstockholmgrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Australia",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-13.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Faustraliagrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    },
    {
        "DC": "Europe",
        "dcgrain": "yorktown",
        "saltmaster": "kc-saltmaster-14.ssnc-corp.cloud",
        "urls": [
            {
                "name": "Minion File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fgenericminion&isNativeBrowsing=true",
                "destination": "minion/minion"
            },
            {
                "name": "Master Certificate",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fminion%2Fmaster_sign.pub&isNativeBrowsing=true",
                "destination": "minion/master_sign.pub"
            },
            {
                "name": "Grains File",
                "url": "https://artifactory.ssnc.dev/ui/api/v1/download?repoKey=es-salt-local&path=salt%2Fbootstrap%2Fgrains%2Feuropegrains&isNativeBrowsing=true",
                "destination": "grains"
            }
        ]
    }
]

"@ | ConvertFrom-Json

# this list can be obtained from the https://portal.ssnc-corp.cloud/api/v2/swagger-ui/index.html#/Compute/getPatchGroups API
# could be its own file on the artifactory share and consumed directly
$PatchingGroups = @(
    "4th-tues-6pm-10pm",
    "4th-thurs-6pm-10pm",
    "3rd-sat-9am-3pm (Domain Controllers Only)",
    "3rd-sat-8pm-2am (Domain Controllers Only)",
    "3rd-sat-2am-8am (Domain Controllers Only)",
    "1st-sun-2am-5am",
    "3rd-sun-2am-5am",
    "1st-sat-8pm-2am (Domain Controllers Only)",
    "1st-sat-6pm-10pm",
    "2nd-sat-12pm-4pm",
    "4th-sat-8pm-2am (Domain Controllers Only)",
    "1st-sat-9am-3pm (Domain Controllers Only)",
    "1st-sun-3am-5am",
    "4th-sun-2am-5am",
    "self-managed",
    "4th-tues-10pm-4am",
    "4th-thurs-10pm-4am",
    "4th-sat-2am-8am (Domain Controllers Only)",
    "2nd-sat-6pm-10pm",
    "2nd-sun-6pm-10pm",
    "4th-sat-9am-3pm (Domain Controllers Only)",
    "3rd-thurs-6pm-10pm",
    "3rd-sat-10pm-4am",
    "2nd-sun-2am-5am",
    "1st-sun-12am-4am",
    "3rd-tues-6pm-10pm",
    "3rd-sat-12pm-4pm",
    "1st-mon-2am-6am",
    "4th-sat-6pm-10pm",
    "4th-sun-12am-2am",
    "2nd-sun-12am-4am",
    "3rd-tues-10pm-4am",
    "3rd-thurs-10pm-4am",
    "1st-sat-12pm-4pm",
    "1st-sat-2am-8am (Domain Controllers Only)",
    "3rd-mon-2am-6am",
    "1st-sun-6pm-10pm",
    "4th-sat-12pm-4pm"
)

###########################################
##              FUNCTIONS                ##
###########################################

Function Log-Message {
    
	<#
	.SYNOPSIS
	    Logs a message to both the console and a specified log file.
	.DESCRIPTION
	    The Log-Message function writes a message with a timestamp to the standard output and appends the same message to a log file. It checks if the directory for the log file exists and creates it if necessary.
	.PARAMETER message
	    The message text to log. This parameter is required.
	.PARAMETER filePath
	    The path to the log file where the message will be appended. Defaults to 'C:\temp\automationlog.log'.
	.EXAMPLE
	    Log-Message -Message "Process completed successfully"
	    Logs the message with a timestamp to the console and to 'C:\temp\automationlog.log'.
	.EXAMPLE
	    Log-Message -Message "User logged in" -filePath "C:\logs\userlog.log"
	    Logs the message to the console and to a specified file path.
	.NOTES
	    This function requires that the user has the necessary permissions to create directories and write to files in the specified paths.
	#>
    
    Param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$filePath = "C:\temp\SaltInstall.log"
    )
    $timestamp = [datetime]::Now
    $logEntry = "$timestamp : $message"
    
    # Ensure the directory exists
    $dir = Split-Path -Path $filePath
    If (-not (Test-Path -Path $dir)) {
        Try {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
        } Catch {
            Write-Error "Failed to create directory '$dir': $_"
            Return # Exit the function if the directory cannot be created
        }
    }
    
    # Try to write to the log file
    Try {
        Add-Content -Path $filePath -Value $logEntry -ErrorAction Stop
    } Catch {
        Write-Error "Failed to write to log file: $_"
    }
}

Function Get-DatacenterSelection {
    
    Param
    (
        [pscustomobject]$DatacenterData
    )
    
    # Ensure $DatacenterData is not empty
    If (-not $DatacenterData) {
        Write-Host "Error: DatacenterData is empty or null." -ForegroundColor Red
        Return $null
    }
    
    
    Write-Host "`nPlease select a Datacenter:" -ForegroundColor Cyan
    
    # Display the menu dynamically based on DatacenterData
    For ($i = 0; $i -lt $DatacenterData.Count; $i++) {
        Write-Host "$($i + 1)) $($DatacenterData[$i].DC)"
    }
    
    # Get user input
    $selection = Read-Host "`nEnter the number of your choice"
    
    # Validate input
    If ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $DatacenterData.Count) {
        $Datacenter = $DatacenterData[[int]$selection - 1]
        Write-Host "`nYou selected: $($Datacenter.DC)" -ForegroundColor Green
    } Else {
        Write-Host "`nInvalid selection. Please try again." -ForegroundColor Red
        Return Get-DatacenterSelection -DatacenterData $DatacenterData # Recursive retry
    }
    
    Return $Datacenter
}

Function Get-PatchingGroup {
    Param (
        [string[]]$PatchingGroups,
        [string]$SelectedGroup = 'not-specified'
    )
    
    # Validate input array
    If (-not $PatchingGroups -or $PatchingGroups.Count -eq 0) {
        Write-Host "Error: PatchingGroups array is empty or null." -ForegroundColor Red
        Return $null
    }
    
    # Sort the list alphabetically
    $SortedGroups = $PatchingGroups | Sort-Object
    
    # If Datacenter is 'not-specified', prompt the user
    If ($SelectedGroup -eq 'not-specified') {
        Write-Host "`nPlease select a Patching Group:" -ForegroundColor Cyan
        
        # Display the sorted menu
        For ($i = 0; $i -lt $SortedGroups.Count; $i++) {
            Write-Host "$($i + 1)) $($SortedGroups[$i])"
        }
        
        # Get user input
        $selection = Read-Host "`nEnter the number of your choice"
        
        # Validate input
        If ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $SortedGroups.Count) {
            $SelectedGroup = $SortedGroups[[int]$selection - 1]
            Write-Host "`nYou selected: $SelectedGroup" -ForegroundColor Green
        } Else {
            Write-Host "`nInvalid selection. Please try again." -ForegroundColor Red
            Return Get-PatchingGroup -PatchingGroups $PatchingGroups # Recursive retry
        }
    }
    
    Return $SelectedGroup
}

Function Get-IsAdministrator {
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
    $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

Function Get-IsUacEnabled {
    (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System).EnableLua -ne 0
}

Function Get-Grains {
    #not in love with this validateion.  One small change to the file could invalidate this function
    $filecontents = Get-Content $ScriptDir\grains
    $filecontents
    Write-Output "Grain should be ssnc_datacenter: ""$dcgrain"""
    If ($filecontents[4] -eq "ssnc_datacenter: ""$dcgrain""") {
        Write-Output "ssnc_datacenter: ""$dcgrain"""
        Write-Output "Grains file valid"
    } Else {
        Write-Error 'Grains file has not downloaded correctly' -ErrorAction Stop
    }
}

Function Get-SaltFiles {
    Param (
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$URLList,
        [Parameter(Mandatory = $true)]
        [string]$RootFolder
    )
    
    # Enable TLS 1.2 support
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    
    # Ensure RootFolder exists
    If (-not (Test-Path -Path $RootFolder)) {
        Write-Host "Creating root directory: $RootFolder" -ForegroundColor Yellow
        New-Item -Path $RootFolder -ItemType Directory -Force | Out-Null
    }
    
    ForEach ($URL In $URLList) {
        Try {
            
            # Construct download path
            $DLPath = Join-Path -Path $RootFolder -ChildPath $URL.destination
            
            # Ensure destination directory exists
            $DLDirectory = Split-Path -Path $DLPath -Parent
            If (-not (Test-Path -Path $DLDirectory)) {
                Write-Host "Creating directory: $DLDirectory" -ForegroundColor Yellow
                New-Item -Path $DLDirectory -ItemType Directory -Force | Out-Null
            }
            
            Write-Host "Downloading '$($URL.name)' from: $($URL.url) to: $DLPath" -ForegroundColor Cyan
            
            # Perform download with progress tracking
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($URL.url, $DLPath)
            Write-Host "Downloaded '$($URL.name)' to: $DLPath" -ForegroundColor Green
        } Catch {
            Write-Host "Error downloading '$($URL.name)' from $($URL.url): $_" -ForegroundColor Red
        } Finally {
            If ($webClient) { $webClient.Dispose() }
        }
    }
}

###########################################
##               SCRIPT                  ##
###########################################

Begin {
    
    If (!(Get-IsAdministrator)) {
        If (Get-IsUacEnabled) {
            # We are not running "as Administrator" - so relaunch as administrator
            # Create a new process object that starts PowerShell
            $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
            
            # Specify the current script path and name as a parameter`
            $parameters = ""
            ForEach ($boundParam In $PSBoundParameters.GetEnumerator()) {
                $parameters = "$parameters -{0} '{1}'" -f $boundParam.Key, $boundParam.Value
            }
            $newProcess.Arguments = $myInvocation.MyCommand.Definition, $parameters
            
            # Specify the current working directory
            $newProcess.WorkingDirectory = "$script_path"
            
            # Indicate that the process should be elevated
            $newProcess.Verb = "runas";
            
            # Start the new process
            [System.Diagnostics.Process]::Start($newProcess);
            
            # Exit from the current, unelevated, process
            Exit
        } Else {
            Throw "You must be administrator to run this script"
        }
    }
    
    #===============================================================================
    # Verify Parameters
    #===============================================================================
    Write-Verbose "Parameters passed in:"
    Write-Verbose "version: $version"
    Write-Verbose "runservice: $runservice"
    Write-Verbose "master: $master"
    Write-Verbose "minion: $minion"
    Write-Verbose "repourl: $repourl"
    
    Switch ($runservice) {
        $true {
            Write-Verbose "Windows service will be set to run"
        }
        $false {
            Write-Verbose "Windows service will be stopped and set to manual"
        }
        default {
            # Param passed in wasn't clear so defaulting to true.
            Write-Verbose "Windows service defaulting to run automatically"
        }
    }
    
    # Remove C:\Temp\Bootstrap if it exists.  Folders will be created as files are downloaded in Get-SaltFiles
    If (Test-Path -Path $ScriptDir) {
        Write-Host "Removing existing directory: $ScriptDir"
        Remove-Item -Path $ScriptDir -Recurse -Force
    }
    
    New-Item -Path $ScriptDir -ItemType Directory -Force | Out-Null
    
}
Process {
    
    Write-Host "Downloading '$($ComputerInfo.CSVFile)' from: $($ComputerInfo.URL) to: $ScriptDir" -ForegroundColor Cyan
    
    # Try to download the file with error handling
    Try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($ComputerInfo.URL, $ComputerInfo.DomainAnswerFile)
        Write-Host "Successfully downloaded Domain Answer File to: $ScriptDir" -ForegroundColor Green
        
        $ComputerAnswers = Import-Csv $ComputerInfo.DomainAnswerFile | Where-Object { $_.fqdn -eq $ComputerInfo.fqdn }
        
        # Check the number of records returned
        $recordCount = $ComputerAnswers.Count
        
        Switch ($recordCount) {
            0 {
                Write-Host "$($ComputerInfo.fqdn) not found in $($ComputerInfo.CSVFile)." -ForegroundColor Red
            }
            1 {
                Write-Host "1 matching record found in $($ComputerInfo.CSVFile)." -ForegroundColor Green
                
                # we will want to do some validation on these answers prior to just blasting them in
                # or we can just assume the answer file has been reviewed and is correct -- This is what we are doing fore the moment
                $Datacenter = $ComputerAnswers.Datercenter.tolower()
                $AppID = $ComputerAnswers.AppID
                $PatchSchedule = $ComputerAnswers.PatchSchedule.tolower()
                $Environment = $ComputerAnswers.Environment.tolower()
                $Org = $ComputerAnswers.Org.toupper()
            }
            default {
                Write-Host "Multiple matching records found ($recordCount) in $($ComputerInfo.CSVFile)." -ForegroundColor Yellow
            }
        }
        
    } Catch [System.Net.WebException] {
        Write-Host "Web Error: Failed to download Domain Answer File. Status: $($_.Exception.Response.StatusCode) - $($_.Exception.Message)" -ForegroundColor Red
    } Catch {
        Write-Host "An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
    } Finally {
        If ($webClient) {
            $webClient.Dispose()
        }
    }
    
    If ($Datacenter -eq 'not-specified') {
        $SelectedDC = Get-DatacenterSelection -DatacenterData $DCData
        $Datacenter = $SelectedDC.dcgrain.tolower()
    }
    
    
    
    
}
End {
    
}


