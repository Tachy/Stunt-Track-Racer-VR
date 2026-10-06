@echo off
rem VR version: headset on, its OpenXR runtime running.
rem Set GODOT to your Godot 4.7 executable if it lives elsewhere.
if not defined GODOT set "GODOT=D:\Eigene_Programme\Godot 4\Godot_v4.7.2-stable_win64.exe"
start "" "%GODOT%" --path "%~dp0."
