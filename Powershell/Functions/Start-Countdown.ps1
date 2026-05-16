Function Start-Countdown {
    <#
    .SYNOPSIS
    Displays a Write-Progress countdown for the specified number of minutes.

    .DESCRIPTION
    Useful as a "wait between API calls" or rate-limit pause where you want
    visible feedback rather than a silent Start-Sleep.

    .PARAMETER Minutes
    Duration of the countdown in minutes. Defaults to 5.

    .PARAMETER ProgressBarName
    Activity label shown in the progress bar. Defaults to "Countdown".

    .EXAMPLE
    Start-Countdown -Minutes 5 -ProgressBarName "Time before next API call"
    #>

    Param (
        [int]$Minutes = 5,
        [string]$ProgressBarName = "Countdown"
    )

    $totalSeconds = $Minutes * 60
    $originalSeconds = $totalSeconds

    While ($totalSeconds -gt 0) {
        $percentComplete = ($totalSeconds / $originalSeconds) * 100
        Write-Progress -Id 1 -Activity $ProgressBarName -Status "$totalSeconds seconds remaining" -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
        $totalSeconds--
    }

    Write-Progress -Id 1 -Activity $ProgressBarName -Completed
}
