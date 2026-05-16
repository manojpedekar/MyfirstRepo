function Invoke-DiagRedaction {
    <#
    .SYNOPSIS
        Mask password, secret, token, and apikey patterns in designated files.
    .DESCRIPTION
        Apply a conservative regex set against a small denylist of staged
        files and rewrite each match to [REDACTED]. Invoke-DiagBundle calls
        this after every collector has finished but before
        Complete-DiagManifest, so the final size and hash reflect the
        redacted content. Each pattern label that fired at least once is
        appended to manifest.redactions_applied.
    .PARAMETER Manifest
        The manifest hashtable. Mutated in place: each unique fired pattern
        label is appended to redactions_applied; per-file read or write
        failures land in collection_errors as warnings.
    .PARAMETER BundleRoot
        Absolute path to the staged bundle root. Candidate file paths
        resolve against it.
    .INPUTS
        None.
    .OUTPUTS
        None. Mutates the manifest hashtable and rewrites files in place.
    .EXAMPLE
        Invoke-DiagRedaction -Manifest $manifest -BundleRoot $workDir
    .NOTES
        Per locked decision #3 the regex set is intentionally narrow --
        password/passwd/pwd, api[_-]?key/apikey/token/secret/bearer,
        Authorization Bearer headers, and connection strings. Only four
        files are eligible: summary/processes.json, summary/services.json,
        summary/roles_apps.json, raw/registry/windowsupdate_policies.reg.
        Other artifacts are not scanned. Files that do not exist are skipped
        silently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Manifest,
        [Parameter(Mandatory)] [string] $BundleRoot
    )

    # Patterns: (regex, label). Patterns assume case-insensitive, single-line.
    $patterns = @(
        @{ Regex = '(?i)(password|passwd|pwd)\s*[:=]\s*"[^"]*"';                    Label = 'password_quoted' }
        @{ Regex = "(?i)(password|passwd|pwd)\s*[:=]\s*'[^']*'";                    Label = 'password_quoted' }
        @{ Regex = '(?i)(password|passwd|pwd)\s*[:=]\s*\S+';                        Label = 'password_kv' }
        @{ Regex = '(?i)\b(--?password|--?passwd|--?pwd|/password|/passwd|/pwd|-p)\s+\S+'; Label = 'password_arg' }
        @{ Regex = '(?i)(api[_-]?key|apikey|token|secret|bearer)\s*[:=]\s*"[^"]*"';  Label = 'secret_quoted' }
        @{ Regex = "(?i)(api[_-]?key|apikey|token|secret|bearer)\s*[:=]\s*'[^']*'";  Label = 'secret_quoted' }
        @{ Regex = '(?i)(api[_-]?key|apikey|token|secret|bearer)\s*[:=]\s*\S+';      Label = 'secret_kv' }
        @{ Regex = '(?i)Authorization\s*:\s*Bearer\s+\S+';                           Label = 'auth_bearer' }
        @{ Regex = '(?i)\b(server|data source)\s*=[^;]+;\s*(user\s*id|uid)\s*=[^;]+;\s*(password|pwd)\s*=[^;]+'; Label = 'connection_string' }
    )

    # Files eligible for redaction. Anything in summary/ that may contain command
    # lines or registry values, plus a few raw-side text artifacts we control.
    # Salt minion config files are added because operators sometimes inline
    # tokens or master_finger-style secrets in conf overrides; the standard
    # password/secret/token regex catches those.
    # The manifest's problem_description.text (in-memory at this point, not yet
    # on disk) is scrubbed in a second pass below using the same pattern set.
    $candidates = @(
        'summary/processes.json'
        'summary/services.json'
        'summary/roles_apps.json'
        'raw/registry/windowsupdate_policies.reg'
        'raw/salt/conf/minion'
        'raw/salt/conf/grains'
        'raw/salt/probes/grains_items.json'
        'raw/cloudbase_init/userdata.txt'
        'raw/cloudbase_init/log/cloudbase-init.log'
        'raw/cloudbase_init/log/cloudbase-init-unattend.log'
    )

    # Drop-in minion.d configs are dynamic; enumerate at run time.
    $minionD = Join-Path $BundleRoot 'raw\salt\conf\minion.d'
    if (Test-Path -LiteralPath $minionD) {
        foreach ($f in (Get-ChildItem -LiteralPath $minionD -Filter '*.conf' -File -ErrorAction SilentlyContinue)) {
            $candidates += "raw/salt/conf/minion.d/$($f.Name)"
        }
    }
    # Same for static grains.d drop-ins.
    $grainsD = Join-Path $BundleRoot 'raw\salt\conf\grains.d'
    if (Test-Path -LiteralPath $grainsD) {
        foreach ($f in (Get-ChildItem -LiteralPath $grainsD -File -ErrorAction SilentlyContinue)) {
            $candidates += "raw/salt/conf/grains.d/$($f.Name)"
        }
    }
    # Cloudbase-Init LocalScripts may contain inline credentials or
    # passing of secrets to downstream tools.
    $cbScripts = Join-Path $BundleRoot 'raw\cloudbase_init\LocalScripts'
    if (Test-Path -LiteralPath $cbScripts) {
        foreach ($f in (Get-ChildItem -LiteralPath $cbScripts -File -ErrorAction SilentlyContinue)) {
            $candidates += "raw/cloudbase_init/LocalScripts/$($f.Name)"
        }
    }

    $applied = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($rel in $candidates) {
        $full = Join-Path $BundleRoot ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $full)) { continue }

        try {
            $text = [System.IO.File]::ReadAllText($full)
            $orig = $text

            foreach ($p in $patterns) {
                $new = [regex]::Replace($text, $p.Regex, {
                    param($m)
                    $head = $m.Groups[1].Value
                    if ([string]::IsNullOrEmpty($head)) {
                        '[REDACTED]'
                    } else {
                        "$head=[REDACTED]"
                    }
                })
                if ($new -ne $text) {
                    [void]$applied.Add($p.Label)
                    $text = $new
                }
            }

            if ($text -ne $orig) {
                [System.IO.File]::WriteAllText($full, $text, [System.Text.UTF8Encoding]::new($false))
            }
        }
        catch {
            [void]$Manifest.collection_errors.Add(@{
                artifact  = $rel
                collector = 'Invoke-DiagRedaction'
                reason    = $_.Exception.Message
                severity  = 'warning'
            })
        }
    }

    # In-memory scrub: the operator-supplied problem_description.text is held
    # in the manifest at this point, not yet on disk. Apply the same pattern
    # set so the eventual manifest.json never contains plaintext secrets the
    # operator pasted into the prompt or description file. The value is
    # PSCustomObject (cast in the orchestrator to work around a PS 5.1
    # ConvertTo-Json bug); read its property via PSObject reflection so this
    # code is tolerant of either OrderedDictionary or PSCustomObject shape.
    $pd = $null
    if ($Manifest.collection.Contains('problem_description')) {
        $pd = $Manifest.collection['problem_description']
    }
    if ($null -ne $pd) {
        $textProp = $pd.PSObject.Properties['text']
        if ($null -ne $textProp -and -not [string]::IsNullOrEmpty([string]$textProp.Value)) {
            $pdText = [string]$textProp.Value
            $pdOrig = $pdText
            foreach ($p in $patterns) {
                $new = [regex]::Replace($pdText, $p.Regex, {
                    param($m)
                    $head = $m.Groups[1].Value
                    if ([string]::IsNullOrEmpty($head)) {
                        '[REDACTED]'
                    } else {
                        "$head=[REDACTED]"
                    }
                })
                if ($new -ne $pdText) {
                    [void]$applied.Add($p.Label)
                    $pdText = $new
                }
            }
            if ($pdText -ne $pdOrig) {
                $textProp.Value = $pdText
            }
        }
    }

    foreach ($label in $applied) {
        [void]$Manifest.redactions_applied.Add($label)
    }
}
