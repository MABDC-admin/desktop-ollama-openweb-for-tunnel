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
