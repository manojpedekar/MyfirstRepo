Function Start-HttpListener {
	Param (
		[string]$Url = 'http://localhost:8080/'
	)
	
	# Generate a unique key
	$Key = [Guid]::NewGuid().ToString()
	Write-Host "Generated Key: $Key"
	
	# Create a synchronized hashtable to control the loop
	$syncHash = [hashtable]::Synchronized(@{ Running = $true })
	
	$listener = New-Object System.Net.HttpListener
	$listener.Prefixes.Add($Url)
	$listener.Start()
	
	Write-Host "Listening at $Url"
	
	While ($syncHash.Running) {
		$context = $listener.GetContext()
		$request = $context.Request
		$response = $context.Response
		
		# Process the request
		$reader = New-Object System.IO.StreamReader($request.InputStream)
		$requestData = $reader.ReadToEnd() | ConvertFrom-Json
		
		$responseString = ""
		
		If ($requestData.Key -eq $Key) {
			If ($requestData.Command -eq "Stop") {
				$syncHash.Running = $false
				$responseString = "Stopping listener."
			} Else {
				$scriptBlock = [ScriptBlock]::Create($requestData.ScriptBlock)
				$job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $requestData.Arguments
				Receive-Job -Job $job -Wait
				
				$responseString = "Task started."
			}
		} Else {
			$responseString = "Invalid key."
		}
		
		# Send the response
		$buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
		$response.ContentLength64 = $buffer.Length
		$output = $response.OutputStream
		$output.Write($buffer, 0, $buffer.Length)
		$output.Close()
	}
	
	$listener.Stop()
	Write-Host "Listener stopped."
}


# Example of calling the HTTP listener
$uri = 'http://localhost:8080/'
$key = '7f8e9229-c3fd-441e-9379-d6180775ba09'
$scriptBlock = "dir c:\windows"
$myargs = @("Hello, World!")

$body = @{
	Key		    = $key
	ScriptBlock = $scriptBlock
	Arguments   = $myargs
} | ConvertTo-Json

Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/json'



$body = @{
	Key	    = $key
	Command = 'Stop'
} | ConvertTo-Json

Invoke-RestMethod -Uri 'http://localhost:8080/' -Method Post -Body $body -ContentType 'application/json'



