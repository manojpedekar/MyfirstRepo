# =====================================================================
# Get_Disk_Volume_Mapping_2008R2.ps1
#
# Collects disk and volume details on Windows Server 2008 R2.
# Handles a mix of BASIC (simple) and DYNAMIC disks/volumes, and reports
# which physical disks each volume consumes and their sizes.
#
# Runs LOCALLY on each server, ELEVATED. PowerShell 2.0 compatible
# (Get-WmiObject + New-Object PSObject; no CIM / Storage module).
#
# Approach:
#   * diskpart "detail volume" gives the disk<->volume relationship for
#     BOTH basic (Partition) and dynamic (Spanned/Striped/Mirror/RAID-5)
#     volumes - WMI (Win32_LogicalDiskToPartition) cannot do dynamic.
#   * WMI (Win32_DiskDrive) supplies exact per-disk model/serial/size.
#   * WMI (Win32_Volume) supplies free space, incl. mounted-folder vols.
#
# diskpart tables are FIXED-WIDTH; we parse them by the column positions
# taken from the "----" separator line rather than by whitespace, so
# empty Ltr/Label/Fs fields and the separate Dyn/Gpt "*" columns are
# read correctly.
# =====================================================================

$ErrorActionPreference = "Stop"
$OutCsv = "C:\Temp\DiskVolumeMapping.csv"

# ---------------------------------------------------------------------
# Run a diskpart script, return its output as an array of lines.
# ---------------------------------------------------------------------
function Invoke-DiskPart([string]$script) {
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value $script -Encoding ASCII
    try {
        $out = & diskpart.exe /s $tmp 2>&1
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    return $out
}

# Safe fixed-width substring + trim.
function Get-Field([string]$line, [int]$start, [int]$end) {
    if ($null -eq $line -or $start -ge $line.Length) { return "" }
    if ($end -gt $line.Length) { $end = $line.Length }
    $len = $end - $start
    if ($len -le 0) { return "" }
    return $line.Substring($start, $len).Trim()
}

# From a diskpart table, return column ranges { Name, Start, End } derived
# from the "----" separator line, plus the separator's line index.
function Get-ColumnRanges($lines) {
    $sepIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*-{3,}') { $sepIdx = $i; break }
    }
    if ($sepIdx -lt 1) { return $null }

    $sep    = [string]$lines[$sepIdx]
    $header = [string]$lines[$sepIdx - 1]

    $runs = [regex]::Matches($sep, '-+')
    $ranges = @()
    for ($c = 0; $c -lt $runs.Count; $c++) {
        $start = $runs[$c].Index
        if ($c -lt $runs.Count - 1) { $end = $runs[$c + 1].Index } else { $end = [int]::MaxValue }
        $ranges += New-Object PSObject -Property @{
            Name  = (Get-Field $header $start $end)
            Start = $start
            End   = $end
        }
    }
    return New-Object PSObject -Property @{ Ranges = $ranges; SepIdx = $sepIdx }
}

# Pick a column range whose (trimmed) header matches a -like pattern.
function Find-Col($ranges, [string]$pattern) {
    foreach ($r in $ranges) { if ($r.Name -like $pattern) { return $r } }
    return $null
}

# "15 TB" / "4025 GB" / "100 MB" / "0 B"  ->  GB (double).
function ConvertTo-GB([string]$text) {
    $m = [regex]::Match($text, '(?i)([\d\.]+)\s*(TB|GB|MB|KB|B)')
    if (-not $m.Success) { return $null }
    $n = [double]$m.Groups[1].Value
    switch ($m.Groups[2].Value.ToUpper()) {
        "TB" { return [math]::Round($n * 1024, 2) }
        "GB" { return [math]::Round($n, 2) }
        "MB" { return [math]::Round($n / 1024, 2) }
        "KB" { return [math]::Round($n / 1024 / 1024, 2) }
        "B"  { return [math]::Round($n / 1GB, 2) }
    }
    return $null
}

# ---------------------------------------------------------------------
# 1. Physical disks from WMI. Win32_DiskDrive.Index == diskpart "Disk N".
# ---------------------------------------------------------------------
$diskByIndex = @{}
foreach ($d in Get-WmiObject Win32_DiskDrive) {
    $serial = $null
    if ($d.SerialNumber) { $serial = ($d.SerialNumber).Trim() }
    $diskByIndex[[int]$d.Index] = New-Object PSObject -Property @{
        Model  = $d.Model
        Serial = $serial
        SizeGB = [math]::Round($d.Size / 1GB, 2)
    }
}

# ---------------------------------------------------------------------
# 2. Free-space / capacity lookup from Win32_Volume, keyed by the volume
#    Name ("C:\", "E:\Data2\AWDSRVGRP\", ...). Covers mounted folders.
# ---------------------------------------------------------------------
$freeByName = @{}
foreach ($wv in Get-WmiObject Win32_Volume) {
    if ($wv.Name) {
        $freeByName[$wv.Name.ToUpper()] = New-Object PSObject -Property @{
            FreeGB = [math]::Round($wv.FreeSpace / 1GB, 2)
            CapGB  = [math]::Round($wv.Capacity  / 1GB, 2)
        }
    }
}

# ---------------------------------------------------------------------
# 3. list disk -> Basic vs Dynamic per disk number (the "Dyn" column).
# ---------------------------------------------------------------------
$dynamicDisk = @{}
$diskLines = Invoke-DiskPart "list disk"
$diskTbl   = Get-ColumnRanges $diskLines
if ($diskTbl) {
    $cDisk = Find-Col $diskTbl.Ranges "Disk*"
    $cDyn  = Find-Col $diskTbl.Ranges "Dyn*"
    for ($i = $diskTbl.SepIdx + 1; $i -lt $diskLines.Count; $i++) {
        $line = [string]$diskLines[$i]
        $f = Get-Field $line $cDisk.Start $cDisk.End      # e.g. "Disk 2" or "Disk M0"
        if ($f -notmatch '^Disk\s') { continue }
        $tok = ($f -split '\s+')[1]
        $isDyn = ((Get-Field $line $cDyn.Start $cDyn.End) -match '\*')
        if ($tok -match '^\d+$') { $dynamicDisk[[int]$tok] = $isDyn }
    }
}

# ---------------------------------------------------------------------
# 4. list volume -> one entry per volume, plus mounted-folder paths from
#    the indented continuation lines.
# ---------------------------------------------------------------------
$volLines = Invoke-DiskPart "list volume"
$volTbl   = Get-ColumnRanges $volLines
$volumes  = @()
if ($volTbl) {
    $cVol   = Find-Col $volTbl.Ranges "Volume*"
    $cLtr   = Find-Col $volTbl.Ranges "Ltr*"
    $cLabel = Find-Col $volTbl.Ranges "Label*"
    $cFs    = Find-Col $volTbl.Ranges "Fs*"
    $cType  = Find-Col $volTbl.Ranges "Type*"
    $cSize  = Find-Col $volTbl.Ranges "Size*"

    $last = $null
    for ($i = $volTbl.SepIdx + 1; $i -lt $volLines.Count; $i++) {
        $line = [string]$volLines[$i]
        $f = Get-Field $line $cVol.Start $cVol.End
        if ($f -match '^Volume\s+(\d+)') {
            $last = New-Object PSObject -Property @{
                VolNum    = [int]$matches[1]
                Letter    = (Get-Field $line $cLtr.Start   $cLtr.End)
                Label     = (Get-Field $line $cLabel.Start $cLabel.End)
                Fs        = (Get-Field $line $cFs.Start    $cFs.End)
                Type      = (Get-Field $line $cType.Start  $cType.End)
                SizeTxt   = (Get-Field $line $cSize.Start  $cSize.End)
                MountPath = ""
            }
            $volumes += $last
        }
        elseif ($null -ne $last -and $line -match '^\s+([A-Za-z]:\\.*)$') {
            # indented mount-folder path belongs to the volume just above
            $last.MountPath = $matches[1].Trim()
        }
    }
}

# ---------------------------------------------------------------------
# 5. detail volume per volume -> member disk numbers (basic & dynamic).
#    The output repeats the "list disk" table listing only the member(s).
# ---------------------------------------------------------------------
$results = @()
foreach ($v in $volumes) {

    $detail   = Invoke-DiskPart "select volume $($v.VolNum)`r`ndetail volume"
    $detailTbl = Get-ColumnRanges $detail

    $memberIdx = @()
    if ($detailTbl) {
        $cD = Find-Col $detailTbl.Ranges "Disk*"
        for ($i = $detailTbl.SepIdx + 1; $i -lt $detail.Count; $i++) {
            $line = [string]$detail[$i]
            $f = Get-Field $line $cD.Start $cD.End
            if ($f -notmatch '^Disk\s') { continue }
            $tok = ($f -split '\s+')[1]
            if ($tok -match '^\d+$') { $memberIdx += [int]$tok }
            else { $memberIdx += $tok }        # "M0" etc. (missing member)
        }
    }
    $memberIdx = $memberIdx | Select-Object -Unique
    if ($memberIdx.Count -eq 0) { $memberIdx = @($null) }

    # free space: match Win32_Volume by drive letter, else by mount path
    $freeGB = $null
    $key = $null
    if ($v.Letter)         { $key = ($v.Letter + ":\").ToUpper() }
    elseif ($v.MountPath)  { $key = $v.MountPath.ToUpper(); if ($key -notmatch '\\$') { $key += "\" } }
    if ($key -and $freeByName.ContainsKey($key)) { $freeGB = $freeByName[$key].FreeGB }

    foreach ($idx in $memberIdx) {
        $disk = $null
        $diskKind = "Unknown"
        $diskNum  = "N/A"

        if ($null -ne $idx) {
            $diskNum = $idx
            if ($idx -is [int]) {
                if ($diskByIndex.ContainsKey($idx)) { $disk = $diskByIndex[$idx] }
                if ($dynamicDisk.ContainsKey($idx)) {
                    if ($dynamicDisk[$idx]) { $diskKind = "Dynamic" } else { $diskKind = "Basic" }
                }
            } else {
                $diskKind = "Dynamic (Missing)"   # e.g. "M0"
            }
        }

        $row = New-Object PSObject
        $row | Add-Member NoteProperty Server        $env:COMPUTERNAME
        $row | Add-Member NoteProperty VolumeNum      $v.VolNum
        $row | Add-Member NoteProperty DriveLetter   $(if ($v.Letter) { "$($v.Letter):" } else { "" })
        $row | Add-Member NoteProperty VolumeLabel    $v.Label
        $row | Add-Member NoteProperty MountPath      $v.MountPath
        $row | Add-Member NoteProperty FileSystem     $v.Fs
        $row | Add-Member NoteProperty VolumeType     $v.Type          # Simple/Spanned/Striped/Mirror/RAID-5/Partition/DVD-ROM
        $row | Add-Member NoteProperty VolumeSize     $v.SizeTxt
        $row | Add-Member NoteProperty VolumeSizeGB   (ConvertTo-GB $v.SizeTxt)
        $row | Add-Member NoteProperty VolumeFreeGB   $freeGB
        $row | Add-Member NoteProperty DiskNumber     $diskNum
        $row | Add-Member NoteProperty DiskKind       $diskKind
        $row | Add-Member NoteProperty DiskModel     $(if ($disk) { $disk.Model } else { "" })
        $row | Add-Member NoteProperty DiskSerial     $(if ($disk) { $disk.Serial } else { "" })
        $row | Add-Member NoteProperty DiskSizeGB    $(if ($disk) { $disk.SizeGB } else { "" })
        $results += $row
    }
}

# ---------------------------------------------------------------------
# 6. Output.
# ---------------------------------------------------------------------
$cols = "Server","VolumeNum","DriveLetter","VolumeLabel","MountPath","FileSystem",
        "VolumeType","VolumeSize","VolumeSizeGB","VolumeFreeGB",
        "DiskNumber","DiskKind","DiskModel","DiskSerial","DiskSizeGB"

Write-Host "===== VOLUME -> DISK MAPPING =====" -ForegroundColor Cyan
$results | Select-Object $cols | Format-Table -AutoSize

if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" | Out-Null }
$results | Select-Object $cols | Export-Csv $OutCsv -NoTypeInformation

# ---------------------------------------------------------------------
# 7. Per-DISK rollup: which disk hosts how many / which volumes.
#    A disk becomes free after deleting a volume only if that disk hosts
#    exactly one volume (the one being deleted) -> FreesDiskIfVolDeleted.
# ---------------------------------------------------------------------
$OutDiskCsv = "C:\Temp\DiskUsageByDisk.csv"

# group volume-disk rows by real (numeric) disk; skip N/A rows.
$diskRows = @()
$byDisk = $results | Where-Object { $_.DiskNumber -is [int] } | Group-Object DiskNumber

foreach ($g in ($byDisk | Sort-Object { [int]$_.Name })) {

    # distinct volumes on this disk (a volume can appear once per member disk)
    $vols = $g.Group | Select-Object -Property VolumeNum,DriveLetter,VolumeLabel,VolumeType,VolumeSizeGB -Unique
    $volCount = ($vols | Measure-Object).Count

    $sample = $g.Group[0]
    $volList = ($vols | ForEach-Object {
        $tag = if ($_.DriveLetter) { $_.DriveLetter } elseif ($_.VolumeLabel) { $_.VolumeLabel } else { "Vol$($_.VolumeNum)" }
        "$tag($($_.VolumeType))"
    }) -join ", "

    $row = New-Object PSObject
    $row | Add-Member NoteProperty Server        $env:COMPUTERNAME
    $row | Add-Member NoteProperty DiskNumber     ([int]$g.Name)
    $row | Add-Member NoteProperty DiskKind       $sample.DiskKind
    $row | Add-Member NoteProperty DiskSizeGB     $sample.DiskSizeGB
    $row | Add-Member NoteProperty DiskModel      $sample.DiskModel
    $row | Add-Member NoteProperty DiskSerial     $sample.DiskSerial
    $row | Add-Member NoteProperty VolumeCount    $volCount
    $row | Add-Member NoteProperty Volumes        $volList
    # single-volume disk => deleting that volume frees the whole disk
    $row | Add-Member NoteProperty FreesDiskIfVolDeleted $(if ($volCount -eq 1) { "YES" } else { "no" })
    $diskRows += $row
}

$diskCols = "Server","DiskNumber","DiskKind","DiskSizeGB","DiskModel","DiskSerial",
            "VolumeCount","FreesDiskIfVolDeleted","Volumes"

Write-Host ""
Write-Host "===== DISK -> VOLUMES ROLLUP =====" -ForegroundColor Cyan
$diskRows | Select-Object $diskCols | Format-Table -AutoSize
$diskRows | Select-Object $diskCols | Export-Csv $OutDiskCsv -NoTypeInformation

Write-Host ""
Write-Host "Volume->Disk report : $OutCsv"
Write-Host "Disk->Volume report : $OutDiskCsv"
Write-Host ""
Write-Host "TIP: a disk shows FreesDiskIfVolDeleted=YES only when it hosts a"
Write-Host "single volume. To fully reclaim disks by deleting a spanned volume,"
Write-Host "ALL of that volume's member disks must each host only that volume."
