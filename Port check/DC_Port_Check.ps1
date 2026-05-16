Import-Module ActiveDirectory

# ---------- State handling ----------
$StatePath = "$env:LOCALAPPDATA\DCConnectivityTest"
$StateFile = "$StatePath\lastdomain.txt" #Provide the list of DCs to test against. This is used to pre-populate the domain prompt on subsequent runs.

if (-not (Test-Path $StatePath)) {
    New-Item -ItemType Directory -Path $StatePath | Out-Null
}

$LastDomain = if (Test-Path $StateFile) {
    Get-Content $StateFile -ErrorAction SilentlyContinue
}

$Domain = Read-Host "Enter domain name [$LastDomain]"
if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = $LastDomain
}

if (-not $Domain) {
    Write-Error "No domain provided. Exiting."
    return
}

$Domain | Out-File $StateFile -Force

# ---------- Output file ----------
$Timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$OutputFile = Join-Path (Get-Location) "DC_RPC_Test_$($Domain)_$Timestamp.txt"

"Domain Controller Connectivity Test" | Out-File $OutputFile
"Domain   : $Domain"                  | Out-File $OutputFile -Append
"Date     : $(Get-Date)"               | Out-File $OutputFile -Append
"------------------------------------" | Out-File $OutputFile -Append

Write-Host "Results will be written to:" -ForegroundColor Cyan
Write-Host " $OutputFile" -ForegroundColor Yellow

# ---------- Enumerate DCs ----------
$DCs = Get-ADDomainController -Filter * -Server $Domain |
       Select-Object -ExpandProperty HostName

$Total   = $DCs.Count
$Counter = 0
$Results = @()

foreach ($DC in $DCs) {
    $Counter++
    Write-Progress `
        -Activity "Testing Domain Controllers" `
        -Status "Testing $DC ($Counter of $Total)" `
        -PercentComplete (($Counter / $Total) * 100)

    Write-Host "`n=== $DC ===" -ForegroundColor Yellow
    "=== $DC ===" | Out-File $OutputFile -Append

    # ---------- Port tests ----------
    $Ports = @{
        LDAP_389   = 389
        LDAPS_636  = 636
        GC_3268    = 3268
        GCSSL_3269 = 3269
        RPC_135    = 135
        ADWS_9389  = 9389
    }

    $PortResults = @{}
    foreach ($Name in $Ports.Keys) {
        $Test = Test-NetConnection $DC -Port $Ports[$Name] -WarningAction SilentlyContinue
        $Status = if ($Test.TcpTestSucceeded) { "OK" } else { "FAIL" }
        $PortResults[$Name] = $Test.TcpTestSucceeded

        Write-Host ("{0,-12}: {1}" -f $Name, $Status)
        ("{0,-12}: {1}" -f $Name, $Status) | Out-File $OutputFile -Append
    }

    # ---------- RPC dynamic ports ----------
    $RpcTests = @{
        RPC_Kerberos = "Kerberos"
        RPC_NTLM     = "NTLM"
    }

    $RpcResults = @{}

    foreach ($RpcName in $RpcTests.Keys) {
        Write-Host "$RpcName (dynamic RPC): " -NoNewline
        "$RpcName (dynamic RPC): " | Out-File $OutputFile -Append -NoNewline

        try {
            rpcping `
                -s $DC `
                -u $RpcTests[$RpcName] `
                -t ncacn_ip_tcp `
                -a connect `
                -I e3514235-4b06-11d1-ab04-00c04fc2dcd2 `
                -q 2 > $null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "OK"
                "OK" | Out-File $OutputFile -Append
                $RpcResults[$RpcName] = "OK"
            }
            else {
                Write-Host "FAIL"
                "FAIL" | Out-File $OutputFile -Append
                $RpcResults[$RpcName] = "FAIL"
            }
        }
        catch {
            Write-Host "ERROR"
            "ERROR" | Out-File $OutputFile -Append
            $RpcResults[$RpcName] = "ERROR"
        }
    }

    "" | Out-File $OutputFile -Append

    $Results += [PSCustomObject]@{
        DomainController = $DC
        LDAP_389         = $PortResults["LDAP_389"]
        LDAPS_636        = $PortResults["LDAPS_636"]
        GC_3268          = $PortResults["GC_3268"]
        GCSSL_3269       = $PortResults["GCSSL_3269"]
        RPC_135          = $PortResults["RPC_135"]
        ADWS_9389        = $PortResults["ADWS_9389"]
        RPC_Kerberos     = $RpcResults["RPC_Kerberos"]
        RPC_NTLM         = $RpcResults["RPC_NTLM"]
    }
}

Write-Progress -Activity "Testing Domain Controllers" -Completed

# ---------- Summary ----------
"Summary:" | Out-File $OutputFile -Append
$Results | Format-Table -AutoSize | Tee-Object -FilePath $OutputFile -Append

Write-Host "`nTesting complete." -ForegroundColor Green
Write-Host "Results saved to:" -ForegroundColor Cyan
Write-Host " $OutputFile" -ForegroundColor Yellow
