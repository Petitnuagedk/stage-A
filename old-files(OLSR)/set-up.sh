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
# [1/9] Paquets requis
############################################
echo "[1/9] Installation des dépendances..."
apt update
apt install -y \
  iw iproute2 netcat-openbsd \
  build-essential git \
  systemd

############################################
# [2/9] Désactivation NetworkManager / WPA
############################################
echo "[2/9] Désactivation services conflictuels..."
systemctl disable --now NetworkManager 2>/dev/null || true
systemctl disable --now wpa_supplicant 2>/dev/null || true

############################################
# [3/9] Activation systemd-networkd
############################################
echo "[3/9] Activation systemd-networkd..."
systemctl enable systemd-networkd
systemctl start systemd-networkd

############################################
# [4/9] Configuration réseau statique
############################################
echo "[4/9] Configuration réseau wlan0..."

cat > /etc/systemd/network/10-mesh.network <<EOF
[Match]
Name=wlan0

[Network]
Address=$IP/24
ConfigureWithoutCarrier=yes
EOF

############################################
# [5/9] Compilation et installation OLSRd
############################################

echo "[5/9] Compilation OLSRd (installation unique)..."

apt update
apt install -y build-essential bison flex autoconf automake libtool pkg-config cmake

mv olsrd.tar.gz /tmp
cd /tmp
tar xzf olsrd.tar.gz

cd /tmp/olsrd || { echo "❌ /tmp/olsrd introuvable"; exit 1; }

./autogen.sh || true
make clean
cd build
cmake ..
make 

echo "✅ OLSRd installé"

############################################
# [6/9] Configuration OLSRd + txtinfo
############################################
echo "[6/9] Configuration OLSRd..."

mkdir -p /etc/olsrd

cat > /etc/olsrd/olsrd.conf <<EOF
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

############################################
# [7/9] Script IBSS (iw)
############################################
echo "[7/9] Script IBSS..."

cat > /usr/local/bin/setup-adhoc.sh <<EOF
#!/bin/bash
set -e
exec >> /var/log/mesh-adhoc.log 2>&1

echo "=== Mesh start \$(date) ==="

ip link set wlan0 down
iw dev wlan0 set type ibss
ip link set wlan0 up

iw dev wlan0 ibss join $ESSID $CHANNEL_FREQ fixed-freq 02:11:22:33:44:$MAC_SUFFIX

ip addr flush dev wlan0
ip addr add $IP/24 dev wlan0

/usr/local/sbin/olsrd -f /etc/olsrd/olsrd.conf -d 1 &
echo "wlan0 prêt avec $IP"
EOF

chmod +x /usr/local/bin/setup-adhoc.sh

############################################
# [8/9] Service systemd
############################################
echo "[8/9] Service systemd..."

cat > /etc/systemd/system/mesh.service <<EOF
[Unit]
Description=Mesh IBSS Network
After=systemd-networkd.service
Wants=systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-adhoc.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mesh.service

############################################
# [9/9] Identité & logs
############################################
echo "[9/9] Finalisation..."

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
