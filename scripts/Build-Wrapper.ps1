$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Project = Join-Path $RepoRoot 'src\OpenWebUIWrapper\wrapper.csproj'
$OutputDir = Join-Path $RepoRoot 'outputs'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET SDK is required. Install .NET SDK 8, then rerun this script.'
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

dotnet publish $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $OutputDir

if ($LASTEXITCODE -ne 0) {
    throw 'dotnet publish failed.'
}

$Exe = Join-Path $OutputDir 'OpenWebUI.exe'
if (-not (Test-Path $Exe)) {
    throw "Expected output was not created: $Exe"
}

Write-Host "Built $Exe"
