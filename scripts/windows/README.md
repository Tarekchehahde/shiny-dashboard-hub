# Windows — IONOS VPS SSH shortcut

Use these files on your **work laptop (Windows)** to get the same root SSH session as the Mac **IONOS VPS Terminal** shortcut.

**VPS:** `82.165.167.86` · user `root` · alias `ionos-mastr`

The **dashboard hub** (http://82.165.167.86/) works in any browser on any laptop — no setup needed. SSH is per-machine (one-time key setup on each PC).

---

## Copy to the work laptop

Copy this entire folder to e.g.:

```
C:\Users\You\Tools\mastr-vps-ssh\
```

Or zip and email/Teams/OneDrive:

```powershell
# On Mac (from repo root)
zip -r mastr-vps-ssh-windows.zip scripts/windows/
```

---

## One-time setup (each Windows PC)

1. **OpenSSH Client** (usually already on Windows 10/11)  
   Settings → Apps → Optional features → **OpenSSH Client** → Install

2. **PowerShell** (Run as normal user, not admin required):

   ```powershell
   cd C:\Users\You\Tools\mastr-vps-ssh
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   .\setup-ionos-ssh-key.ps1
   ```

   Enter the **IONOS root password** once when prompted.

3. **Desktop shortcut** (optional):  
   Right-click `launch-ionos-ssh.bat` → Send to → Desktop (create shortcut)

---

## Daily use

- Double-click **`launch-ionos-ssh.bat`**, or  
- In PowerShell: `.\launch-ionos-ssh.ps1`

You get the infra banner (services, disk, hints) then an interactive root shell. Type `exit` to disconnect.

---

## Same key on Mac and Windows?

- **Recommended:** run `setup-ionos-ssh-key.ps1` on Windows — it creates a **second** key and adds it to the VPS. Both laptops work independently.
- **Alternative:** copy `~/.ssh/id_ed25519_ionos_mastr` (+ `.pub`) from Mac to `%USERPROFILE%\.ssh\` on Windows and add the same `Host ionos-mastr` block to `C:\Users\You\.ssh\config`. Less ideal (one key on two machines).

---

## Manual command (no scripts)

After setup:

```powershell
ssh -t ionos-mastr "bash /opt/mastr-shiny/scripts/vps-infra-shell.sh"
```

Or plain root login:

```powershell
ssh root@82.165.167.86
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `ssh is not recognized` | Install OpenSSH Client (see above) |
| Permission denied (publickey) | Run `setup-ionos-ssh-key.ps1` again |
| Corporate firewall blocks SSH | Ask IT to allow outbound **TCP 22** to `82.165.167.86` |
| Script execution disabled | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
