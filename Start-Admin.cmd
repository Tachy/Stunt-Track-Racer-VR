@echo off
rem Admin: the track editor (desktop) that saves the official tracks back to
rem server/official - to tune them; commit the files afterwards.
rem The Godot executable comes only from start.cfg (copy start.cfg.example
rem to start.cfg and enter your path there; start.cfg is not in the repo).
setlocal
set "GODOT="
if not exist "%~dp0start.cfg" goto no_config
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0start.cfg") do if /i "%%a"=="GODOT" set "GODOT=%%b"
if not defined GODOT goto no_config
if not exist "%GODOT%" goto not_found
rem Is it really Godot? (an .exe with "godot" in its name that answers --version)
for %%f in ("%GODOT%") do (
  set "GODOT_NAME=%%~nxf"
  set "GODOT_EXT=%%~xf"
)
if /i not "%GODOT_EXT%"==".exe" goto not_godot
echo "%GODOT_NAME%" | findstr /i "godot" >nul || goto not_godot
set "GODOT_VERSION="
for /f "delims=" %%v in ('""%GODOT%" --version 2^>nul"') do if not defined GODOT_VERSION set "GODOT_VERSION=%%v"
if not defined GODOT_VERSION goto not_godot
rem Refresh Godot's class cache (.godot\) before every start: after a
rem download or a git pull new scripts would be unknown otherwise (~3 s).
echo Preparing the project ...
"%GODOT%" --headless --xr-mode off --path "%~dp0." --import >nul 2>&1
start "" "%GODOT%" --xr-mode off --path "%~dp0." -- --no-xr --admin --editor
exit /b 0

:no_config
echo No Godot executable configured.
echo Copy start.cfg.example to start.cfg and enter the path of your Godot 4.7 exe there.
set /p "_=Press Enter to close ..."
exit /b 1

:not_found
echo Godot not found: "%GODOT%"
echo Check the path in start.cfg.
set /p "_=Press Enter to close ..."
exit /b 1

:not_godot
echo This is not a Godot executable: "%GODOT%"
echo Check the path in start.cfg.
set /p "_=Press Enter to close ..."
exit /b 1
