param([string]$Godot = 'D:\tools\Godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$runtimeRoot = Join-Path $projectRoot '.runtime'
$env:APPDATA = Join-Path $runtimeRoot 'AppData'
$env:LOCALAPPDATA = Join-Path $runtimeRoot 'LocalAppData'
$env:TEMP = Join-Path $runtimeRoot 'Temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$env:TEMP,(Join-Path $projectRoot 'build\engine') | Out-Null
& $Godot --headless --path $projectRoot --editor --import --quit --log-file (Join-Path $projectRoot 'qa\build-import.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
& $Godot --headless --path $projectRoot --export-pack 'Windows Desktop' (Join-Path $projectRoot 'build\MountainMark.pck') --log-file (Join-Path $projectRoot 'qa\export-final.log')
if ($LASTEXITCODE -ne 0) { throw 'Godot pack export failed.' }
$runtimeExe = $Godot.Replace('_console.exe','.exe')
Copy-Item -LiteralPath $runtimeExe -Destination (Join-Path $projectRoot 'build\engine\Godot.exe')
& (Join-Path $PSScriptRoot 'make_icon.ps1')
$csharpCompiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csharpCompiler /nologo /target:winexe /reference:System.Windows.Forms.dll /win32icon:assets\icon.ico /out:build\MountainMark.exe tools\launcher.cs
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
Write-Output 'Build ready: build\MountainMark.exe'
