#!/bin/bash

# --- 1. INITIAL SETUP ---
BIN_DIR="/usr/local/bin"
CONF_FILE="$BIN_DIR/wgcf-profile.conf"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)." 
   exit 1
fi

echo "--- Starting Lean Deployment: AmneziaWG (amn0) to Cloudflare WARP ---"

# --- 2. INSTALL SYSTEM DEPENDENCIES ---
echo "Installing WireGuard, Docker-utils, and network tools..."
apt update && apt install -y wireguard-tools openresolv curl iptables sed jq cron

# --- 3. DOWNLOAD LATEST WGCF VERSION ---
echo "Fetching latest wgcf version from GitHub..."
LATEST_URL=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | jq -r '.assets[] | select(.name | contains("linux_amd64")) | .browser_download_url')
if [ -z "$LATEST_URL" ]; then
    LATEST_URL="https://github.com/ViRb3/wgcf/releases/download/v2.2.30/wgcf_2.2.30_linux_amd64"
fi
curl -fsSL "$LATEST_URL" -o $BIN_DIR/wgcf
chmod +x $BIN_DIR/wgcf

# Register WARP and generate profile
cd $BIN_DIR
./wgcf register --accept-tos
./wgcf generate

# --- 4. HARDEN CONFIGURATION (SSH SAFETY) ---
echo "Applying patches to wgcf-profile.conf..."
# Disable automatic routing to keep SSH alive
sed -i '/Address =/a Table = off' $CONF_FILE
sed -i 's/^DNS =/# DNS =/' $CONF_FILE
# Keep-alive prevents silent tunnel timeouts
if ! grep -q "PersistentKeepalive" $CONF_FILE; then
    sed -i '/Endpoint =/a PersistentKeepalive = 25' $CONF_FILE
fi

# --- 5. CREATE THE SMART TUNNEL SCRIPT ---
echo "Writing warp-tunnel.sh..."
cat << 'EOF' > /usr/local/bin/warp-tunnel.sh
#!/bin/bash
WARP_CONF="/usr/local/bin/wgcf-profile.conf"
WG_IF="wgcf-profile"
AMNEZIA_IF="amn0"

# --- SMART DETECTION LOGIC ---

# 1. Subnet Detection: Extracting from amn0
AMNEZIA_SUBNET=$(ip route show dev "$AMNEZIA_IF" | grep -v "default" | head -n 1 | awk '{print $1}')

# 2. Port Detection Method A: Docker Mappings
AMNEZIA_PORT=$(docker ps --format "{{.ID}}" 2>/dev/null | xargs -I {} docker container inspect {} \
    --format '{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}} {{$p}}{{end}}' \
    | grep "/udp" | awk '{print $1}' | head -n 1)

# Port Detection Method B: Fallback to System Sockets
if [ -z "$AMNEZIA_PORT" ]; then
    echo "Docker detection failed, trying system sockets..."
    AMNEZIA_PORT=$(ss -ulpn | grep -i "awg\|docker" | grep -oP '(?<=:)\d+(?=\s)' | head -n 1)
fi

cleanup() {
    echo "Shutting down and cleaning up..."
    # Always use full path for wg-quick down
    wg-quick down "$WARP_CONF" 2>/dev/null
    if ip link show "$WG_IF" >/dev/null 2>&1; then ip link delete dev "$WG_IF" 2>/dev/null; fi
    while ip rule del priority 90 2>/dev/null; do :; done
    while ip rule del priority 100 2>/dev/null; do :; done
    ip route flush table 51820 2>/dev/null
    iptables -t nat -D POSTROUTING -o "$WG_IF" -j MASQUERADE 2>/dev/null
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240 2>/dev/null
}

if [ "$1" == "stop" ]; then
    cleanup
    exit 0
fi

cleanup 
echo "Activating Cloudflare Tunnel..."
wg-quick up "$WARP_CONF"
ip route add default dev "$WG_IF" table 51820

# Apply loop-breaker for the detected Amnezia port only
if [ -n "$AMNEZIA_PORT" ]; then
    echo "Applying loop-breaker for port: $AMNEZIA_PORT"
    ip rule add ipproto udp sport $AMNEZIA_PORT priority 90 lookup main
    ip rule add ipproto udp dport $AMNEZIA_PORT priority 90 lookup main
fi

# Apply Routing Wrap (Priority 100)
if [ -n "$AMNEZIA_SUBNET" ]; then
    echo "Routing all traffic from $AMNEZIA_SUBNET through WARP"
    ip rule add from "$AMNEZIA_SUBNET" priority 100 lookup 51820
fi

# NAT and MTU Optimization
iptables -t nat -A POSTROUTING -o "$WG_IF" -j MASQUERADE
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1240
sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "WARP-Tunnel is LIVE."
EOF

chmod +x $BIN_DIR/warp-tunnel.sh

# --- 6. CREATE WATCHDOG (1-MINUTE INTERVAL) ---
cat << 'EOF' > $BIN_DIR/warp-watchdog.sh
#!/bin/bash
if ! ping -c 2 -W 5 -I wgcf-profile 1.1.1.1 > /dev/null 2>&1; then
    systemctl restart warp-tunnel
fi
EOF
chmod +x $BIN_DIR/warp-watchdog.sh

# --- 7. CREATE SYSTEMD SERVICE ---
cat << EOF > /etc/systemd/system/warp-tunnel.service
[Unit]
Description=Cloudflare WARP-over-Amnezia Tunnel
After=network.target network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN_DIR/warp-tunnel.sh
ExecStop=$BIN_DIR/warp-tunnel.sh stop
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# --- 8. FINALIZE ---
systemctl daemon-reload
systemctl enable warp-tunnel.service

# Schedule watchdog for every minute
(crontab -l 2>/dev/null | grep -v "warp-watchdog.sh"; echo "* * * * * $BIN_DIR/warp-watchdog.sh") | crontab -

echo "-------------------------------------------------------"
echo "DEPLOYMENT COMPLETE"
echo "To activate: systemctl start warp-tunnel"
echo "-------------------------------------------------------"