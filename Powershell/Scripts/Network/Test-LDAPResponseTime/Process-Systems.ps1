Function Process-Systems {
    Param ([string[]]$Records,
        [string]$RecordType
    )
    
    $ProcessedRecords = New-Object System.Collections.Generic.List[Object]
    
    ForEach ($Record In $Records) {
        If (-not ([string]::IsNullOrEmpty($Record))) {
            # Create a custom object with name and type properties
            $obj = New-Object PSObject -Property @{
                Name       = $Record
                DeviceType = $RecordType
            }
            
            # Add the custom object to the list
            [void]$ProcessedRecords.Add($obj)
            
            # Add a log message indicating success
        } Else {
            # Add a failure log message
            # Write-Host "Failed to add: Line is empty"
        }
        
    }
    Return $ProcessedRecords
}