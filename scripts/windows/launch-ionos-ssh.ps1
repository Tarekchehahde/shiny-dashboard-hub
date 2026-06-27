# Opens a root SSH session to the IONOS VPS (infra / ops walkthrough).
# Usage: double-click launch-ionos-ssh.bat, or run this script in PowerShell.

$ErrorActionPreference = "Stop"
$SshHost = "ionos-mastr"
$Remote  = "/opt/mastr-shiny/scripts/vps-infra-shell.sh"

try {
  ssh -o BatchMode=yes -o ConnectTimeout=8 $SshHost "echo ok" 2>$null | Out-Null
} catch {
  [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
  [System.Windows.Forms.MessageBox]::Show(
    "SSH key not configured.`n`nRun once in PowerShell:`n  .\setup-ionos-ssh-key.ps1",
    "IONOS VPS SSH",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Warning
  )
  exit 1
}

# -t allocates a TTY so the remote banner + interactive shell work
ssh -t $SshHost "bash $Remote 2>/dev/null || exec bash -l"
