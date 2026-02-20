#!/bin/bash
# ============================================================
# Ubuntu Server 22.04 - Ad-hoc Mesh Network Setup Script
# Author: Adapted from Raspberry Pi Mesh Script
# Purpose: Configure wlan0 in ad-hoc mode, assign static IP,
#          install OLSR, and start it via systemd.
# Usage: sudo bash setup-mesh.sh <BOARD_ID>
# Example: sudo bash setup-mesh.sh 1
# ============================================================

set -euo pipefail  # Stop on any error

# -----------------------------
# 0. Vérification des droits root
# -----------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run this script as root (sudo)"
    exit 1
fi

# -----------------------------
# 1. Vérification des arguments
# -----------------------------
if [ -z "${1:-}" ]; then
    echo "ERROR: Please specify a BOARD_ID"
    echo "Usage: sudo bash setup-mesh.sh <BOARD_ID>"
    exit 1
fi

BOARD_ID="$1"
BOARD_IP="10.0.0.$BOARD_ID"
IFACE="wlan0"
MESH_SSID="mesh-test"
MESH_CHANNEL=6

echo "======================================"
echo "Mesh Network Setup - Board $BOARD_ID"
echo "IP Address: $BOARD_IP"
echo "Interface: $IFACE"
echo "ESSID: $MESH_SSID"
echo "======================================"

# -----------------------------
# 2. Installer les dépendances
# -----------------------------
echo "[1/6] Installing packages..."
apt update
apt install -y build-essential git iw iproute2 netcat-openbsd net-tools

# -----------------------------
# 3. Installer OLSR
# -----------------------------
echo "[2/6] Cloning and building OLSR..."
cd /tmp
rm -rf olsrd
git clone https://github.com/OLSR/olsrd.git
cd olsrd
make
make install

# Vérification installation OLSR
if ! command -v olsrd &>/dev/null; then
    echo "ERROR: OLSR installation failed!"
    exit 1
fi
echo "OLSR installed successfully: $(olsrd -v | head -n1)"

# -----------------------------
# 4. Créer la configuration OLSR
# -----------------------------
echo "[3/6] Creating OLSR configuration..."
mkdir -p /etc/olsrd
cat > /etc/olsrd/olsrd.conf <<EOF
DebugLevel 2
IpVersion 4

Interface "$IFACE"
{
    Mode "mesh"
}
EOF
echo "OLSR configuration created at /etc/olsrd/olsrd.conf"

# -----------------------------
# 5. Configurer l'interface Wi-Fi via Netplan
# -----------------------------
echo "[4/6] Configuring Netplan for ad-hoc Wi-Fi..."

cat > /etc/netplan/99-mesh.yaml <<EOF
network:
  version: 2
  renderer: networkd
  wifis:
    $IFACE:
      dhcp4: no
      addresses:
        - $BOARD_IP/24
      access-points:
        "$MESH_SSID":
          mode: ad-hoc
          channel: $MESH_CHANNEL
EOF

# Appliquer la configuration
netplan generate || { echo "ERROR: netplan generate failed"; exit 1; }
netplan apply || { echo "ERROR: netplan apply failed"; exit 1; }

# Vérifier l'interface
ip addr show "$IFACE" || { echo "ERROR: Interface $IFACE not found"; exit 1; }
ip route || echo "NOTE: Check routing table"

# -----------------------------
# 6. Créer le service systemd pour OLSR
# -----------------------------
echo "[5/6] Creating systemd service for OLSR..."

cat > /etc/systemd/system/olsrd.service <<EOF
[Unit]
Description=OLSR mesh routing daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/sbin/olsrd -f /etc/olsrd/olsrd.conf -i $IFACE
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable olsrd
systemctl restart olsrd

# Vérification OLSR
sleep 5
if ! systemctl is-active --quiet olsrd; then
    echo "ERROR: OLSR service failed to start"
    journalctl -u olsrd --no-pager | tail -n 20
    exit 1
fi

# -----------------------------
# 7. Test de connectivité locale
# -----------------------------
echo "[6/6] Testing connectivity..."
ping -c 3 "$BOARD_IP" || echo "WARNING: Ping to self failed"

echo "======================================"
echo "Setup completed successfully!"
echo "Board ID: $BOARD_ID"
echo "IP Address: $BOARD_IP"
echo "Interface: $IFACE"
echo "ESSID: $MESH_SSID"
echo "OLSR should be running: systemctl status olsrd"
echo "Logs: journalctl -u olsrd"
echo "======================================"
