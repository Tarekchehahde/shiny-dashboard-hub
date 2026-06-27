#!/usr/bin/env bash
# Runs on the VPS after SSH login — quick infra summary, then interactive shell.

clear
cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║  IONOS MaStR VPS — infrastructure shell (root)               ║
╚══════════════════════════════════════════════════════════════╝
EOF

cpus=$(nproc 2>/dev/null || echo "?")
load=$(uptime | sed 's/.*load average: //')
mem=$(free -h 2>/dev/null | awk '/Mem:/ {printf "%s used / %s total · %s available", $3, $2, $7}')
disk=$(df -h / | awk 'NR==2 {print $3 " used / " $2 " (" $5 ")"}')

echo "Host:     $(hostname)  ·  ${cpus} vCPU"
echo "Uptime:   $(uptime -p 2>/dev/null || uptime | awk -F, '{print $1}')"
echo "Load:     ${load}  (≈ ${cpus} cores — sustained load > ${cpus} = saturated)"
echo "Memory:   ${mem}"
echo "Disk /:   ${disk}"
echo
echo "── Shiny / R memory (top RSS) ──"
ps aux --sort=-%mem 2>/dev/null | awk 'NR==1 || /mastr|shiny::runApp|rsession/ {printf "  %-8s %5s %5s %s\n", $1, $3"%", $4"%", $11}' | head -10
echo
echo "── Dashboard services ──"
systemctl list-units 'mastr-*' --no-legend 2>/dev/null | awk '{printf "  %-42s %s\n", $1, $3}' || true
echo
echo "── Monitor commands ──"
echo "  htop              interactive CPU + RAM (q to quit)"
echo "  free -h           memory snapshot"
echo "  df -h             disk all mounts"
echo "  vmstat 2 5        CPU / IO every 2s (5 samples)"
echo "  systemctl status mastr-most-visited"
echo "  journalctl -u mastr-deutschland-solar-radiation -f"
echo "  Netdata (via SSH tunnel): http://localhost:19999"
echo "      ssh -L 19999:127.0.0.1:19999 ionos-mastr"
echo
echo "Hub: http://82.165.167.86/  ·  exit to disconnect"
echo
exec bash -l
