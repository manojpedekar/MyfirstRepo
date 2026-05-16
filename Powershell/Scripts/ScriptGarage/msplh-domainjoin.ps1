<#    
# ****************************************
# Dale Hollis
# Intended to join a new server to a domain using salt
# Must be run on the server being joined
# v1.0 - Initial Version
# 
# 
# 
# ************ Known Issues ************** 
# None  

#>

# Establish standard log variables
$Date = Get-Date -Format yyyy-M-d
$LogName = "_JoinServerToDomain" #For use in the log filenames
$Log = $Date + $LogName + ".txt"
$ErrorLog = $Date + $LogName + "Errors.txt"
$FilePath = "C:\temp"

Start-Transcript -Path $FilePath\$Log


Write-Host "Getting interface index"

#Set NIC variables
    $NIC               = Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses -like "*.*.*.*"}
    $Nicindex          = $NIC.InterfaceIndex



# Set DNS server IPs
    $DNS               = "100.98.0.8","100.98.8.4"

# Attempt to set the NIC's DNS servers
    Try{

        Set-DnsClientServerAddress -InterfaceIndex $Nicindex -ServerAddresses ($DNS)

    }
    Catch{

        Write-Host "Unable to set DNS client server addresses `n`tError: $($($_.Exception).Message)"
    }



# Establish domain variables
$vnetbios                   = "sscclient161"
$ClientDomFQDN              = $vnetbios + ".ssncad.global"
$TargetDomName              = $ClientDomFQDN

# Establish variables for user. The user account will need to be an account in the new domain. #This information must be provided when executing the scipt.
$strRemoteAdmin             = "Administrator"



# Sets the OU path depending on the team the server belongs to. Landing Zone is the default OU.

    $OUPath = "OU=ServerByProject,OU=Windows,OU=Domain Servers,DC=" + $vnetbios + ",DC=ssncad,DC=global"


# Attempts to join the server to the domain
Write-Host "*********************************************** `n         Attempting to join server to domain $TargetDomName  `n`t`t in OU $OUPath"
$PWord = ConvertTo-SecureString -String $strRemoteAdminPassword -AsPlainText -Force
$Cred = get-credential 
    Try{
        
        Add-Computer -DomainName $TargetDomName -PassThru -Verbose -OUPath $OUPath -Credential $Cred -Force -Restart  
    }
    Catch{
        Write-Host "Unable to join domain: Failed `n`tError: $($($_.Exception).Message)"
    }

    
Stop-Transcript
