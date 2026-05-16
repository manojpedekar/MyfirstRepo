@echo off
cls

rem ####################################################
rem ## YOU MUST RUN THIS BATCH FILE AS ADMINISTRATOR ###
rem ####################################################

rem FILL IN THE BELOW THREE VARIABLES, REPLACING THE TEXT BETWEEN THE QUOTES
rem DO NOT PUT SPACES ON EITHER SIDE OF THE = SIGN

Set DESC=LegacyServer_and_DriveInfo_2_cloud REM modify description, thsi will update the log file name so be sure to use Servername and drive details for the log name
Set SOURCE=SourceDrivePath REM Modify SourceDrivePath to what is needed for the copy
Set DEST=DestinationDrivePath REM Modify DestinationDrivePath to what is needed for the copy
rem Set DEST=Y:

:copysync
For /f "tokens=2-4 delims=/ " %%a in ('date /t') do (set mydate=%%c%%a%%b)
For /f "tokens=1-2 delims=/: " %%a in ("%TIME%") do (if %%a LSS 10 (set mytime=0%%a%%b) else (set mytime=%%a%%b))

@echo.
@echo #####============================================================#####
@echo ##### STARTING Robo_%DESC% ON %DATE% at %TIME% 
@echo #####============================================================#####
@echo.

robocopy "%SOURCE%" "%DEST%" /MIR /S /E /COPYALL /XD "$RECYCLE.BIN" /R:0 /W:0 /LOG:%DESC%_%mydate%-%mytime%.log

@echo.
@echo #####=============================================================#####
@echo ##### COMPLETED Robo_%DESC% ON %DATE% at %TIME% 
@echo #####=============================================================#####
@echo.
@echo #################################
@echo ##### SLEEPING FOR 12 HOURS #####
@echo #####  hit CTRL-C to break  #####
@echo #################################
@echo.
@echo.

rem sleep 43200
rem goto copysync
@pause
