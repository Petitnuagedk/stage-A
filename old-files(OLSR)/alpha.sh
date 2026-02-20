#!/bin/bash
set -e

############################################
# Raspberry Pi Zero W – Mesh IBSS (Bookworm)
# Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]
############################################

### --- Sécurité ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Lancer ce script avec sudo"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]"
  exit 1
fi

BOARD_ID="$1"
IP="10.0.0.$BOARD_ID"
ESSID="mesh-test"
CHANNEL_FREQ="2437"   # canal 6
MAC_SUFFIX=$(printf "%02x" "$BOARD_ID")

echo "========================================="
echo " Mesh Bookworm – Node $BOARD_ID ($IP)"
echo "========================================="

############################################
# [1/11] Paquets requis
############################################
echo "[1/11] Installation des dépendances..."

if [ -f /etc/apt/apt.conf.d/95proxy ]; then
    rm /etc/apt/apt.conf.d/95proxy
fi

cp 95proxy /etc/apt/apt.conf.d/

date -s "29 JAN 2026 16:45:00"

apt update

apt install -y \
  iw iproute2 netcat-openbsd \
  build-essential \
  git \
  cmake \
  pkg-config \
  bison \
  flex \
  libnl-3-dev \
  libnl-genl-3-dev \
  libconfig-dev \
  libprotobuf-c-dev \
  protobuf-c-compiler \
  systemd \
  nmap \
  arp-scan

############################################
# [2/11] Désactivation NetworkManager / WPA
############################################
echo "[2/11] Désactivation services conflictuels..."
systemctl disable --now NetworkManager 2>/dev/null || true
systemctl disable --now wpa_supplicant 2>/dev/null || true

############################################
# [3/11] Activation systemd-networkd
############################################
echo "[3/11] Activation systemd-networkd..."
systemctl enable systemd-networkd
systemctl start systemd-networkd

############################################
# [4/11] Configuration réseau wlan0 safe
############################################
echo "[4/11] Configuration réseau wlan0 safe..."

cat > /etc/systemd/network/10-mesh.network <<EOF
[Match]
Name=wlan0

[Network]
LinkLocalAddressing=no
EOF

systemctl restart systemd-networkd
echo "✅ wlan0 networkd config appliquée (LinkLocalAddressing désactivé)"

############################################
# [5/11] Compilation et installation OLSRv2
############################################

echo "[5/11] Compilation OLSRv2 (OONF)..."

# Déplacement des sources
mv OONF /tmp
cd /tmp/OONF || { echo "❌ /tmp/OONF introuvable"; exit 1; }

# Build out-of-source
mkdir -p build
cd build

echo "⚙️  Configuration CMake..."
cmake .. 

echo "🔨 Compilation..."
make 

echo "📦 Installation..."
make install
ldconfig

echo "✅ OLSRv2 (OONF) installé"

############################################
# [6/11] Configuration OLSRv2
############################################

echo "[6/11] Configuration OLSRv2..."

mkdir -p /etc/olsrd2

cat > /etc/olsrd2/olsrd2.conf <<EOF
[olsrd]
debug_level = 1

[interfaces]
wlan0 = {
    type = mesh
    hello_interval = 2.0
    tc_interval = 5.0
}

[plugins]
txtinfo = {
    port = 2006
    accept = 0.0.0.0
}
EOF

echo "✅ Configuration OLSRv2 prête"

############################################
# [7/11] Script IBSS – robuste avec logs
############################################

echo "[7/11] Script IBSS..."

cat > /usr/local/bin/setup-adhoc.sh <<'EOF'
#!/bin/bash
set -e

LOGFILE="/var/log/mesh-adhoc.log"
exec >> "$LOGFILE" 2>&1

echo "=== Mesh start $(date) ==="

if [ ! -f /etc/mesh-id ]; then
  echo "❌ /etc/mesh-id introuvable"
  exit 1
fi

BOARD_ID=$(cat /etc/mesh-id)
IP="10.0.0.${BOARD_ID}"
ESSID="mesh-test"
CHANNEL_FREQ="2437"
MAC_SUFFIX=$(printf "%02x" "$BOARD_ID")

# Lever l'interface Wi-Fi avant IBSS
echo "⚡ Mise en UP de wlan0..."
ip link set wlan0 up || true
sleep 1

# Configuration IBSS
echo "⚙️  Mode IBSS..."
iw dev wlan0 set type ibss
ip link set wlan0 up
sleep 0.5

echo "🔗 Join SSID $ESSID sur channel $CHANNEL_FREQ..."
iw dev wlan0 ibss join "$ESSID" "$CHANNEL_FREQ" fixed-freq "02:11:22:33:44:$MAC_SUFFIX"

# Attribution IP
ip addr flush dev wlan0
ip addr add "${IP}/24" dev wlan0

echo "✅ wlan0 prêt avec IP ${IP}"
EOF

chmod +x /usr/local/bin/setup-adhoc.sh
echo "✅ Script IBSS prêt"

############################################
# [8/11] Service systemd – IBSS
############################################

echo "[8/11] Service systemd IBSS..."

cat > /etc/systemd/system/mesh-ibss.service <<EOF
[Unit]
Description=Mesh IBSS Network (wlan0)
After=network.target
Before=olsrv2.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-adhoc.sh
RemainAfterExit=yes
StandardOutput=append:/var/log/mesh-adhoc.log
StandardError=append:/var/log/mesh-adhoc.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mesh-ibss.service

############################################
# [9/11] Service systemd – OLSRv2
############################################

echo "[9/11] Service systemd OLSRv2..."

cat > /etc/systemd/system/olsrv2.service <<EOF
[Unit]
Description=OLSRv2 Routing Daemon (OONF)
After=mesh-ibss.service
Requires=mesh-ibss.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/olsrd2_dynamic -f /etc/olsrd2/olsrd2.conf -d 1
Environment=LD_LIBRARY_PATH=/usr/local/lib/oonf
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable olsrv2.service

############################################
# [10/11] Identité & logs
############################################
echo "[10/11] Finalisation..."

echo "$BOARD_ID" > /etc/mesh-id
mkdir -p /var/log
touch /var/log/mesh-adhoc.log

echo "========================================="
echo " ✅ INSTALLATION TERMINÉE"
echo " Node ID : $BOARD_ID"
echo " IP      : $IP"
echo " ESSID   : $ESSID"
echo "========================================="
echo ""
echo "👉 Redémarre maintenant : sudo reboot"
