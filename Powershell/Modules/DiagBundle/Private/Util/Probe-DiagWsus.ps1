function _ProbeDiagWsus {
    <#
    .SYNOPSIS
        Interrogate a WSUS server to confirm it actually responds as WSUS.

    .DESCRIPTION
        Issues a TCP connect (with measured RTT) followed by HTTP probes
        against the canonical WSUS *client* endpoints:
        ClientWebService/Client.asmx?WSDL (primary -- this is what WUA
        actually calls when it scans), and SelfUpdate/wuident.cab (HEAD,
        secondary confirmation). Validates the WSDL body against a
        signature pattern to distinguish a real WSUS server from any IIS
        instance answering on the same port.

        Earlier versions probed ServerSyncWebService and iuident.cab; both
        proved misleading because ServerSyncWebService is the WSUS-to-WSUS
        replica sync endpoint (often deliberately not exposed on leaf WSUS
        servers) and iuident.cab is not served on modern WSUS deployments.

        Used by Get-DiagPatching when wu_policy.wsus_server is configured.
        Never throws; returns a verdict object on failure.

    .PARAMETER BaseUrl
        WSUS server URL as configured in policy, e.g. http://wsus.foo:8530.

    .PARAMETER TimeoutSec
        Per-probe timeout in seconds. Default 15.

    .OUTPUTS
        OrderedDictionary with: url, tcp_ok, tcp_rtt_ms, cert_validation_skipped
        (https only), tests (array of per-test results), verdict.

    .NOTES
        Uses the system proxy (whatever WUA itself would use) -- the test
        mirrors real WUA behavior. For HTTPS WSUS with internal/self-signed
        certs, installs a temporary
        ServicePointManager.ServerCertificateValidationCallback that always
        returns $true; restores the original callback in a finally block.
        Cert bypass is recorded as cert_validation_skipped: true so the
        consumer knows the test did not validate the certificate chain.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $BaseUrl,
        [Parameter()] [int] $TimeoutSec = 15
    )

    $result = [ordered]@{
        url                     = $BaseUrl
        tcp_ok                  = $false
        tcp_rtt_ms              = -1
        cert_validation_skipped = $false
        tests                   = @()
        verdict                 = 'unknown'
    }

    $uri = $null
    try { $uri = [Uri]::new($BaseUrl) } catch {
        $result.verdict = 'invalid_url'
        $result.error = $_.Exception.Message
        return $result
    }

    # TCP probe with measured RTT.
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $task = $client.ConnectAsync($uri.Host, $uri.Port)
        if ($task.Wait([TimeSpan]::FromSeconds($TimeoutSec))) {
            $sw.Stop()
            $result.tcp_ok = [bool]$client.Connected
            $result.tcp_rtt_ms = [int]$sw.ElapsedMilliseconds
        } else {
            $sw.Stop()
            $result.tcp_rtt_ms = $TimeoutSec * 1000
        }
    } catch {
        $result.tcp_error = $_.Exception.Message
    } finally {
        if ($client) { $client.Close() }
    }

    if (-not $result.tcp_ok) {
        $result.verdict = 'tcp_blocked'
        return $result
    }

    # Cert callback shim for HTTPS WSUS (often self-signed internally).
    $oldCallback = $null
    if ($uri.Scheme -eq 'https') {
        $oldCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        $result.cert_validation_skipped = $true
    }

    $tests = New-Object System.Collections.ArrayList
    try {
        $base = $BaseUrl.TrimEnd('/')

        # Primary: the actual client-server WSUS endpoint. Match either WSDL
        # SOAP signature OR a "Client Web Service" body marker for cases where
        # IIS returns the friendly description page instead of the WSDL.
        $clientUrl = "$base/ClientWebService/Client.asmx?WSDL"
        $clientRes = _DoDiagHttpProbe -Name 'ClientWebService_wsdl' -Url $clientUrl -Method GET -TimeoutSec $TimeoutSec -SignaturePattern '<wsdl:definitions|<definitions|Client Web Service|WebServiceProxyHost|targetNamespace="http://www.microsoft.com/SoftwareDistribution"'
        [void]$tests.Add($clientRes)

        # Secondary: SelfUpdate path (used for WUA self-update). HEAD is fine.
        $selfUpdateUrl = "$base/SelfUpdate/wuident.cab"
        [void]$tests.Add((_DoDiagHttpProbe -Name 'selfupdate_wuident' -Url $selfUpdateUrl -Method HEAD -TimeoutSec $TimeoutSec))
    } finally {
        if ($uri.Scheme -eq 'https') {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $oldCallback
        }
    }

    $result.tests = @($tests)

    $clientOk = ($tests | Where-Object { $_['name'] -eq 'ClientWebService_wsdl' -and $_['signature_match'] }) | Select-Object -First 1
    $any200 = ($tests | Where-Object { $_['status'] -eq 200 }) | Select-Object -First 1
    if ($clientOk) {
        $result.verdict = 'wsus_responding'
    } elseif ($any200) {
        $result.verdict = 'http_ok_but_not_wsus'
    } else {
        $result.verdict = 'http_error'
    }

    return $result
}

function _DoDiagHttpProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Method,
        [Parameter()] [int] $TimeoutSec = 15,
        [Parameter()] [string] $SignaturePattern
    )

    $entry = [ordered]@{
        name   = $Name
        method = $Method
        url    = $Url
        ok     = $false
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method $Method -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        $sw.Stop()
        $entry.status     = [int]$resp.StatusCode
        $entry.rtt_ms     = [int]$sw.ElapsedMilliseconds
        $entry.body_bytes = if ($resp.RawContentLength) { [long]$resp.RawContentLength } else { 0 }
        $entry.server_header = "$($resp.Headers['Server'])"
        $entry.content_type  = "$($resp.Headers['Content-Type'])"
        if ($SignaturePattern) {
            $body = if ($resp.Content) { $resp.Content } else { '' }
            $entry.signature_match = ([string]$body -match $SignaturePattern)
        }
        $entry.ok = $true
    } catch {
        $sw.Stop()
        $entry.rtt_ms = [int]$sw.ElapsedMilliseconds
        $entry.error  = $_.Exception.Message
        if ($_.Exception.Response) {
            $entry.status = [int]$_.Exception.Response.StatusCode
        }
    }

    return $entry
}
