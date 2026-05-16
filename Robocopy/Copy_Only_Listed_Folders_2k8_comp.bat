@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  copy_folder_structure.bat
::
::  Reads full source paths from folder_list.txt.
::  Strips the BASE_SOURCE prefix, takes only the FIRST
::  folder segment after it, and creates it on the Pure share.
::
::  Example:
::    Source:  E:\Data2\USIRKS\ARC Management Code Docs\Management Code
::    Creates: \\PureServer\Share\ARC Management Code Docs
:: ============================================================

:: --- CONFIGURATION ---
set "INPUT_FILE=folderlist.txt"
set "BASE_SOURCE=E:\Data2\USIRKS"
set "DEST_BASE=\\wdc-pure-fb-01-data-vif01.ssnc-corp.cloud\TABusTechShare"
set "LOG_FILE=copy_folder_log.txt"

:: --- INIT LOG ---
echo ============================================================ > "%LOG_FILE%"
echo  Folder Structure Copy Log >> "%LOG_FILE%"
echo  Started: %DATE% %TIME% >> "%LOG_FILE%"
echo  Base Source : %BASE_SOURCE% >> "%LOG_FILE%"
echo  Destination : %DEST_BASE% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

:: --- CHECK INPUT FILE EXISTS ---
if not exist "%INPUT_FILE%" (
    echo [ERROR] Input file not found: %INPUT_FILE%
    echo [ERROR] Input file not found: %INPUT_FILE% >> "%LOG_FILE%"
    goto :END
)

:: --- CHECK DESTINATION IS REACHABLE ---
if not exist "%DEST_BASE%\" (
    echo [ERROR] Destination share not reachable: %DEST_BASE%
    echo [ERROR] Destination share not reachable: %DEST_BASE% >> "%LOG_FILE%"
    goto :END
)

set "CREATED=0"
set "SKIPPED=0"
set "ERRORS=0"

:: Calculate length of BASE_SOURCE + trailing backslash
set "TEMP_STR=%BASE_SOURCE%\"
set "_S=!TEMP_STR!#"
set "BASE_LEN=0"
:STRLEN_LOOP
if "!_S:~0,1!"=="#" goto :STRLEN_DONE
set "_S=!_S:~1!"
set /A "BASE_LEN+=1"
goto STRLEN_LOOP
:STRLEN_DONE

:: --- PROCESS EACH LINE ---
for /F "usebackq tokens=* delims=" %%L in ("%INPUT_FILE%") do (
    set "FULL_PATH=%%L"

    :: Skip blank lines and comment lines
    if not "!FULL_PATH!"=="" (
        if not "!FULL_PATH:~0,1!"=="#" (

            :: Remove trailing backslash if present
            if "!FULL_PATH:~-1!"=="\" set "FULL_PATH=!FULL_PATH:~0,-1!"

            :: Strip the BASE_SOURCE\ prefix
            set "REL_PATH=!FULL_PATH:~%BASE_LEN%!"

            :: Extract only the first folder segment (before any backslash)
            for /F "tokens=1 delims=\" %%S in ("!REL_PATH!") do set "TOP_FOLDER=%%S"

            :: Skip if top folder is empty
            if not "!TOP_FOLDER!"=="" (
                set "DEST_PATH=%DEST_BASE%\!TOP_FOLDER!"

                if exist "!DEST_PATH!\" (
                    echo [SKIP]    !TOP_FOLDER!
                    echo [SKIP]    !DEST_PATH! >> "%LOG_FILE%"
                    set /A SKIPPED+=1
                ) else (
                    mkdir "!DEST_PATH!" 2>>"%LOG_FILE%"
                    if !ERRORLEVEL! EQU 0 (
                        echo [CREATED] !TOP_FOLDER!
                        echo [CREATED] !DEST_PATH! >> "%LOG_FILE%"
                        set /A CREATED+=1
                    ) else (
                        echo [ERROR]   Failed to create: !TOP_FOLDER!
                        echo [ERROR]   Failed to create: !DEST_PATH! >> "%LOG_FILE%"
                        set /A ERRORS+=1
                    )
                )
            )
        )
    )
)

:: --- SUMMARY ---
echo.
echo ============================================================
echo  Done.  Created: %CREATED%  Skipped: %SKIPPED%  Errors: %ERRORS%
echo  See %LOG_FILE% for details.
echo ============================================================

echo. >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"
echo  Done.  Created: %CREATED%  Skipped: %SKIPPED%  Errors: %ERRORS% >> "%LOG_FILE%"
echo  Finished: %DATE% %TIME% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

:END
endlocal
pause
