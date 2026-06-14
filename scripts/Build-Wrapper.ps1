$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Project = Join-Path $RepoRoot 'src\OpenWebUIWrapper\wrapper.csproj'
$OutputDir = Join-Path $RepoRoot 'outputs'
$PublishDir = Join-Path $RepoRoot 'work\publish'
$ArtifactName = 'desktop-openwebui-ollama.exe'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET SDK is required. Install .NET SDK 8, then rerun this script.'
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (Test-Path $PublishDir) {
    Remove-Item -Recurse -Force -LiteralPath $PublishDir
}
New-Item -ItemType Directory -Force -Path $PublishDir | Out-Null

dotnet publish $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $PublishDir

if ($LASTEXITCODE -ne 0) {
    throw 'dotnet publish failed.'
}

$PublishedExe = Join-Path $PublishDir 'OpenWebUI.exe'
$Exe = Join-Path $OutputDir $ArtifactName
if (Test-Path $PublishedExe) {
    Copy-Item -Force -LiteralPath $PublishedExe -Destination $Exe
}

Remove-Item -Force -LiteralPath (Join-Path $OutputDir 'OpenWebUI.exe') -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath (Join-Path $OutputDir 'OpenWebUI.pdb') -ErrorAction SilentlyContinue

if (-not (Test-Path $Exe)) {
    throw "Expected output was not created: $Exe"
}

Write-Host "Built $Exe"
