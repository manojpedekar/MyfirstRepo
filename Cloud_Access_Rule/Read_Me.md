Go to the file path of tha funtion file and run below command

`. .\Function.ps1`

`$env:SSNC_API_KEY = "your-api-key"`

`New-NetAccessBatch -JsonPath "C:\path\to\NetworkRules.json"`

or 

`New-NetAccessBatch -JsonPath "C:\path\to\NetworkRules.json" -APIKey $env:SSNC_API_KEY`