param(
    [string]$Distro = 'Ubuntu-24.04',
    [string]$ContainerName = 'open-webui',
    [string]$Model = 'qwen2.5:3b',
    [int]$Port = 8080,
    [switch]$Recreate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Wsl {
    param([Parameter(Mandatory)][string]$Command)
    wsl -d $Distro -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed: $Command"
    }
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
    } else {
        $parent = Split-Path -Parent $Path
        $leaf = Split-Path -Leaf $Path
        $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
        $resolved = Join-Path $resolvedParent $leaf
    }

    if ($resolved -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$relative"
    }

    throw "Unsupported path format for WSL conversion: $Path"
}

function Quote-Bash {
    param([Parameter(Mandatory)][string]$Value)
    "'" + ($Value -replace "'", "'\''") + "'"
}

function Copy-ToContainer {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $wslSource = ConvertTo-WslPath $Source
    Invoke-Wsl ("docker cp {0} {1}" -f (Quote-Bash $wslSource), (Quote-Bash "${ContainerName}:$Destination"))
}

function Update-IndexHtmlTheme {
    param(
        [Parameter(Mandatory)][string]$ThemeDir
    )

    $customCss = Get-Content -LiteralPath (Join-Path $ThemeDir 'custom.css') -Raw
    $loaderJs = Get-Content -LiteralPath (Join-Path $ThemeDir 'loader.js') -Raw
    $tempIndex = Join-Path ([System.IO.Path]::GetTempPath()) "openwebui-index-$PID.html"
    $wslTempIndex = ConvertTo-WslPath $tempIndex

    Invoke-Wsl ("docker cp {0} {1}" -f (Quote-Bash "${ContainerName}:/app/build/index.html"), (Quote-Bash $wslTempIndex))

    $index = [System.IO.File]::ReadAllText($tempIndex)
    $index = [regex]::Replace(
        $index,
        '<link rel="stylesheet" href="/static/custom\.css(?:\?v=[^"]*)?" crossorigin="use-credentials" />',
        '<link rel="stylesheet" href="/static/custom.css?v=login-theme-20260615" crossorigin="use-credentials" />'
    )

    $startMarker = '<!-- openwebui-login-theme:start -->'
    $endMarker = '<!-- openwebui-login-theme:end -->'
    $markedBlockPattern = "(?s)\s*$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))\s*"
    $legacyBlockPattern = "(?s)\s*<script>\s*\(\(\) => \{\s*'use strict';\s*const VIDEO_ID = 'openwebui-auth-background-video';.*?observer\.observe\(document\.documentElement, \{ childList: true, subtree: true \}\);\s*\}\)\(\);\s*</script>\s*"

    $index = [regex]::Replace($index, $markedBlockPattern, "`n")
    $index = [regex]::Replace($index, $legacyBlockPattern, "`n")

    $themeBlock = @"
$startMarker
<style>
$customCss
</style>
<script>
$loaderJs
</script>
$endMarker
"@

    $stylesheetTag = '<link rel="stylesheet" href="/static/custom.css?v=login-theme-20260615" crossorigin="use-credentials" />'
    if ($index -notlike "*$stylesheetTag*") {
        throw 'Could not find the Open WebUI custom stylesheet tag in index.html.'
    }

    $index = $index.Replace($stylesheetTag, "$stylesheetTag`n$themeBlock")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempIndex, $index, $utf8NoBom)

    Invoke-Wsl ("docker cp {0} {1}" -f (Quote-Bash $wslTempIndex), (Quote-Bash "${ContainerName}:/app/build/index.html"))
}

function Apply-LoginTheme {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $themeDir = Join-Path $repoRoot 'assets\login-theme'

    if (-not (Test-Path -LiteralPath $themeDir)) {
        return
    }

    Write-Host 'Applying login page video theme...'

    $customCss = Join-Path $themeDir 'custom.css'
    $loaderJs = Join-Path $themeDir 'loader.js'
    $video = Join-Path $themeDir 'turn_into_a_video_animation.mp4'

    Copy-ToContainer -Source $customCss -Destination '/app/build/static/custom.css'
    Copy-ToContainer -Source $customCss -Destination '/app/backend/open_webui/static/custom.css'
    Copy-ToContainer -Source $loaderJs -Destination '/app/build/static/loader.js'
    Copy-ToContainer -Source $loaderJs -Destination '/app/backend/open_webui/static/loader.js'
    Copy-ToContainer -Source $video -Destination '/app/build/static/turn_into_a_video_animation.mp4'
    Copy-ToContainer -Source $video -Destination '/app/backend/open_webui/static/turn_into_a_video_animation.mp4'
    Update-IndexHtmlTheme -ThemeDir $themeDir
}

if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    throw 'WSL is required but wsl.exe was not found.'
}

try {
    $ollama = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
    if ($ollama.StatusCode -ne 200) { throw "Unexpected Ollama status $($ollama.StatusCode)" }
} catch {
    throw 'Ollama is not reachable at http://127.0.0.1:11434. Start Ollama, then rerun this script.'
}

$tags = (& ollama list 2>$null | Out-String)
if ($tags -notmatch [regex]::Escape($Model)) {
    Write-Host "Pulling Ollama model $Model..."
    & ollama pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Failed to pull Ollama model $Model." }
}

Invoke-Wsl 'command -v docker >/dev/null'

$Gateway = (wsl -d $Distro -- bash -lc "ip route | sed -n 's/^default via \([^ ]*\).*/\1/p' | head -n1" | Out-String).Trim()
if (-not $Gateway) {
    throw 'Could not detect WSL default gateway.'
}

$OllamaBaseUrl = "http://${Gateway}:11434"
Write-Host "Using Ollama from container as $OllamaBaseUrl"

$existing = (wsl -d $Distro -- bash -lc "docker ps -a --format '{{.Names}}' | grep -Fx '$ContainerName' || true" | Out-String).Trim()
if ($existing -and $Recreate) {
    Invoke-Wsl "docker rm -f '$ContainerName' >/dev/null"
    $existing = ''
}

if (-not $existing) {
    $run = @"
docker run -d \
  --name '$ContainerName' \
  --restart always \
  -p $Port:8080 \
  -e OLLAMA_BASE_URL='$OllamaBaseUrl' \
  -e DEFAULT_MODELS='$Model' \
  -e DEFAULT_PINNED_MODELS='$Model' \
  -e TASK_MODEL='$Model' \
  -e TASK_MODEL_EXTERNAL='$Model' \
  -e WEBUI_NAME='Open WebUI Local' \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
"@
    Invoke-Wsl $run
} else {
    Invoke-Wsl "docker start '$ContainerName' >/dev/null"
}

Apply-LoginTheme

$deadline = (Get-Date).AddMinutes(4)
do {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
        if ($health.StatusCode -eq 200) {
            Write-Host "Open WebUI is healthy at http://127.0.0.1:$Port"
            exit 0
        }
    } catch {
        Write-Host 'Waiting for Open WebUI...'
    }
} while ((Get-Date) -lt $deadline)

throw "Open WebUI did not become healthy at http://127.0.0.1:$Port/health"
