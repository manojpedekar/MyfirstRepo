@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM  Manage-ShareLegacy.cmd
REM
REM  One dependency-free tool for legacy Windows Server (2003 / 2008 / 2008 R2).
REM  Uses only native openfiles.exe, wmic, and dir -- NO PowerShell required, so
REM  it runs even on 2003 boxes where PowerShell was never installed.
REM
REM  Replaces three legacy scripts:
REM     Collect-ShareAccess.cmd              -> COLLECT mode
REM     Collect-ShareOpenFiles-2k8.ps1       -> COLLECT mode
REM     Windows_2k3_FolderOrShare_details.ps1-> DETAILS mode
REM
REM  MODES
REM    COLLECT   Snapshot the files currently opened through this server's shares
REM              (accessing user + open mode) and APPEND to a master CSV. Meant to
REM              run hourly via scheduled task; each run adds one timestamped batch.
REM    DETAILS   Report total size, file count and folder count for one path.
REM
REM  USAGE
REM    Manage-ShareLegacy.cmd COLLECT [logDir]
REM    Manage-ShareLegacy.cmd DETAILS <path> [outCsv]
REM
REM  EXAMPLES
REM    Manage-ShareLegacy.cmd COLLECT
REM    Manage-ShareLegacy.cmd COLLECT C:\temp\ShareUsageLogs
REM    Manage-ShareLegacy.cmd DETAILS "G:\Group_Windt132k\Shared\REIT Team\Rompsen"
REM
REM  SCHEDULE (COLLECT, hourly):
REM    schtasks /create /tn "ShareAccessSnapshot" ^
REM      /tr "\"C:\Scripts\Manage-ShareLegacy.cmd\" COLLECT" ^
REM      /sc hourly /ru SYSTEM /rl HIGHEST
REM
REM  OUTPUT SCHEMA (COLLECT master CSV):
REM    "SnapshotTime","Hostname","ID","AccessedBy","Type","Locks","OpenMode","OpenFile"
REM    This matches what Manage-ShareUsage_v2.ps1 -Action Analyze auto-detects
REM    (via the OpenMode column), so legacy-collected data feeds the modern analyzer.
REM
REM  LIMITATIONS
REM    * DETAILS parses the "dir /s" grand-total line; the thousands separator is
REM      locale-dependent (this handles the comma used by en-US). On other locales
REM      the byte total may not strip cleanly -- file/folder COUNTS are always exact.
REM    * openfiles lists files opened OVER THE NETWORK by default. Local-process
REM      opens require "openfiles /local on" + reboot (not needed for a file share).
REM ============================================================================

set "MODE=%~1"
if /i "%MODE%"=="COLLECT" goto :collect
if /i "%MODE%"=="DETAILS" goto :details

echo(
echo   Manage-ShareLegacy.cmd - legacy (2003/2008) share tool
echo(
echo   Usage:
echo     %~nx0 COLLECT [logDir]
echo     %~nx0 DETAILS ^<path^> [outCsv]
echo(
echo   Run with no valid mode shows this help.
endlocal
exit /b 1

REM --------------------------------------------------------------------------
:collect
REM --------------------------------------------------------------------------
set "LOGDIR=%~2"
if "%LOGDIR%"=="" set "LOGDIR=C:\temp\ShareUsageLogs"
set "MASTER=%LOGDIR%\OpenFiles_Master.csv"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM --- Locale-independent timestamp (YYYYMMDDHHMMSS) via WMIC ---
set "LDT="
for /f "skip=1 delims=." %%A in ('wmic os get localdatetime 2^>nul') do (
    if not defined LDT set "LDT=%%A"
)
if not defined LDT set "LDT=00000000000000"
set "TS=%LDT:~0,4%-%LDT:~4,2%-%LDT:~6,2% %LDT:~8,2%:%LDT:~10,2%:%LDT:~12,2%"

REM --- Per-run raw capture (kept for troubleshooting) ---
set "RAW=%LOGDIR%\openfiles_%LDT:~0,14%.csv"
openfiles /query /fo csv /v > "%RAW%" 2>&1

REM --- Write master header once ---
if not exist "%MASTER%" (
    echo "SnapshotTime","Hostname","ID","AccessedBy","Type","Locks","OpenMode","OpenFile"> "%MASTER%"
)

REM --- Append each data row (skip openfiles' own header), timestamp-prefixed ---
set "ROWS=0"
for /f "skip=1 tokens=* delims=" %%L in ('type "%RAW%"') do (
    echo "%TS%",%%L>> "%MASTER%"
    set /a ROWS+=1
)

echo %TS%: logged !ROWS! row(s) to "%MASTER%"
endlocal
exit /b 0

REM --------------------------------------------------------------------------
:details
REM --------------------------------------------------------------------------
set "TARGET=%~2"
set "OUTCSV=%~3"
if "%TARGET%"=="" (
    echo ERROR: DETAILS requires a path.  Usage: %~nx0 DETAILS ^<path^> [outCsv]
    endlocal
    exit /b 1
)
if not exist "%TARGET%" (
    echo ERROR: path not found: "%TARGET%"
    endlocal
    exit /b 1
)

REM --- File count: list files recursively (bare), count lines ---
set "FILES=0"
for /f %%C in ('dir /a-d /s /b "%TARGET%" 2^>nul ^| find /c /v ""') do set "FILES=%%C"

REM --- Folder count: list dirs recursively (bare), count lines ---
set "FOLDERS=0"
for /f %%C in ('dir /ad /s /b "%TARGET%" 2^>nul ^| find /c /v ""') do set "FOLDERS=%%C"

REM --- Total bytes: take the grand-total from dir /s (Windows does the big-number
REM     math, avoiding batch's 32-bit SET /A overflow on large trees). The last
REM     " File(s)" line is the grand total; token 3 is the byte figure. ---
set "BYTES="
for /f "tokens=3 delims= " %%A in ('dir /a-d /s "%TARGET%" 2^>nul ^| find /i " File(s)"') do set "BYTES=%%A"
if not defined BYTES set "BYTES=0"
REM Strip the en-US thousands separator so the number is machine-usable.
set "BYTES=%BYTES:,=%"

echo(
echo Path        : %TARGET%
echo Total Bytes : %BYTES%
echo File Count  : %FILES%
echo Folder Count: %FOLDERS%

if not "%OUTCSV%"=="" (
    for %%D in ("%OUTCSV%") do if not exist "%%~dpD" mkdir "%%~dpD"
    echo "Path","TotalBytes","FileCount","FolderCount"> "%OUTCSV%"
    echo "%TARGET%","%BYTES%","%FILES%","%FOLDERS%">> "%OUTCSV%"
    echo Saved to    : %OUTCSV%
)

endlocal
exit /b 0
