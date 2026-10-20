@echo off
setlocal
cd /d "%~dp0"
set "APPDATA=%~dp0.runtime\AppData"
set "LOCALAPPDATA=%~dp0.runtime\LocalAppData"
set "TEMP=%~dp0.runtime\Temp"
set "TMP=%~dp0.runtime\Temp"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%TEMP%" mkdir "%TEMP%"
start "Godot - Mountain Mark" "D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0." --log-file "%~dp0.runtime\editor.log"
endlocal
