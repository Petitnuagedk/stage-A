#!/bin/bash

# Ubuntu Server 22.04 - Ad-hoc Mesh Network Setup Script (OLSR)
# Compatible Raspberry Pi & x86
# Run with: sudo bash setup-mesh.sh [BOARD_ID]

set -e

# =========================
# Root check
# =========================
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root"
    exit 1
fi

# =========================
# Board ID
# =========================
if [ -z "$1" ]; then
    echo "ERROR: Board ID missing"
    exit 1
fi

BOARD_ID="$1"
BOARD_IP="10.0.0.$BOARD_ID"
USERNAME="${SUDO_USER:-root}"
HOME_DIR=$(eval echo "~$USERNAME")

echo "=========================================="
echo "Ubuntu 22.04 Mesh Network Setup"
echo "Board ID: $BOARD_ID"
echo "IP: $BOARD_IP"
echo "User: $USERNAME"
echo "=========================================="

# =========================
# Step 1: Dependencies (FIX)
# =========================
echo "[1/8] Installing dependencies..."
apt update
apt install -y \
    build-essential git flex bison \
    iw iproute2 net-tools \
    netcat-openbsd

systemctl enable systemd-networkd
systemctl start systemd-networkd

# =========================
# Step 2: Build OLSR
# =========================
echo "[2/8] Building OLSR..."
cd /tmp
rm -rf olsrd
git clone https://github.com/OLSR/olsrd.git
cd olsrd
make
make install

command -v olsrd >/dev/null || { echo "OLSR failed"; exit 1; }

# =========================
# Step 3: OLSR config
# =========================
echo "[3/8] Configuring OLSR..."

mkdir -p /etc/olsrd

cat > /etc/olsrd/olsrd.conf << 'EOF'
DebugLevel 1
IpVersion 4

LoadPlugin "olsrd_txtinfo.so.1.1"
{
    PlParam "port" "2006"
    PlParam "Accept" "0.0.0.0"
}

Interface "wlan0"
{
    Mode "mesh"
    HelloInterval 2.0
    TcInterval 5.0
}
EOF

# =========================
# Step 4: Netplan + IBSS (FIX)
# =========================
echo "[4/8] Configuring netplan and IBSS..."

# Générer le YAML Netplan valide
cat > /etc/netplan/99-mesh.yaml << EOF
network:
  version: 2
  renderer: networkd
  wifis:
    wlan0:
      dhcp4: no
      addresses:
        - \$BOARD_IP/24
      access-points: {}
      ssid: mesh-test
      optional: true
EOF

# Appliquer la configuration Netplan
netplan generate
netplan apply

# Passer wlan0 en mode IBSS (ad-hoc) avec canal 2412
ip link set wlan0 down
iw dev wlan0 set type ibss
ip link set wlan0 up
iw dev wlan0 ibss join mesh-test 2412

echo "[4/8] Netplan + IBSS configuration applied."

# =========================
# Step 5: Monitoring Script
# =========================
echo "[5/8] Creating monitoring script..."

cat > /usr/local/bin/mesh-test.sh << 'EOF'
#!/bin/bash

LOG_DIR="$HOME/mesh-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/mesh-$(date +%F-%H%M).log"

echo "Mesh test started $(date)" | tee -a "$LOG_FILE"

sleep 30

ip addr show wlan0 | tee -a "$LOG_FILE"
iw dev wlan0 info | tee -a "$LOG_FILE"

echo "Starting OLSR..." | tee -a "$LOG_FILE"
olsrd -f /etc/olsrd/olsrd.conf -i wlan0 &

sleep 45

MY_IP=$(ip -4 addr show wlan0 | grep inet | awk '{print $2}' | cut -d/ -f1)

for i in {1..40}; do
    echo "==== Check $i ====" | tee -a "$LOG_FILE"
    ip route | tee -a "$LOG_FILE"

    echo "/links" | nc -w2 127.0.0.1 2006 | tee -a "$LOG_FILE"
    echo "/topology" | nc -w2 127.0.0.1 2006 | tee -a "$LOG_FILE"

    for IP in 10.0.0.{1..4}; do
        [ "$IP" != "$MY_IP" ] && ping -c2 -W1 "$IP" | tee -a "$LOG_FILE"
    done

    sleep 15
done
EOF

chmod +x /usr/local/bin/mesh-test.sh
chown "$USERNAME:$USERNAME" /usr/local/bin/mesh-test.sh

# =========================
# Step 6: Systemd Service
# =========================
echo "[6/8] Creating systemd service..."

cat > /etc/systemd/system/mesh-adhoc.service << EOF
[Unit]
Description=Mesh Ad-hoc Setup
After=network.target

[Service]
ExecStart=/usr/local/bin/mesh-test.sh
User=$USERNAME
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mesh-adhoc.service

# =========================
# Step 7: Logs & ID
# =========================
echo "[7/8] Preparing logs..."

mkdir -p "$HOME/mesh-logs"
touch "$HOME/BOARD_$BOARD_ID"
chown -R "$USERNAME:$USERNAME" "$HOME/mesh-logs" "$HOME/BOARD_$BOARD_ID"

# =========================
# Step 8: Final
# =========================
echo "[8/8] Done"

echo "=========================================="
echo "SETUP COMPLETE"
echo "IP: $BOARD_IP"
echo "ESSID: mesh-test"
echo "Logs: $HOME/mesh-logs"
echo "=========================================="
echo "Reboot recommended"

