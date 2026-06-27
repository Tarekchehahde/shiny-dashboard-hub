@echo off
REM Opens Netdata on the IONOS VPS via SSH tunnel (http://localhost:19999/)

set SSH_HOST=ionos-mastr
set LOCAL_PORT=19999

where ssh >nul 2>&1
if errorlevel 1 (
  echo OpenSSH client not found. Install via Settings - Optional features - OpenSSH Client
  pause
  exit /b 1
)

ssh -o BatchMode=yes -o ConnectTimeout=8 %SSH_HOST% echo ok >nul 2>&1
if errorlevel 1 (
  echo SSH key not configured. Run setup-ionos-ssh-key.ps1 first.
  pause
  exit /b 1
)

REM Start background tunnel if not already running (Windows: new window minimized)
start /min cmd /c "ssh -N -L %LOCAL_PORT%:127.0.0.1:%LOCAL_PORT% %SSH_HOST%"

timeout /t 2 /nobreak >nul
start http://localhost:%LOCAL_PORT%/
