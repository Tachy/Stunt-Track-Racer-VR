@echo off
rem VR version: headset on, its OpenXR runtime running.
rem Set GODOT to your Godot 4.7 executable if it lives elsewhere.
if not defined GODOT set "GODOT=D:\Eigene_Programme\Godot 4\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  echo Set GODOT to your Godot 4.7 executable, e.g.  set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64.exe"
  pause
  exit /b 1
)
rem Refresh Godot's class cache (.godot\) before every start: after a
rem download or a git pull new scripts would be unknown otherwise (~3 s).
echo Preparing the project ...
"%GODOT%" --headless --xr-mode off --path "%~dp0." --import >nul 2>&1
start "" "%GODOT%" --path "%~dp0."
