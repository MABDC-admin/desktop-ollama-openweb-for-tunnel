$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Exe = Join-Path $RepoRoot 'outputs\OpenWebUI.exe'

if (-not (Test-Path $Exe)) {
    throw "Missing $Exe. Run scripts\Build-Wrapper.ps1 first."
}

$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\app-it'
New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null

$LinkPath = Join-Path $StartMenuDir 'Open WebUI.lnk'
$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($LinkPath)
$Shortcut.TargetPath = $Exe
$Shortcut.WorkingDirectory = Split-Path -Parent $Exe
$Shortcut.Description = 'Open WebUI local desktop wrapper'
$Shortcut.IconLocation = "$Exe,0"
$Shortcut.Save()

Write-Host "Installed shortcut: $LinkPath"
