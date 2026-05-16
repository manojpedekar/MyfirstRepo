#Set Execution Scope
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

#(First time only) Trust the PowerShell Gallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

#Install Module
Install-Module -Name VMware.PowerCLI

#PowerCLI’s module VMware.VimAutomation.Core provides commands with the same names, so PowerShell blocks the install to avoid conflicts. In this situation run below command.
Install-Module VMware.PowerCLI -AllowClobber

#Install Specific Version (Optional)
Install-Module VMware.PowerCLI -RequiredVersion 13.3.0

#Verify Instalaltion
Get-Module VMware.PowerCLI -ListAvailable

#Avoid certificate warnings (very common in labs):
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

TLS/SSL issues
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Optional: Disable CEIP Prompt
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false


#Verify PowerCLI Works
Get-PowerCLIVersion
Connect-VIServer vcenter.example.com

#Best Practice (Avoid Confusion) Load VMware PowerCLI explicitely.
Import-Module VMware.PowerCLI


#Upgrade PowerCL
Update-Module VMware.PowerCLI

#Uninstall PowerCLI
Uninstall-Module VMware.PowerCLI -AllVersions



