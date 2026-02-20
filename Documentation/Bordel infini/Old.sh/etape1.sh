#!/bin/bash

# Raspberry Pi - IBSS Mesh Network Setup Script (Bookworm compatible)
# Usage: sudo bash setup-mesh.sh [BOARD_ID]

set -e

### === ETAPE 0 : VERIFICATIONS ===
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root (sudo)"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: sudo bash setup-mesh.sh [BOARD_ID]"
    exit 1
fi

BOARD_ID="$1"
BOARD_IP="10.0.0.$BOARD_ID"

ESSID="mesh-test"
FREQ="2437"                     # Canal 6
BSSID="02:11:22:33:44:55"       # BSSID FORCÉ (CRITIQUE)

echo "=========================================="
echo " IBSS Mesh Setup"
echo " Board ID : $BOARD_ID"
echo " IP       : $BOARD_IP"
echo " ESSID    : $ESSID"
echo " BSSID    : $BSSID"
echo "=========================================="

### === ETAPE 1 : DEPENDANCES ===
echo "[1/8] Installing dependencies..."
apt update
apt install -y iw build-essential git netcat-openbsd iproute2

### === ETAPE 2 : INSTALLATION OLSR ===
echo "[2/8] Installing OLSR..."
cd /tmp
rm -rf olsrd
git clone https://github.com/OLSR/olsrd.git
cd olsrd
make
make install

command -v olsrd >/dev/null || { echo "OLSR install failed"; exit 1; }

### === ETAPE 3 : CONFIGURATION OLSR ===
echo "[3/8] Creating OLSR config..."
mkdir -p /etc/olsrd

cat > /etc/olsrd/olsrd.conf <<EOF
DebugLevel 1
IpVersion 4

LoadPlugin "olsrd_txtinfo.so.1.1"
{
    PlParam "port" "2006"
    PlParam "Accept" "127.0.0.1"
}

Interface "wlan0"
{
    HelloInterval 2.0
    TcInterval 5.0
}
EOF

### === ETAPE 4 : DESACTIVATION SERVICES CONFLICTUELS ===
echo "[4/8] Disabling conflicting network services..."
systemctl stop NetworkManager || true
systemctl disable NetworkManager || true
systemctl stop wpa_supplicant || true
systemctl disable wpa_supplicant || true
systemctl stop dhcpcd || true
systemctl disable dhcpcd || true

### === ETAPE 5 : CONFIGURATION IBSS (FORCÉE) ===
echo "[5/8] Configuring IBSS network..."

ip link set wlan0 down
iw dev wlan0 set type ibss
ip link set wlan0 up

# Création / jonction du réseau IBSS
iw dev wlan0 ibss join "$ESSID" "$FREQ" fixed-freq "$BSSID"

# IP statique
ip addr flush dev wlan0
ip addr add "$BOARD_IP/24" dev wlan0

### === ETAPE 6 : DEMARRAGE OLSR ===
echo "[6/8] Starting OLSR..."
pkill olsrd || true
olsrd -i wlan0 -d 1 &

### === ETAPE 7 : SCRIPT DE MONITORING (CONSERVÉ) ===
echo "[7/8] Installing monitoring script..."

cat > /usr/local/bin/mesh-monitor.sh <<'EOF'
#!/bin/bash
LOG="/var/log/mesh-monitor.log"
echo "=== Mesh monitor started $(date) ===" >> $LOG

while true; do
    echo "--- $(date) ---" >> $LOG
    iw dev wlan0 link >> $LOG 2>&1
    ip route >> $LOG
    sleep 30
done
EOF

chmod +x /usr/local/bin/mesh-monitor.sh
/usr/local/bin/mesh-monitor.sh &

### === ETAPE 8 : SERVICE SYSTEMD ===
echo "[8/8] Installing systemd service..."

cat > /etc/systemd/system/mesh-ibss.service <<EOF
[Unit]
Description=IBSS Mesh Network
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-mesh.sh $BOARD_ID
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mesh-ibss.service

echo "=========================================="
echo " IBSS Mesh setup COMPLETE"
echo " Reboot recommended"
echo "=========================================="

