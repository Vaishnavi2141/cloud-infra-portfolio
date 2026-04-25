#!/usr/bin/env bash
# =============================================================================
# health_monitor.sh — Linux System Health Monitor
# Author : Your Name
# Version: 1.0.0
# Description: Collects CPU, memory, disk, network, and process metrics,
#              writes a timestamped report to a log file, and prints a
#              colour-coded summary to the terminal.
# Usage  : bash health_monitor.sh [--log /path/to/logfile] [--silent]
# =============================================================================

set -euo pipefail

# ── Configuration (override via environment or flags) ─────────────────────────
LOG_DIR="${LOG_DIR:-$HOME/health_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/health_$(date +%Y%m%d).log}"
REPORT_LINES=10          # top N processes to capture
DISK_WARN=80             # % usage that triggers a WARNING
DISK_CRIT=90             # % usage that triggers a CRITICAL alert
CPU_WARN=80              # % CPU that triggers a WARNING
MEM_WARN=85              # % RAM that triggers a WARNING
SILENT=false             # suppress terminal output when true

# ── Colour codes (disabled when not a terminal) ───────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "$*" | tee -a "$LOG_FILE"; }
info() { $SILENT || echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
warn() { $SILENT || echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
crit() { $SILENT || echo -e "${RED}${BOLD}[CRIT]${RESET}  $*"; }
ok()   { $SILENT || echo -e "${GREEN}${BOLD}[ OK ]${RESET}  $*"; }

hr()   { log "$(printf '%0.s─' {1..70})"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)    LOG_FILE="$2"; shift 2 ;;
    --silent) SILENT=true;   shift   ;;
    *)        echo "Unknown flag: $1"; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null || uptime)

# =============================================================================
# 1. HEADER
# =============================================================================
hr
log "  SYSTEM HEALTH REPORT — $TIMESTAMP"
log "  Host   : $HOSTNAME"
log "  Kernel : $KERNEL"
log "  Uptime : $UPTIME"
hr

info "Collecting metrics for ${HOSTNAME}..."
echo ""

# =============================================================================
# 2. CPU USAGE
# =============================================================================
log ""
log "── CPU ──────────────────────────────────────────────────────────────────"

# Use /proc/stat for a 1-second sample (works without mpstat)
get_cpu_usage() {
  local cpu1 cpu2
  cpu1=$(grep '^cpu ' /proc/stat)
  sleep 1
  cpu2=$(grep '^cpu ' /proc/stat)

  local idle1 total1 idle2 total2
  read -r _ user1 nice1 sys1 idle1 iowait1 irq1 softirq1 _ <<< "$cpu1"
  read -r _ user2 nice2 sys2 idle2 iowait2 irq2 softirq2 _ <<< "$cpu2"

  total1=$(( user1 + nice1 + sys1 + idle1 + iowait1 + irq1 + softirq1 ))
  total2=$(( user2 + nice2 + sys2 + idle2 + iowait2 + irq2 + softirq2 ))

  local dtotal=$(( total2 - total1 ))
  local didle=$(( idle2 - idle1 ))

  echo $(( (dtotal - didle) * 100 / dtotal ))
}

CPU_CORES=$(nproc)
CPU_USAGE=$(get_cpu_usage)
CPU_LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

log "  Cores        : $CPU_CORES"
log "  Usage (1s)   : ${CPU_USAGE}%"
log "  Load avg     : $CPU_LOAD  (1m / 5m / 15m)"

if (( CPU_USAGE >= CPU_WARN )); then
  warn "CPU usage is high: ${CPU_USAGE}%"
  log "  [WARN] CPU usage: ${CPU_USAGE}%"
else
  ok   "CPU usage: ${CPU_USAGE}%"
fi

# =============================================================================
# 3. MEMORY USAGE
# =============================================================================
log ""
log "── MEMORY ───────────────────────────────────────────────────────────────"

MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_FREE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_USED=$(( MEM_TOTAL - MEM_FREE ))
MEM_PCT=$(( MEM_USED * 100 / MEM_TOTAL ))

to_mb() { echo $(( $1 / 1024 )); }

log "  Total     : $(to_mb $MEM_TOTAL) MB"
log "  Used      : $(to_mb $MEM_USED) MB  (${MEM_PCT}%)"
log "  Available : $(to_mb $MEM_FREE) MB"

SWAP_TOTAL=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_FREE=$(grep SwapFree  /proc/meminfo | awk '{print $2}')
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
log "  Swap used : $(to_mb $SWAP_USED) MB / $(to_mb $SWAP_TOTAL) MB"

if (( MEM_PCT >= MEM_WARN )); then
  warn "Memory usage is high: ${MEM_PCT}%"
  log "  [WARN] Memory: ${MEM_PCT}%"
else
  ok   "Memory usage: ${MEM_PCT}%"
fi

# =============================================================================
# 4. DISK USAGE
# =============================================================================
log ""
log "── DISK ─────────────────────────────────────────────────────────────────"
log "  $(printf '%-20s %-8s %-8s %-8s %s' 'Filesystem' 'Size' 'Used' 'Avail' 'Use%')"

DISK_ALERT=false
while IFS= read -r line; do
  log "  $line"
  PCT=$(echo "$line" | awk '{gsub(/%/,""); print $5}')
  FS=$(echo "$line"  | awk '{print $1}')
  if (( PCT >= DISK_CRIT )); then
    crit "Disk CRITICAL on $FS: ${PCT}%"
    log "  [CRIT] Disk ${PCT}% on $FS"
    DISK_ALERT=true
  elif (( PCT >= DISK_WARN )); then
    warn "Disk WARNING on $FS: ${PCT}%"
    log "  [WARN] Disk ${PCT}% on $FS"
    DISK_ALERT=true
  fi
done < <(df -h --output=source,size,used,avail,pcent -x tmpfs -x devtmpfs -x squashfs 2>/dev/null \
         | tail -n +2 | awk '{printf "%-20s %-8s %-8s %-8s %s\n",$1,$2,$3,$4,$5}')

$DISK_ALERT || ok "All disk partitions within limits"

# =============================================================================
# 5. NETWORK INTERFACES
# =============================================================================
log ""
log "── NETWORK ──────────────────────────────────────────────────────────────"

# Snapshot RX/TX, wait 2s, recalculate bandwidth
net_stats() {
  local iface="$1"
  local rx_file="/sys/class/net/${iface}/statistics/rx_bytes"
  local tx_file="/sys/class/net/${iface}/statistics/tx_bytes"
  [[ -f $rx_file ]] || return
  local rx1=$(< "$rx_file") tx1=$(< "$tx_file")
  sleep 2
  local rx2=$(< "$rx_file") tx2=$(< "$tx_file")
  local rx_kbps=$(( (rx2 - rx1) / 2 / 1024 ))
  local tx_kbps=$(( (tx2 - tx1) / 2 / 1024 ))
  local ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  ip="${ip:-no IPv4}"
  log "  $iface  IP: $ip  RX: ${rx_kbps} KB/s  TX: ${tx_kbps} KB/s"
}

for iface in $(ls /sys/class/net/ | grep -v lo); do
  STATE=$(cat /sys/class/net/${iface}/operstate 2>/dev/null || echo unknown)
  if [[ "$STATE" == "up" ]]; then
    net_stats "$iface"
  else
    log "  $iface  [DOWN]"
  fi
done

# =============================================================================
# 6. TOP PROCESSES BY CPU
# =============================================================================
log ""
log "── TOP ${REPORT_LINES} PROCESSES (by CPU) ─────────────────────────────────────────────"
log "  $(printf '%-8s %-8s %-8s %s' 'PID' '%CPU' '%MEM' 'COMMAND')"

ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 {printf "  %-8s %-8s %-8s %s\n",$2,$3,$4,$11}' \
  | head -n "$REPORT_LINES" | tee -a "$LOG_FILE"

# =============================================================================
# 7. TOP PROCESSES BY MEMORY
# =============================================================================
log ""
log "── TOP ${REPORT_LINES} PROCESSES (by MEM) ─────────────────────────────────────────────"
log "  $(printf '%-8s %-8s %-8s %s' 'PID' '%CPU' '%MEM' 'COMMAND')"

ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 {printf "  %-8s %-8s %-8s %s\n",$2,$3,$4,$11}' \
  | head -n "$REPORT_LINES" | tee -a "$LOG_FILE"

# =============================================================================
# 8. SYSTEM SERVICES (common ones)
# =============================================================================
log ""
log "── KEY SERVICES ─────────────────────────────────────────────────────────"

SERVICES=(sshd nginx apache2 docker cron firewalld auditd)
for svc in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    ok   "$svc is running"
    log "  [ OK ] $svc — active"
  elif systemctl list-units --all 2>/dev/null | grep -q "$svc"; then
    warn "$svc is installed but NOT running"
    log "  [WARN] $svc — inactive"
  fi
  # silently skip services that don't exist on this machine
done

# =============================================================================
# 9. FAILED SYSTEMD UNITS
# =============================================================================
log ""
log "── FAILED SYSTEMD UNITS ─────────────────────────────────────────────────"

FAILED=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}')
if [[ -z "$FAILED" ]]; then
  ok "No failed systemd units"
  log "  [ OK ] No failed units"
else
  for unit in $FAILED; do
    crit "Failed unit: $unit"
    log "  [CRIT] Failed unit: $unit"
  done
fi

# =============================================================================
# 10. RECENT AUTH FAILURES (last 20 lines of auth log)
# =============================================================================
log ""
log "── RECENT AUTH FAILURES ─────────────────────────────────────────────────"

AUTH_LOG=""
for f in /var/log/auth.log /var/log/secure; do
  [[ -r "$f" ]] && AUTH_LOG="$f" && break
done

if [[ -n "$AUTH_LOG" ]]; then
  FAILURES=$(grep -i "failed\|invalid\|error" "$AUTH_LOG" 2>/dev/null | tail -20)
  if [[ -z "$FAILURES" ]]; then
    ok "No recent auth failures in $AUTH_LOG"
    log "  [ OK ] No recent auth failures"
  else
    warn "Recent auth issues detected — check $AUTH_LOG"
    echo "$FAILURES" | tail -5 | while IFS= read -r line; do
      log "  $line"
    done
  fi
else
  log "  Auth log not accessible (run as root for full data)"
fi

# =============================================================================
# 11. FOOTER
# =============================================================================
log ""
hr
log "  Report complete — $(date '+%Y-%m-%d %H:%M:%S')"
log "  Full log saved to: $LOG_FILE"
hr

echo ""
info "Done. Log written to: $LOG_FILE"



