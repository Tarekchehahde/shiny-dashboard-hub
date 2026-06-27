# One-time setup on Windows: SSH key + config alias for passwordless root login.
# Run in PowerShell:  .\setup-ionos-ssh-key.ps1
# You will enter the IONOS root password once when the public key is copied.

$ErrorActionPreference = "Stop"

$VpsIp   = "82.165.167.86"
$VpsUser = "root"
$SshHost = "ionos-mastr"
$SshDir  = Join-Path $env:USERPROFILE ".ssh"
$Key     = Join-Path $SshDir "id_ed25519_ionos_mastr"
$Config  = Join-Path $SshDir "config"

if (-not (Test-Path $SshDir)) {
  New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
}

if (-not (Test-Path $Key)) {
  Write-Host "Creating SSH key: $Key"
  ssh-keygen -t ed25519 -f $Key -N '""' -C "ionos-mastr-windows"
} else {
  Write-Host "Key already exists: $Key"
}

$block = @"

# MaStR IONOS VPS — added by setup-ionos-ssh-key.ps1
Host $SshHost
  HostName $VpsIp
  User $VpsUser
  IdentityFile $Key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ServerAliveInterval 60
"@

if (-not (Test-Path $Config) -or -not (Select-String -Path $Config -Pattern "Host $SshHost" -Quiet)) {
  Add-Content -Path $Config -Value $block
  Write-Host "Added SSH config block for Host $SshHost"
} else {
  Write-Host "SSH config already contains Host $SshHost"
}

Write-Host ""
Write-Host "Copying public key to ${VpsUser}@${VpsIp} (enter VPS root password once)..."
$pub = Get-Content "${Key}.pub" -Raw
$pub | ssh "${VpsUser}@${VpsIp}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

Write-Host ""
Write-Host "Testing login..."
ssh -o BatchMode=yes $SshHost "echo OK: connected as $(whoami)@$(hostname)"

Write-Host ""
Write-Host "Setup complete. Double-click launch-ionos-ssh.bat or run launch-ionos-ssh.ps1"
