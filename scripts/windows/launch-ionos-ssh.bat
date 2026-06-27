@echo off
REM Double-click this file to open a root SSH session to the MaStR VPS.
REM One-time setup: run setup-ionos-ssh-key.ps1 in PowerShell first.

set SSH_HOST=ionos-mastr
set REMOTE=/opt/mastr-shiny/scripts/vps-infra-shell.sh

where ssh >nul 2>&1
if errorlevel 1 (
  echo OpenSSH client not found. Install it:
  echo   Settings - Apps - Optional features - OpenSSH Client
  pause
  exit /b 1
)

ssh -o BatchMode=yes -o ConnectTimeout=8 %SSH_HOST% echo ok >nul 2>&1
if errorlevel 1 (
  echo SSH key not configured.
  echo Run once in PowerShell:  setup-ionos-ssh-key.ps1
  pause
  exit /b 1
)

REM Prefer Windows Terminal if installed; otherwise default console
where wt >nul 2>&1
if not errorlevel 1 (
  wt ssh -t %SSH_HOST% "bash %REMOTE% 2>/dev/null || exec bash -l"
) else (
  ssh -t %SSH_HOST% "bash %REMOTE% 2>/dev/null || exec bash -l"
)
