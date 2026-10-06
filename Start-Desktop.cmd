@echo off
rem Desktop version: OpenXR is not started at all.
rem Set GODOT to your Godot 4.7 executable if it lives elsewhere.
if not defined GODOT set "GODOT=D:\Eigene_Programme\Godot 4\Godot_v4.7.2-stable_win64.exe"
start "" "%GODOT%" --xr-mode off --path "%~dp0." -- --no-xr
