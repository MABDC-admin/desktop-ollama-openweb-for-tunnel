# Desktop Ollama OpenWeb Wrapper

Local Windows wrapper for Open WebUI backed by Ollama.

## What This Provides

- A self-contained Windows `OpenWebUI.exe` wrapper using WPF + WebView2.
- A WSL Docker startup script for Open WebUI on `http://127.0.0.1:8080`.
- Default Ollama model wiring for `qwen2.5:3b`.
- A minimalist login theme with a muted looping background video.
- A persistent default blueprint system prompt for the local default model.
- A Start Menu shortcut installer.

## Requirements

- Windows 11 or Windows 10 with WebView2 Evergreen Runtime.
- PowerShell 7 preferred, Windows PowerShell also works for the helper scripts.
- .NET SDK 8 to rebuild the wrapper.
- WSL Ubuntu with Docker available.
- Ollama running on Windows at `http://127.0.0.1:11434`.

## Start Open WebUI

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Start-OpenWebUI.ps1
```

Then open:

```text
http://127.0.0.1:8080
```

## Build The EXE

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Build-Wrapper.ps1
```

Output:

```text
outputs\desktop-openwebui-ollama.exe
```

## Install Start Menu Shortcut

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Shortcut.ps1
```

Shortcut:

```text
Start Menu > app-it > Open WebUI
```

## Current Defaults

- Open WebUI URL: `http://127.0.0.1:8080`
- Ollama URL from WSL container: detected from WSL default gateway, normally `http://172.x.x.1:11434`
- Default model: `qwen2.5:3b`
- Container name: `open-webui`
- Docker image: `ghcr.io/open-webui/open-webui:main`
- Login theme assets: `assets\login-theme`
- Default blueprint prompt: `assets\default-blueprint\prompt.md`

## Notes

The EXE is intentionally just a desktop shell around the local Open WebUI URL. It does not start Ollama or Docker by itself. Use `scripts\Start-OpenWebUI.ps1` to ensure the backend container is running, reapply the login theme assets, and restore the default blueprint prompt.
