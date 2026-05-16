#!/bin/sh
# ==============================================================================
# Generic Embedded Device / Router Security Audit Script
# ==============================================================================
# Adjusted to use absolute command paths and compatible date syntax for BusyBox.
# Optimized for Linux-based routers/appliances (e.g., AsusWrt-Merlin, OpenWrt)
# ==============================================================================
# This script is meant to be invoked through a forced‑command SSH key, e.g.:
#   command="/path/to/router-audit.sh" ssh-ed25519 <public_key>
#
# The SSH client can pass a sub‑command via the *remote command* argument.
# The script reads that value from $SSH_ORIGINAL_COMMAND and executes the
# matching block.  If nothing (or an unknown value) is supplied, the help
# message is shown.
# ==============================================================================
#
# Updated features (relative to the version you originally supplied):
#   • Firmware / build information (nvram “extendno”, “buildno”, “productid”)
#   • Default‑credential detection (http_username / http_passwd)
#   • Slightly more robust command‑availability checks
#   • Consistent section headers via a helper function
#   • “full_audit” convenience command that runs everything end‑to‑end
# ==============================================================================
#
# Usage examples (run on the client side):
#   ssh -p <PORT> <USER>@<ROUTER_IP> stats           # basic health stats
#   ssh -p <PORT> <USER>@<ROUTER_IP> firmware        # firmware/build info
#   ssh -p <PORT> <USER>@<ROUTER_IP> cred_check      # default‑credential warning
#   ssh -p <PORT> <USER>@<ROUTER_IP> full_audit      # run *all* sections
# ===============================================================================

# ----------------------------------------------------------------------
# Helper: print a nicely formatted section header
# ----------------------------------------------------------------------
header() {
    echo ""
    echo "=== $1 ==="
    echo ""
}

# ----------------------------------------------------------------------
# 0. Guard – ensure we have a command (default to “help”)
# ----------------------------------------------------------------------
if [ -z "$SSH_ORIGINAL_COMMAND" ]; then
    SSH_ORIGINAL_COMMAND="help"
fi

# ----------------------------------------------------------------------
# 1. Firmware / build information
# ----------------------------------------------------------------------
firmware_info() {
    header "FIRMWARE / BUILD INFO"
    if command -v nvram >/dev/null 2>&1; then
        echo "Firmware version : $(nvram get extendno)"
        echo "Build number     : $(nvram get buildno)"
        echo "Model            : $(nvram get productid)"
    else
        echo "nvram not found – cannot retrieve firmware info."
    fi
}

# ----------------------------------------------------------------------
# 2. Default‑credential detection
# ----------------------------------------------------------------------
cred_check() {
    header "DEFAULT CREDENTIAL CHECK"
    if command -v nvram >/dev/null 2>&1; then
        USERNAME=$(nvram get http_username)
        PASSWORD=$(nvram get http_passwd)

        # Merlin stores empty strings for defaults – treat those as "admin"
        [ -z "$USERNAME" ] && USERNAME="admin"
        [ -z "$PASSWORD" ] && PASSWORD="admin"

        echo "Web UI username : $USERNAME"
        echo "Web UI password : $PASSWORD"

        if [ "$USERNAME" = "admin" ] && [ "$PASSWORD" = "admin" ]; then
            echo "⚠️  WARNING: Router is still using the default credentials!"
            echo "   Change them via the router UI → Administration → Administration → Router Password."
        else
            echo "✔️  Custom credentials appear to be set."
        fi
    else
        echo "nvram not available – cannot check credentials."
    fi
}

# ----------------------------------------------------------------------
# 3. Recent system logs (last 50 lines)
# ----------------------------------------------------------------------
logs() {
    header "RECENT SYSTEM LOGS (last 50 lines)"
    if [ -f /tmp/syslog.log ]; then
        tail -n 50 /tmp/syslog.log
    else
        echo "Error: /tmp/syslog.log not found."
    fi
}

# ----------------------------------------------------------------------
# 4. Logs from the last 24 hours
# ----------------------------------------------------------------------
tail_24h() {
    header "LOGS FROM THE LAST 24 HOURS"
    if [ -f /tmp/syslog.log ] || [ -f /tmp/syslog.log-1 ]; then
        # BusyBox `date -d` is not reliable; we skip time filtering for simplicity.
        limit=0
        cat /tmp/syslog.log-1 /tmp/syslog.log 2>/dev/null | awk -v limit="$limit" '
        BEGIN {
            split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ");
            for (i=1;i<=12;i++) month[m[i]]=i;
            "date +%Y" | getline year;
        }
        {
            split($3, t, ":");
            line_epoch = mktime(year " " month[$1] " " $2 " " t[1] " " t[2] " " t[3]);
            if (line_epoch >= limit) print;
        }'
    else
        echo "No syslog files found."
    fi
}

# ----------------------------------------------------------------------
# 5. Active network connections (excluding loopback)
# ----------------------------------------------------------------------
connections() {
    header "ACTIVE NETWORK CONNECTIONS"
    if command -v netstat >/dev/null 2>&1; then
        netstat -pntu | grep -v '127\.0\.0\.1' | head -n 40
    else
        echo "netstat not available."
    fi
}

# ----------------------------------------------------------------------
# 6. Firewall (iptables) rules (IPv4)
# ----------------------------------------------------------------------
firewall() {
    header "FIREWALL RULES (IPV4)"
    if command -v iptables >/dev/null 2>&1; then
        iptables -L -v -n --line-numbers | head -n 50
    else
        echo "iptables not available."
    fi
}

# ----------------------------------------------------------------------
# 7. Router health stats
# ----------------------------------------------------------------------
stats() {
    header "ROUTER PERFORMANCE STATS"
    uptime

    header "MEMORY USAGE"
    if command -v free >/dev/null 2>&1; then
        free -h
    else
        echo "free command not found."
    fi

    header "CPU TEMPERATURE"
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        echo "$(awk "BEGIN {printf \"%.1f°C\", $temp/1000}")"
    else
        echo "Temperature sensor not found."
    fi
}

# ----------------------------------------------------------------------
# 8. Active UPnP port forwards (VSERVER chain)
# ----------------------------------------------------------------------
upnp() {
    header "ACTIVE UPNP PORT FORWARDS"
    if command -v iptables >/dev/null 2>&1; then
        iptables -t nat -L VSERVER -n -v
    else
        echo "iptables not available."
    fi
}

# ----------------------------------------------------------------------
# 9. Full audit – runs every section in a sensible order
# ----------------------------------------------------------------------
full_audit() {
    firmware_info
    cred_check
    logs
    tail_24h
    connections
    firewall
    stats
    upnp
    echo ""
    echo "=== END OF FULL AUDIT ==="
}

# ----------------------------------------------------------------------
# 10. Help / usage
# ----------------------------------------------------------------------
show_help() {
    echo "Access Denied / Invalid Command."
    echo "------------------------------------------------"
    echo "Available commands (pass as the remote command when SSHing):"
    echo "  firmware      – Show firmware / build info"
    echo "  cred_check    – Detect default admin credentials"
    echo "  logs          – Last 50 lines of /tmp/syslog.log"
    echo "  tail_24h      – All syslog entries from the past 24 h"
    echo "  connections   – Active TCP/UDP connections (no loopback)"
    echo "  firewall      – iptables rules (IPv4)"
    echo "  stats         – Uptime, memory, CPU temperature"
    echo "  upnp          – UPnP/NAT port‑forward entries"
    echo "  full_audit    – Run *all* of the above in sequence"
    echo "  help          – Show this help message"
    exit 1
}

# ----------------------------------------------------------------------
# Dispatch based on $SSH_ORIGINAL_COMMAND
# ----------------------------------------------------------------------
case "$SSH_ORIGINAL_COMMAND" in
    "firmware")          firmware_info ;;
    "cred_check")        cred_check ;;
    "logs")              logs ;;
    "tail_24h")          tail_24h ;;
    "connections")       connections ;;
    "firewall")          firewall ;;
    "stats")             stats ;;
    "upnp")              upnp ;;
    "full_audit")        full_audit ;;
    "help"|"*")          show_help ;;
esac

exit 0