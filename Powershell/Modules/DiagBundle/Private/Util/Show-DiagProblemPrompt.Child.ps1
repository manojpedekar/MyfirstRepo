# Child script invoked via 'powershell.exe -STA -File' by Show-DiagProblemPrompt
# when the parent PS host is MTA. Reads the prefill from -InputFile, calls the
# shared _RenderDiagProblemForm helper (defined in Show-DiagProblemPrompt.ps1
# and dot-sourced here at module load time too), writes the JSON result to
# -OutputFile, captures any exception to -ErrorFile, and exits.
#
# IMPORTANT: this file is auto-discovered and dot-sourced by DiagBundle.psm1.
# The body therefore defines a function and only runs the form when invoked
# as a script with the expected parameters present in $args. Dot-sourcing
# produces no side effect beyond the function definition.

function Invoke-DiagProblemPromptChild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InputFile,
        [Parameter(Mandatory)] [string] $OutputFile,
        [Parameter()]          [string] $ErrorFile
    )

    function _WriteErr {
        param([string] $Text)
        if ($ErrorFile) {
            try {
                [System.IO.File]::AppendAllText($ErrorFile, $Text + "`r`n", [System.Text.UTF8Encoding]::new($false))
            } catch { }
        }
    }

    try {
        # Apartment-state assertion: this child is launched with -STA, so MTA
        # here means a packaging or invocation bug. Surface it immediately
        # rather than letting ShowDialog hang.
        $apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        if ($apt -ne 'STA') {
            _WriteErr "Child apartment state is $apt, expected STA. Re-launch powershell.exe with -STA."
            exit 2
        }

        $prefill = ''
        if (Test-Path -LiteralPath $InputFile) {
            try {
                $prefill = [System.IO.File]::ReadAllText($InputFile, [System.Text.UTF8Encoding]::new($false))
            } catch { $prefill = '' }
        }

        # The helper is defined in Show-DiagProblemPrompt.ps1, which lives
        # next to this file and is dot-sourced by the module loader on the
        # parent side. When this child script is invoked via -File, the
        # module is NOT loaded -- so dot-source the sibling script ourselves.
        $sibling = Join-Path $PSScriptRoot 'Show-DiagProblemPrompt.ps1'
        if (-not (Test-Path -LiteralPath $sibling)) {
            _WriteErr "Sibling script missing: $sibling"
            exit 4
        }
        . $sibling

        $payload = _RenderDiagProblemForm -Prefill $prefill

        $json = $payload | ConvertTo-Json -Compress
        [System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        _WriteErr ("Exception: " + $_.Exception.GetType().FullName + ": " + $_.Exception.Message + "`r`nStack:`r`n" + $_.ScriptStackTrace)
        exit 3
    }
}

# Run only when invoked as a script with the file parameters present in $args.
# When the module loader dot-sources this file, $MyInvocation.InvocationName
# is '.' and $args is empty, so the function is defined but not executed.
if ($MyInvocation.InvocationName -ne '.' -and $args.Count -gt 0) {
    $params = @{}
    for ($i = 0; $i -lt $args.Count - 1; $i++) {
        switch ($args[$i]) {
            '-InputFile'  { $params['InputFile']  = [string]$args[$i + 1] }
            '-OutputFile' { $params['OutputFile'] = [string]$args[$i + 1] }
            '-ErrorFile'  { $params['ErrorFile']  = [string]$args[$i + 1] }
        }
    }
    if ($params.ContainsKey('InputFile') -and $params.ContainsKey('OutputFile')) {
        Invoke-DiagProblemPromptChild @params
    }
}
