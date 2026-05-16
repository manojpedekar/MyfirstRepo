<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	2/11/2025 3:01 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>


Function Start-SpeedTestServer {
    
    Param (
        [ValidateRange(1, 65535)]
        [int]$Port = 8080,
        [switch]$RunUntilClosed
    )
    
    $listener = [System.Net.Sockets.TcpListener]::new($Port)
    $listener.Start()
    Write-Host "Listening on port $Port..."
    
    Try {
        Do {
            $client = $listener.AcceptTcpClient()
            $startTime = Get-Date
            $clientEndpoint = $client.Client.RemoteEndPoint.ToString()
            Write-Host "Connection from $clientEndpoint started at $startTime"
            
            $stream = $client.GetStream()
            $buffer = New-Object byte[] 1024
            $totalRead = 0
            
            # Continue reading data until client closes the connection
            While (($read = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) {
                $totalRead += $read
            }
            
            $endTime = Get-Date
            Write-Host "   Upload finished at $endTime"
            $duration = $endTime - $startTime
            $durationInSeconds = $duration.TotalSeconds
            
            $speedMegaBytesps = [math]::round($totalRead / ($durationInSeconds * 1MB),2)
            $speedMegaBitsps = [math]::Round(($totalRead * 8) / ($durationInSeconds * 1MB),2)
            
            Write-Host "   Total data received from $clientEndpoint : $totalRead bytes"
            Write-Host "   Time taken: $durationInSeconds seconds"
            Write-Host "   Speed: $speedMegaBytesps MB/s"
            Write-Host "   Speed: $speedMegaBitsps /Mbps"
            $stream.Close()
            $client.Close()
        } While ($RunUntilClosed)
    } Finally {
        $listener.Stop()
        Write-Host "Server stopped."
    }
}

Function Create-BalastFile {
    Param (
        [string]$filePath = "C:\Temp\Dummy.deleteme",
        [ValidateScript({
                If ($_ -match '^\d+(\.\d+)?(KB|MB|GB)$') {
                    $true
                } Else {
                    Throw "Size must be a numeric value followed by KB, MB, or GB (e.g., '10GB')"
                }
            })]
        [string]$size = "10GB"
    )
    
    # Convert size to bytes for SetLength
    $sizeInBytes = Switch -Regex ($size) {
        'KB$' { [int]($size -replace 'KB', '') * 1KB }
        'MB$' { [int]($size -replace 'MB', '') * 1MB }
        'GB$' { [int]($size -replace 'GB', '') * 1GB }
    }
    
    # Create a file and set its length
    $fileStream = [System.IO.File]::Create($filePath)
    $fileStream.SetLength($sizeInBytes)
    $fileStream.Close()
    
    Write-Host "File created at $filePath with size $size."
}

Function Start-SpeedTestClient {
    Param (
        [string]$SpeedTestServer = "10.102.0.10",
        [string]$filePath = "C:\Temp\Dummy.deleteme",
        [ValidateRange(1, 65535)]
        [int]$Port = 8080
    )
    
    
    # Start timer
    $startTime = Get-Date
    
    # Send the file
    $client = New-Object System.Net.Sockets.TcpClient($SpeedTestServer, $Port)
    $stream = $client.GetStream()
    $fileStream = [System.IO.File]::OpenRead($filePath)
    $buffer = New-Object Byte[] 1024
    $bytesRead = 0
    
    Try {
        Do {
            $bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)
            $stream.Write($buffer, 0, $bytesRead)
        } While ($bytesRead -ne 0)
    } Finally {
        $fileStream.Close()
        $stream.Close()
        $client.Close()
    }
    
    # Stop timer
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $durationInSeconds = $duration.TotalSeconds
    
    # Calculate speed
    $fileSizeInBytes = (Get-Item -Path $filePath).Length
    $speedMegaBytesps = [math]::round($fileSizeInBytes / ($durationInSeconds * 1024 * 1024))
    $speedMegaBitsps = [math]::Round(($fileSizeInBytes * 8) / ($durationInSeconds * 1MB), 2)
    
    # Output results
    "Time taken: $durationInSeconds seconds"
    "Speed: $speedMegaBytesps MB/s"
    "Speed: $speedMegaBitsps /Mbps"
       
    
}

