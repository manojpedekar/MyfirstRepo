@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM  Collect-ShareAccess.cmd
REM
REM  Snapshots files currently opened through this server's shares, recording
REM  the accessing user and the open mode (Read / Write / Read+Write).
REM  Designed for Windows Server 2003 (uses only native openfiles / wmic).
REM
REM  Schedule hourly, e.g.:
REM    schtasks /create /tn "ShareAccessSnapshot" /tr "\"C:\Scripts\Collect-ShareAccess.cmd\"" /sc hourly /ru SYSTEM /rl HIGHEST
REM ============================================================================

REM === Config: where logs are written ===
set "LOGDIR=C:\ShareAccessLogs"
set "MASTER=%LOGDIR%\OpenFiles_Master.csv"

if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM === Locale-independent timestamp (YYYYMMDDHHMMSS) via WMIC ===
set "LDT="
for /f "skip=1 delims=." %%A in ('wmic os get localdatetime 2^>nul') do (
    if not defined LDT set "LDT=%%A"
)
if not defined LDT set "LDT=00000000000000"
set "TS=%LDT:~0,4%-%LDT:~4,2%-%LDT:~6,2% %LDT:~8,2%:%LDT:~10,2%:%LDT:~12,2%"

REM === Per-run raw capture ===
set "RAW=%LOGDIR%\openfiles_%LDT:~0,14%.csv"
openfiles /query /fo csv /v > "%RAW%" 2>&1

REM === Write master header once ===
if not exist "%MASTER%" (
    echo "SnapshotTime","Hostname","ID","AccessedBy","Type","Locks","OpenMode","OpenFile" > "%MASTER%"
)

REM === Append each data row (skip openfiles' own header) prefixed with timestamp ===
for /f "skip=1 tokens=* delims=" %%L in ('type "%RAW%"') do (
    echo "%TS%",%%L >> "%MASTER%"
)

endlocal
