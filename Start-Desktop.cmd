@echo off
rem Desktop version: OpenXR is not started at all.
rem Set GODOT to your Godot 4.7 executable if it lives elsewhere.
if not defined GODOT set "GODOT=D:\Eigene_Programme\Godot 4\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  echo Set GODOT to your Godot 4.7 executable, e.g.  set "GODOT=C:\Godot\Godot_v4.7.2-stable_win64.exe"
  pause
  exit /b 1
)
rem First start after a download: Godot builds its class cache (.godot\) once.
if not exist "%~dp0.godot\global_script_class_cache.cfg" (
  echo First start: preparing the project, this takes a moment ...
  "%GODOT%" --headless --xr-mode off --path "%~dp0." --import
)
start "" "%GODOT%" --xr-mode off --path "%~dp0." -- --no-xr
