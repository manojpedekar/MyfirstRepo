function Resolve-DiagProblemDescription {
    <#
    .SYNOPSIS
        Resolve operator-supplied problem description from string / file / GUI prompt
        into the manifest.collection.problem_description block, or $null if none.
    .DESCRIPTION
        Single source of truth for input handling. The orchestrator passes its
        three optional parameters (-ProblemDescription, -ProblemDescriptionFile,
        -PromptForProblem) plus a user-interactive flag, and this function:
          - validates that ProblemDescription and ProblemDescriptionFile are
            not both supplied (parameter conflict);
          - rejects -PromptForProblem when the session is non-interactive
            (Salt/SYSTEM/service caller would otherwise hang waiting for a
            click that never comes);
          - reads the file when -ProblemDescriptionFile is supplied;
          - dispatches to Show-DiagProblemPrompt when -PromptForProblem is set,
            using the resolved string as the textbox prefill;
          - strips control characters except CR/LF/TAB;
          - truncates the final text to 8192 bytes (UTF-8) and records the
            original size in truncated_to_bytes when trimming occurred;
          - stamps operator_name (DOMAIN\\user) and supplied_at_utc.

        Returns $null when no input was supplied (the manifest field stays
        absent). Returns an [ordered] hashtable otherwise.
    .PARAMETER ProblemDescription
        Direct string from the -ProblemDescription parameter, or $null.
    .PARAMETER ProblemDescriptionFile
        Path passed to -ProblemDescriptionFile, or $null/empty.
    .PARAMETER PromptForProblem
        $true when -PromptForProblem switch is set.
    .PARAMETER UserInteractive
        Pass [System.Environment]::UserInteractive. Parameterised so tests
        can force the non-interactive path without spoofing the runtime.
    .PARAMETER PromptInvoker
        Optional scriptblock that takes a single -Prefill string parameter
        and returns @{ status='ok'|'cancelled'; text=<string> }. Defaults to
        Show-DiagProblemPrompt. Parameterised so tests can stub the GUI.
    .INPUTS
        None.
    .OUTPUTS
        [ordered] hashtable matching manifest.collection.problem_description, or $null.
    .EXAMPLE
        $pd = Resolve-DiagProblemDescription -ProblemDescription 'patched 04-26, server stuck' -UserInteractive $true
    .NOTES
        Cap is 8 KB UTF-8 bytes after control-char strip. Truncation preserves
        the leading bytes (operators put the headline first in chat-style
        descriptions). The UTF-8 byte count, not character count, is what
        actually drives manifest size, so the cap is enforced in bytes.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ProblemDescription,

        [Parameter()]
        [string] $ProblemDescriptionFile,

        [Parameter()]
        [bool] $PromptForProblem = $false,

        [Parameter(Mandatory)]
        [bool] $UserInteractive,

        [Parameter()]
        [scriptblock] $PromptInvoker
    )

    $hasString = -not [string]::IsNullOrEmpty($ProblemDescription)
    $hasFile   = -not [string]::IsNullOrWhiteSpace($ProblemDescriptionFile)

    if ($hasString -and $hasFile) {
        throw 'ProblemDescription and ProblemDescriptionFile are mutually exclusive. Pass exactly one.'
    }

    if ($PromptForProblem -and -not $UserInteractive) {
        throw '-PromptForProblem requires an interactive session. Use -ProblemDescription or -ProblemDescriptionFile in unattended contexts (Salt/SYSTEM/WinRM/SSM).'
    }

    $text          = $null
    $source        = $null
    $originalPath  = $null

    if ($hasFile) {
        if (-not (Test-Path -LiteralPath $ProblemDescriptionFile -PathType Leaf)) {
            throw "ProblemDescriptionFile not found or not a file: $ProblemDescriptionFile"
        }
        $fi = Get-Item -LiteralPath $ProblemDescriptionFile
        if ($fi.Length -gt 1MB) {
            throw "ProblemDescriptionFile exceeds 1MB (size=$($fi.Length)). Pre-trim the file."
        }
        try {
            $text = [System.IO.File]::ReadAllText($ProblemDescriptionFile, [System.Text.UTF8Encoding]::new($false))
        } catch {
            throw "Failed to read ProblemDescriptionFile '$ProblemDescriptionFile': $($_.Exception.Message)"
        }
        $source       = 'file'
        $originalPath = $fi.FullName
    } elseif ($hasString) {
        $text   = $ProblemDescription
        $source = 'parameter'
    }

    if ($PromptForProblem) {
        $invoker = if ($null -ne $PromptInvoker) { $PromptInvoker } else { { param($Prefill) Show-DiagProblemPrompt -Prefill $Prefill } }
        $prefillArg = if ($null -ne $text) { $text } else { '' }
        $r = & $invoker $prefillArg
        if ($null -eq $r -or -not $r.Contains('status')) {
            throw 'Problem-prompt invoker returned an unexpected result (missing status field).'
        }
        if ($r.status -eq 'cancelled') {
            $text   = ''
            $source = 'prompt_cancelled'
        } else {
            $text   = [string]$r.text
            $source = 'prompt'
        }
    }

    if ($null -eq $source) { return $null }

    # Strip control characters except CR (\r), LF (\n), and TAB (\t). Keeps
    # multi-line text intact while removing terminal escapes and other
    # noise pasted from console buffers.
    if ($null -ne $text -and $text.Length -gt 0) {
        $sb = New-Object System.Text.StringBuilder $text.Length
        foreach ($ch in $text.ToCharArray()) {
            $code = [int]$ch
            if ($code -eq 9 -or $code -eq 10 -or $code -eq 13 -or $code -ge 32) {
                [void]$sb.Append($ch)
            }
        }
        $text = $sb.ToString()
    }

    # Truncate at 8192 UTF-8 bytes. Slice carefully so we do not cut a
    # multi-byte UTF-8 sequence -- back off until we land on a valid boundary.
    $cap = 8192
    $truncatedTo = $null
    if ($null -ne $text -and $text.Length -gt 0) {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $bytes = $utf8.GetBytes($text)
        if ($bytes.Length -gt $cap) {
            $cut = $cap
            # Walk back if we land in the middle of a multi-byte sequence
            # (continuation bytes have the form 10xxxxxx -- 0x80..0xBF).
            while ($cut -gt 0 -and ($bytes[$cut] -band 0xC0) -eq 0x80) {
                $cut--
            }
            $truncatedTo = $bytes.Length
            $text = $utf8.GetString($bytes, 0, $cut)
        }
    }

    $operatorName = try {
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    } catch {
        $env:USERNAME
    }

    $fmt = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    $out = [ordered]@{
        text                = if ($null -eq $text) { '' } else { $text }
        source              = $source
        operator_name       = $operatorName
        supplied_at_utc     = (Get-Date).ToUniversalTime().ToString($fmt)
        truncated_to_bytes  = $truncatedTo
    }
    if ($null -ne $originalPath) {
        $out['original_path'] = $originalPath
    }
    return $out
}
