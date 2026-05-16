
NAME
    C:\Source-WinEng\WinEng\Copy-ExistingFolderACE\Copy-ExistingFolderACE.ps1
    
SYNOPSIS
    This script will duplicate an existing ACE using a new TargetID.
    
    
SYNTAX
    C:\Source-WinEng\WinEng\Copy-ExistingFolderACE\Copy-ExistingFolderACE.ps1 [-TargetID] <String> [-SourceID] <String> [-RootFolder] <String> [-SNOWTicket] <String> [-BypassADCheck] [<CommonParameters>]
    
    
DESCRIPTION
    This script will duplicate an existing ACE using a new TargetID.  The script will evaluate all sub directories starting at the RootFolder for the source ID.  Where it is found, a new ACE will be added to the folder ACLs.
    
    This script will not impact any other ACEs.
    
    This script does not support cross domain rights.
    

PARAMETERS
    -TargetID <String>
        Specify the ID to be used in the duplicated ACE.  This should be in the form of DOMAIN\DomainLocalGroup
        
        TargetGroup should be in the local domain only
        
        Required?                    true
        Position?                    1
        Default value                
        Accept pipeline input?       false
        Accept wildcard characters?  false
        
    -SourceID <String>
        Specify the Source ID to duplicate.  This should be in the form of DOMAIN\Group.
        
        This value will be found on the IdentityRefrence attribute on an existing ACE
        
        Required?                    true
        Position?                    2
        Default value                
        Accept pipeline input?       false
        Accept wildcard characters?  false
        
    -RootFolder <String>
        Specify the root folder where the permisions are to be updated.  All sub folders will be evaluated.
        
        Required?                    true
        Position?                    3
        Default value                
        Accept pipeline input?       false
        Accept wildcard characters?  false
        
    -SNOWTicket <String>
        Enter the SNOW Ticket Number that will cover this permission change.  This ticket number will be used as the event log name and can be attached to the SNOW ticket as evidence.
        
        The event log file will be saved in the same directory as the script in the following format: RITM0123456_yyyyMMdd-HHmmss.log
        
        Required?                    true
        Position?                    4
        Default value                
        Accept pipeline input?       false
        Accept wildcard characters?  false
        
    -BypassADCheck [<SwitchParameter>]
        Use this switch to override the validation og the target group in AD.  This will allow the script to run when the execution context does not have access to query Active Directory
        
        Required?                    false
        Position?                    named
        Default value                False
        Accept pipeline input?       false
        Accept wildcard characters?  false
        
    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer, PipelineVariable, and OutVariable. For more information, see 
        about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216). 
    
INPUTS
    
OUTPUTS
    
NOTES
    
    
        Additional information about the file.
    
    -------------------------- EXAMPLE 1 --------------------------
    
    PS C:\>.\Copy-ExistingFolderACE -TargetID 'Value1' -SourceID 'Value2' -RootFolder 'Value3' -SNOWTicket RITM123456
    
    
    
    
    
    
    
RELATED LINKS



