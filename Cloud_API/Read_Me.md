Go to the file path of tha funtion file and run below command



`$env:SSNC_API_KEY = "your-api-key"`

`. .\Function.ps1`

`New-NetAccessBatch -JsonPath "C:\path\to\NetworkRules.json"`

or 

`New-NetAccessBatch -JsonPath "C:\path\to\NetworkRules.json" -APIKey $env:SSNC_API_KEY`