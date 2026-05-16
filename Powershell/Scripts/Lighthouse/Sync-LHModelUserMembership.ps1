$CitrixRegionCodes = 'sg', 'tk', 'uk', 'us'
$CitrixRoles = 'trader', 'business', 'dev'

# Create regex pattern like: role-citrix-(sg|tk|uk|us)-(trader|business|dev)
$Pattern = '^role-citrix-(' + ($CitrixRegionCodes -join '|') + ')-(' + ($CitrixRoles -join '|') + '),'


Get-ADUser -SearchBase "OU=ShadowAccounts,OU=Managed,OU=Domain Users,DC=sscclient161,DC=ssncad,DC=global" -Properties MemberOf -Filter * |
Select-Object Name, @{Name='HasCitrixRole'; Expression = {if ($_.MemberOf -match $Pattern){$true}else{$false}}
}






$CitrixRegionCodes = 'sg', 'tk', 'uk', 'us'
$CitrixRoles = 'trader', 'business', 'dev'

# Create regex pattern like: role-citrix-(sg|tk|uk|us)-(trader|business|dev)
$Pattern = '^role-citrix-(' + ($CitrixRegionCodes -join '|') + ')-(' + ($CitrixRoles -join '|') + ')'

$LHModelAfter = Import-Csv .\LHModelAfter.csv | Group-Object ModelSamAccountName


$MembershipChanges = @()

ForEach ($LHModel In $LHModelAfter) {
    $SourceExists = $false
    Write-Host "Starting Compare for Model User $($LHModel.Name)" -ForegroundColor Green
    
    Try {
        $sourceADUser = get-aduser $LHModel.Name -Properties memberof -ErrorAction Stop
        $SourceList = $sourceADUser.memberof | Get-ADGroup | Select-Object -ExpandProperty name | Where-Object { $_ -notmatch $pattern }
        $SourceExists = $true    
    } Catch {
        Write-Host "Error processing Source user: $($LHModel.Name) - $_" -ForegroundColor Red
        #Continue
    }
        
    ForEach ($LHUser In $LHModel.Group) {
        
        Try {
            
            If ($SourceExists) {
                $ADUser = Get-ADUser $LHUser.UPN -Properties memberof -ErrorAction Stop
                
                
                # Prepare the table with status
                $DestList = $ADUser.memberof | Get-ADGroup | Select-Object -ExpandProperty name | Where-Object { $_ -notmatch $pattern }
                
                If (-not $DestList) {
                    # If DestList is null or empty, everything from SourceList needs to be added
                    $results = $SourceList | Select-Object @{ Name = 'Item'; Expression = { $_ } },
                                                           @{ Name = 'Action'; Expression = { 'Add' } }
                } Else {
                    # Otherwise, do the proper comparison
                    $comparison = Compare-Object -ReferenceObject $SourceList -DifferenceObject $DestList
                    
                    $results = $comparison | Select-Object @{ Name = 'Name'; Expression = { $LHUser.Name } },
                                                           @{ Name = 'samAccountName'; Expression = { $LHUser.UPN } },
                                                           @{ Name = 'ModelAccount'; Expression = { $LHUser.'Model Account' } },
                                                           @{ Name = 'ADGroup'; Expression = { $_.InputObject } },
                                                           @{ Name = 'Action'; Expression = { If ($_.SideIndicator -eq '<=') { 'Add' } ElseIf ($_.SideIndicator -eq '=>') { 'Remove' } } }
                }
                
                # Display the results per user
                If ($results) {
                    #Write-Host "`nUser: $($LHUser.UPN)" -ForegroundColor Cyan
                    $MembershipChanges += $results
                } Else {
                    #Write-Host "`nUser: $($LHUser.UPN) - No Changes" -ForegroundColor Green
                    
                }
            } Else {
                Write-Host "Error processing Source user: $($LHModel.Name) - $($LHUser.UPN) not processed!!" -ForegroundColor Red
            }
            
            
        } Catch {
            Write-Host "Error processing user: $($LHUser.UPN) - $_" -ForegroundColor Red
            Continue
        }
    }
    
    
}


