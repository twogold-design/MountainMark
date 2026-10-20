@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0build\MountainMark.exe" goto missing
if not exist "%~dp0build\MountainMark.pck" goto missing
if not exist "%~dp0build\engine\Godot.exe" goto missing
start "Mountain Mark" /D "%~dp0build" "%~dp0build\MountainMark.exe"
exit /b 0
:missing
echo Game files are missing. Please keep this batch file beside the complete build folder.
pause
exit /b 1
