function Show-DiagProblemPrompt {
    <#
    .SYNOPSIS
        Open a modal multi-line text prompt for an interactive operator.
    .DESCRIPTION
        Branches on the current PowerShell host's apartment state:
          - STA (pwsh 7+, ISE, powershell.exe -STA): renders the WinForms
            dialog in-process. Fast, no console flash, no temp files.
          - MTA (powershell.exe console default): spawns a child process
            with -STA so WinForms can render. The child writes its result
            to a temp file; the parent reads it back.

        The form is TopMost and BringToFront-activated so it appears in
        front of other windows. Cancel / Esc / X-button maps to a cancelled
        status. A 10-minute hard cap on the child path keeps a stuck form
        from deadlocking the bundle collection.

        Side effect of the in-process path: System.Windows.Forms and
        System.Drawing remain loaded in the calling PowerShell session for
        the rest of its lifetime (about 30 MB). This is harmless and
        eliminates the load cost on subsequent collections in the same
        session.
    .PARAMETER Prefill
        Initial textbox content. Empty string when there is no prefill.
    .INPUTS
        None.
    .OUTPUTS
        [hashtable] @{ status = 'ok' | 'cancelled'; text = <string> }
    .EXAMPLE
        Show-DiagProblemPrompt -Prefill 'patched 04-26, server stuck'
    .NOTES
        Caller is Resolve-DiagProblemDescription. The shared form code lives
        in _RenderDiagProblemForm below; the child script
        (Show-DiagProblemPrompt.Child.ps1) is a thin wrapper that calls the
        same helper after asserting -STA.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Prefill = ''
    )

    $apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
    if ($apt -eq 'STA') {
        return _RenderDiagProblemForm -Prefill $Prefill
    }

    # MTA fallback: spawn a child powershell.exe -STA process. The child
    # script loads the same helper (via the module loader) and calls it.
    $childScript = Join-Path $PSScriptRoot 'Show-DiagProblemPrompt.Child.ps1'
    if (-not (Test-Path -LiteralPath $childScript)) {
        throw "Child prompt script missing: $childScript"
    }

    $tmpRoot = [System.IO.Path]::GetTempPath()
    $stem    = 'diagprompt_' + ([guid]::NewGuid().ToString('N').Substring(0, 12))
    $inFile  = Join-Path $tmpRoot ($stem + '.in')
    $outFile = Join-Path $tmpRoot ($stem + '.out')
    $errFile = Join-Path $tmpRoot ($stem + '.err')

    try {
        [System.IO.File]::WriteAllText($inFile, $Prefill, [System.Text.UTF8Encoding]::new($false))

        $psExe = 'powershell.exe'
        try {
            $resolved = (Get-Command powershell.exe -ErrorAction Stop).Source
            if ($resolved) { $psExe = $resolved }
        } catch {
            $running = (Get-Process -Id $PID).Path
            if ($running -and (Test-Path -LiteralPath $running)) { $psExe = $running }
        }

        # Spawn with a normal console window. Two things matter for WinForms
        # to render reliably from a child process:
        #   1. Do NOT redirect stdin/stdout/stderr -- redirection prevents
        #      some GDI initialization paths used by WinForms.
        #   2. Do NOT use -WindowStyle Hidden -- on certain session types
        #      this detaches the child from the user's input desktop and the
        #      form, while created, never receives focus or paint events.
        # The child captures its own exceptions to the .err file via try/catch;
        # the parent reads that file when the child exits non-zero.
        $argList = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-STA'
            '-File', $childScript
            '-InputFile',  $inFile
            '-OutputFile', $outFile
            '-ErrorFile',  $errFile
        )
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -PassThru
        if (-not $proc.WaitForExit(600000)) {
            try { $proc.Kill() } catch { }
            throw 'Problem-prompt child timed out (10 minutes). Form may have failed to render.'
        }

        $errText = ''
        if (Test-Path -LiteralPath $errFile) {
            $errText = [System.IO.File]::ReadAllText($errFile, [System.Text.UTF8Encoding]::new($false))
        }

        if ($proc.ExitCode -ne 0) {
            $detail = if ($errText) { " details: $errText" } else { '' }
            throw "Problem-prompt child exited with code $($proc.ExitCode).$detail"
        }
        if (-not (Test-Path -LiteralPath $outFile)) {
            $detail = if ($errText) { " details: $errText" } else { '' }
            throw "Problem-prompt child did not write an output file.$detail"
        }

        $raw = [System.IO.File]::ReadAllText($outFile, [System.Text.UTF8Encoding]::new($false))
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj -or -not ($obj.PSObject.Properties.Name -contains 'status')) {
            throw 'Problem-prompt child output missing status field.'
        }
        return @{
            status = [string]$obj.status
            text   = if ($obj.PSObject.Properties.Name -contains 'text') { [string]$obj.text } else { '' }
        }
    }
    finally {
        Remove-Item -LiteralPath $inFile  -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
}

function _RenderDiagProblemForm {
    <#
    Render the problem-description WinForms dialog and return the result.
    Caller MUST be running in an STA apartment; this function does not
    re-check (the parent dispatcher decides the path). Loads
    System.Windows.Forms and System.Drawing on first call; subsequent calls
    in the same PS session reuse the loaded assemblies.

    Returns @{ status = 'ok' | 'cancelled'; text = <string> }.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Prefill = ''
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form              = New-Object System.Windows.Forms.Form
    $form.Text         = 'DiagBundle - Problem Description'
    $form.Size         = New-Object System.Drawing.Size(640, 460)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize  = New-Object System.Drawing.Size(480, 320)
    $form.TopMost      = $true
    $form.ShowInTaskbar = $true
    $form.KeyPreview   = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Describe the problem you are investigating. The text is stamped into manifest.collection.problem_description and ships with the bundle. Passwords / secrets / tokens are redacted automatically. Cap is 8 KB.'
    $label.Location = New-Object System.Drawing.Point(12, 10)
    $label.Size = New-Object System.Drawing.Size(600, 50)
    $label.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    $textbox = New-Object System.Windows.Forms.TextBox
    $textbox.Location  = New-Object System.Drawing.Point(12, 65)
    $textbox.Size      = New-Object System.Drawing.Size(600, 320)
    $textbox.Multiline = $true
    $textbox.WordWrap  = $true
    $textbox.ScrollBars = 'Vertical'
    $textbox.AcceptsTab = $true
    $textbox.AcceptsReturn = $true
    $textbox.Font = New-Object System.Drawing.Font('Consolas', 10)
    $textbox.Text = $Prefill
    $textbox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text     = 'OK (Ctrl+Enter)'
    $okButton.Size     = New-Object System.Drawing.Size(140, 28)
    $okButton.Location = New-Object System.Drawing.Point(330, 395)
    $okButton.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text     = 'Cancel (Esc)'
    $cancelButton.Size     = New-Object System.Drawing.Size(120, 28)
    $cancelButton.Location = New-Object System.Drawing.Point(485, 395)
    $cancelButton.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $textbox.Add_KeyDown({
        if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
            $_.SuppressKeyPress = $true
        }
    })

    $form.Controls.Add($label)
    $form.Controls.Add($textbox)
    $form.Controls.Add($okButton)
    $form.Controls.Add($cancelButton)

    $form.Add_Shown({
        $form.Activate()
        $form.BringToFront()
        $textbox.Focus() | Out-Null
        if ($textbox.Text.Length -gt 0) {
            $textbox.SelectionStart  = $textbox.Text.Length
            $textbox.SelectionLength = 0
        }
    })

    $result = $form.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return @{ status = 'ok';        text = [string]$textbox.Text }
    } else {
        return @{ status = 'cancelled'; text = '' }
    }
}
