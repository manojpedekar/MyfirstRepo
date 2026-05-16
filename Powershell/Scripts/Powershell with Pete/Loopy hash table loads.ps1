<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.251
	 Created on:   	10/28/2025 2:03 PM
	 Created by:   	DT234083
	 Organization: 	SS&C
	 Filename:     	
	===========================================================================
	.DESCRIPTION
		Loopy hash table loads.  Which option is faster?

    .NOTES

    Option 1 - Adds unnecessary assignment
     - Creates unnecessary var $du

    Option 2 - Simpler, but pipeline adds overhead
     - More simple 

    Option 3 - In-memory loop, minimal overhead
     - Avoids ForEach-Object, which is slower due to pipeline mechanics.
     - Uses direct member access (.ForEach{}), which is executed in memory.
     - Cleaner syntax.
     - Requires PowerShell 4.0+ for array .ForEach() method (works in 5.1+ and PowerShell Core).

    Option 4 - No pipeline, direct memory iteration
     - Fastest in most benchmarks - avoids pipeline overhead entirely.
     - Native, memory-based iteration.
     - Readable and predictable.
     - Slightly more verbose, but ideal for speed and clarity.

    Hashtable Assignment vs .Add() Method

    Both Index Assignment and Add() method are valid hashtalbe assignment methods that have different performance behavior:

    | Aspect                | .Add()                                 | [$key] = $value                      |
    | --------------------- | -------------------------------------- | ------------------------------------ |
    | If key already exists | Throws an exception                    | Overwrites the existing value        |
    | Speed                 | Slightly slower (method call overhead) | Slightly faster (direct access)      |
    | Clarity               | Explicit "add new only" intent         | Common idiomatic PowerShell approach |
    | Use case              | When you need to ensure unique keys    | When updating or replacing is fine   |

    Why [$key] = $value Works (and is Common)

    PowerShell automatically calls the indexer on the underlying System.Collections.Hashtable object.
    If the key doesn't exist, it creates it.
    If it already exists, it updates it.


    Summary:
    Use Option 4 (foreach) when you want maximum efficiency.

    Use Option 3 (.ForEach{}) for concise, modern syntax.

    Avoid unnecessary variable assignment inside loops unless you need it for clarity or debugging.

#>

# Option 1
Measure-Command {
    [hashtable]$DomainUsers = @{ }
    Get-ADComputer -Filter { enabled -eq $true } -server wnpdcesscloud02.cloudad.ssncad.global | ForEach-Object {
        $du = $_
        $DomainUsers.Add($du.DistinguishedName, $du.SID)
    }
}

# Option 2
Measure-Command {
    [hashtable]$DomainUsers = @{ }
    Get-ADComputer -Filter { enabled -eq $true } -server wnpdcesscloud02.cloudad.ssncad.global | ForEach-Object {
        $DomainUsers.Add($_.DistinguishedName, $_.SID)
    }
}

# Option 3
Measure-Command {
    [hashtable]$DomainUsers = @{ }
    (Get-ADComputer -Filter { enabled -eq $true } -server wnpdcesscloud02.cloudad.ssncad.global).ForEach{
        $DomainUsers[$_.DistinguishedName] = $_.SID
    }
}

# Option 4
Measure-Command {
    [hashtable]$DomainUsers = @{ }
    ForEach ($du In (Get-ADComputer -Filter { enabled -eq $true } -server wnpdcesscloud02.cloudad.ssncad.global)) {
        $DomainUsers[$du.DistinguishedName] = $du.SID
    }
}











$myip = "10.102.5.65"

$myip.Split(".")




$mystring = "This is my test string"

$mystring.ToUpper().replace("MY", "a").Split(" ")


Function Test-IsIPAddress {
    Param (
        [Parameter(Mandatory)]
        [string]$InputString
    )
    
    Return [System.Net.IPAddress]::TryParse($InputString.Trim(), [ref]$null)
}



ForEach ($myip In $BigIPList) {
    
    switch ($variable) {
    	value1 {
    		#<code>
    	}
    	value2 {
    		#<code>
    	}
    	value3 {
    		#<code>
    	}
    	default {
    		#<code>
    	}
    }
    
    
    If (-not (Test-IsIPAddress $myip)) {
        write-error "$myip not an ip address"
        Continue
    }
    
    If (!(Test-IsIPAddress $myip)) {
        write-error "$myip not an ip address"
        Continue
    }
    
    If ((Test-IsIPAddress $myip) -eq $false) {
        write-error "$myip not an ip address"
        Continue
    }
    
    [int]$oct1, [string]$oct2, $oct3, $oct4 = $myip.Split(".")
    
    "$oct1 $oct2 $oct3 $oct4"
}



ForEach ($myip In $BigIPList) {
    
    If (Test-IsIPAddress $myip) {
        [int]$oct1, [string]$oct2, $oct3, $oct4 = $myip.Split(".")
        
        "$oct1 $oct2 $oct3 $oct4"
    }else{
        write-error "$myip not an ip address"
        Continue
    }
}

















