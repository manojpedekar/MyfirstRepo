Param
(
	[string]$directoryPath
)

Function Get-FileEncoding {
    <#
    .SYNOPSIS
        Gets the file encoding of a specified file.
    .DESCRIPTION
        This function reads the first few bytes of a file and determines its encoding based on the byte order mark (BOM) or specific byte patterns.
    .PARAMETER Path
        The file path to check for encoding.
    .EXAMPLE
        Get-FileEncoding -Path ".\UTF16-BigEndian.txt"
        Returns "Unicode UTF-16 Big-Endian"
    .LINK
        based on https://gist.github.com/jpoehls/2406504
    #>
	
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Please enter the path to a file')]
		[string]$Path
	)
	
	If (-not (Test-Path -Path $Path)) {
		Write-Error "File does not exist."
		Return "Unknown"
	}
	
	[byte[]]$bytes = Get-Content -Encoding Byte -ReadCount 4 -TotalCount 4 -Path $Path
	
	Switch -Regex ($bytes[0 .. 3]) {
		{ $_ -eq [byte[]](0xef, 0xbb, 0xbf) } { Return 'UTF8' }
		{ $_ -eq [byte[]](0xfe, 0xff) } { Return 'Unicode UTF-16 Big-Endian' }
		{ $_ -eq [byte[]](0xff, 0xfe) } { Return 'Unicode UTF-16 Little-Endian' }
		{ $_ -eq [byte[]](0x00, 0x00, 0xfe, 0xff) } { Return 'UTF32 Big-Endian' }
		{ $_ -eq [byte[]](0xff, 0xfe, 0x00, 0x00) } { Return 'UTF32 Little-Endian' }
		{ $_ -eq [byte[]](0x2b, 0x2f, 0x76) -and $bytes[3] -in 0x38, 0x39, 0x2b, 0x2f } { Return 'UTF7' }
		{ $_ -eq [byte[]](0xf7, 0x64, 0x4c) } { Return 'UTF-1' }
		{ $_ -eq [byte[]](0xdd, 0x73, 0x66, 0x73) } { Return 'UTF-EBCDIC' }
		{ $_ -eq [byte[]](0x0e, 0xfe, 0xff) } { Return 'SCSU' }
		{ $_ -eq [byte[]](0xfb, 0xee, 0x28) } { Return 'BOCU-1' }
		{ $_ -eq [byte[]](0x84, 0x31, 0x95, 0x33) } { Return 'GB-18030' }
		default { Return 'ASCII' }
	}
}

# Get all files in the directory
$files = Get-ChildItem -Path $directoryPath -File

ForEach ($file In $files) {
	Write-Host "Starting: $($file.FullName)"
	$Encoding = Get-FileEncoding -Path $file.FullName
	Switch ($Encoding) {
		'ASCII' {
			# Read the content of the file using ASCII encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::ASCII)
		}
		'UTF8' {
			# Read the content of the file using UTF-8 encoding
			Write-Host "   File is already UTF8 encoded." -ForegroundColor Yellow
			Continue
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
		}
		'Unicode UTF-16 Big-Endian' {
			# Read the content of the file using UTF-16 Big-Endian encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::BigEndianUnicode)
		}
		'Unicode UTF-16 Little-Endian' {
			# Read the content of the file using UTF-16 Little-Endian encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::Unicode)
		}
		'UTF32 Big-Endian' {
			# Read the content of the file using UTF-32 Big-Endian encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::GetEncoding(12001)) # 12001 is the code page for UTF-32 BE
		}
		'UTF32 Little-Endian' {
			# Read the content of the file using UTF-32 Little-Endian encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF32)
		}
		'UTF7' {
			# Read the content of the file using UTF-7 encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF7)
		}
		'UTF-1' {
			Write-Host "   UTF-1 encoding is not supported for conversion." -ForegroundColor Yellow
			Continue
		}
		'UTF-EBCDIC' {
			Write-Host "   UTF-EBCDIC encoding is not supported for conversion." -ForegroundColor Yellow
			Continue
		}
		'SCSU' {
			Write-Host "   SCSU encoding is not supported for conversion." -ForegroundColor Yellow
			Continue
		}
		'BOCU-1' {
			Write-Host "   BOCU-1 encoding is not supported for conversion." -ForegroundColor Yellow
			Continue
		}
		'GB-18030' {
			# Read the content of the file using GB-18030 encoding
			$content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::GetEncoding(54936)) # 54936 is the code page for GB-18030
		}
		default {
			Write-Host "   Unknown encoding for file $($file.FullName). Skipping." -ForegroundColor Yellow
			Continue
		}
	}
	# Write the content back to the file with UTF-8 encoding
	[System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.Encoding]::UTF8)
	Write-Host "   file $($file.Name) conversion from $($Encoding) to UTF8 complete." -ForegroundColor Green
}

Write-Host "Files have been converted to UTF-8 encoding."
