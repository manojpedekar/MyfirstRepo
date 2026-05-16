Class UpdateIDs{
    [guid]$id
    [bool]$InWSUS
    [string]$PatchText
    
    UpdateIDs([guid]$id, [bool]$InWSUS, [string]$PatchText) {
        $this.id = $id
        $this.InWSUS = $InWSUS
        $this.PatchText = $PatchText
    }
}

Class URLList {
    [string]$BaseURL = "https://www.catalog.update.microsoft.com/Search.aspx?q="
    [string]$SearchURL
    [System.Collections.ArrayList]$URLList
    [int]$Pages
    [string]$SearchTerm
    [string]$FormattedSearchTerm
    [System.Collections.ArrayList]$Updates
    
    URLList([string]$SearchTerm) {
        $this.BaseURL = $this.BaseURL
        $this.SearchTerm = $SearchTerm
        $this.FormattedSearchTerm = $SearchTerm.Replace(" ", "+")
        $this.SearchURL = $this.BaseURL + $this.FormattedSearchTerm
        $this.Pages = [URLList]::GetPageCount($this.SearchURL)
        $this.URLList = [URLList]::URLCreateList($this.SearchURL, $this.Pages)
        $this.Updates = Get-UpdateIDs -URLList $this.URLList
    }
    
    Static [System.Collections.ArrayList] URLCreateList([string]$SearchURL, [int]$PageCount) {
        $ListofURLs = [System.Collections.ArrayList]::new()
        
        For ($i = 0; $i -lt $PageCount; $i++) {
            $UpdateURL = $SearchURL + "&p=$($i)"
            [void]$ListofURLs.Add($UpdateURL)
        }
        Return $ListofURLs
    }
    
    Static [int] GetPageCount([string]$SearchURL) {
        
        # Get the page content
        $response = Invoke-WebRequest -Uri $SearchURL
        $content = $response.Content
        
        # Regular Expression to find the text '(page X of Y)'
        $regex = "\(page \d+ of (\d+)\)"
        
        # Extract the maximum page number using the regex
        If ($content -match $regex) {
            $results = $Matches[1]
        } Else { Return 0 }
        
        Return $results
    }
    
    Static [System.Collections.ArrayList] GetUpdateIDs([string[]]$URLList) {
        # Connect to the WSUS Server
        $wsus = Connect-WSUS
        
        $UIDs = [System.Collections.ArrayList]::new()
        $idPattern = "goToDetails\(""(.*?)\""\)"
        
        ForEach ($URL In $URLList) {
            $response = (Invoke-WebRequest -Uri $URL).Links | Where-Object { $_.id -like "*_link" }
            
            ForEach ($item In $response) {
                $id = $null
                $update = $null
                $PatchText = $item.innerText
                $InWSUS = $False
                
                If ($item -match $idPattern) {
                    
                    Try {
                        $id = New-Object System.Guid($matches[1])
                        $update = $wsus.GetUpdate($id) | Out-Null
                    } Catch [System.Management.Automation.MethodInvocationException] {
                        # New-Object System.Guid($matches[1]) not a GUID
                    } Catch [System.Management.Automation.MethodException] {
                        # issue with $wsus.GetUpdate
                    } Catch {
                        #Write-Host "Failed to retrieve update: $_"
                    }
                    
                    If ($update) {
                        $InWSUS = $true
                    }
                } Else {
                    $PatchText = "No Data Returned"
                }
                
                $record = [UpdateIDs]::new($id, $InWSUS, $PatchText)
                [void]$UIDs.Add($record)
                
            }
            
        }
        Return $UIDs
        
    }
    
}

Function Get-UpdateIDs([string[]]$URLList) {

    # Connect to the WSUS Server
    $wsus = Connect-WSUS

    $UIDs = [System.Collections.ArrayList]::new()
    $idPattern = "goToDetails\(""(.*?)\""\)"
    
    ForEach ($URL In $URLList) {
        $response = (Invoke-WebRequest -Uri $URL).Links | Where-Object { $_.id -like "*_link" }
        
        ForEach ($item In $response) {
            $id = $null
            $update = $null
            $PatchText = $item.innerText
            $InWSUS = $False
            
            If ($item -match $idPattern) {
                
                Try {
                    $id = New-Object System.Guid($matches[1])
                    $update = $wsus.GetUpdate($record.id) | Out-Null
                } Catch [System.Management.Automation.MethodInvocationException] {
                    # New-Object System.Guid($matches[1]) not a GUID
                } Catch [System.Management.Automation.MethodException] {
                    # issue with $wsus.GetUpdate
                } Catch {
                    #Write-Host "Failed to retrieve update: $_"
                }
                
                If ($update) {
                    $InWSUS = $true
                }
            } Else {
                $PatchText = "No Data Returned"
            }
            
            $record = [UpdateIDs]::new($id,$InWSUS, $PatchText)
            [void]$UIDs.Add($record)
            
        }
        
    }
    Return $UIDs
}

# Connect-WSUS was duplicated here; the canonical version lives in the
# SSNCWSUS module. Callers in this file invoke Connect-WSUS via:
#     Import-Module (Join-Path $PSScriptRoot '..\..\Module\SSNCWSUS\SSNCWSUS.psd1')