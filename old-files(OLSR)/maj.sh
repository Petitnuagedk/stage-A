#!/bin/bash
set -e

############################################
# Raspberry Pi Zero W – Mesh IBSS (Bookworm)
# Déploiement stable parc complet
# Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]
############################################

### Sécurité
if [ "$EUID" -ne 0 ]; then
  echo "Lancer avec sudo"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]"
  exit 1
fi

BOARD_ID="$1"
IP="10.0.0.$BOARD_ID"
ESSID="mesh-test"
CHANNEL_FREQ="2437"
MAC_SUFFIX=$(printf "%02x" "$BOARD_ID")

echo "========================================="
echo " Mesh Bookworm – Node $BOARD_ID ($IP)"
echo "========================================="

############################################
# [1/12] Dépendances
############################################
echo "[1/12] Installation dépendances"

if [ -f /etc/apt/apt.conf.d/95proxy ]; then
  rm /etc/apt/apt.conf.d/95proxy
fi

date -s "29 JAN 2026 16:45:00"

cp 95proxy /etc/apt/apt.conf.d/

apt update
apt install -y \
  iw iproute2 netcat-openbsd \
  build-essential git cmake pkg-config \
  bison flex libnl-3-dev libnl-genl-3-dev \
  libconfig-dev libprotobuf-c-dev protobuf-c-compiler \
  systemd \
  nmap \
  arp-scan

############################################
# [2/12] Désactivation services Wi-Fi conflictuels
############################################
echo "[2/12] Désactivation NetworkManager / WPA"
systemctl disable --now NetworkManager 2>/dev/null || true
systemctl disable --now wpa_supplicant 2>/dev/null || true

############################################
# [3/12] systemd-networkd (pour eth0 uniquement)
############################################
echo "[3/12] Activation systemd-networkd"
systemctl enable systemd-networkd
systemctl start systemd-networkd

############################################
# [4/12] Compilation OLSRv2
############################################
echo "[4/12] Compilation OLSRv2"
mv OONF /tmp
cd /tmp/OONF || exit 1
mkdir -p build
cd build
cmake ..
make
make install
ldconfig

############################################
# [5/12] Configuration OLSRv2
############################################
echo "[5/12] Configuration OLSRv2"
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
EOF

############################################
# [6/12] Exclusion wlan0 de networkd
############################################
echo "[6/12] wlan0 unmanaged"

rm -f /etc/systemd/network/*wlan0*.network
rm -f /etc/systemd/network/99-ignore-wlan0.link

cat > /etc/systemd/network/99-ignore-wlan0.link <<EOF
[Match]
OriginalName=wlan0

[Link]
Unmanaged=yes
EOF

systemctl restart systemd-networkd

############################################
# [7/12] Script IBSS (ONE SHOT – SAFE)
############################################
echo "[7/12] Création setup-adhoc.sh"

cat > /usr/local/bin/setup-adhoc.sh <<'EOF'
#!/bin/bash
set -e

LOGFILE="/var/log/mesh-adhoc.log"
exec >> "$LOGFILE" 2>&1

echo "=== IBSS start $(date) ==="

BOARD_ID=$(cat /etc/mesh-id)
IP="10.0.0.${BOARD_ID}"
ESSID="mesh-test"
CHANNEL_FREQ="2437"
MAC_SUFFIX=$(printf "%02x" "$BOARD_ID")

# Attente apparition wlan0
for i in $(seq 1 30); do
  ip link show wlan0 >/dev/null 2>&1 && break
  sleep 2
done

# Sécurité : déjà en IBSS
if iw dev wlan0 info | grep -q "type IBSS"; then
  echo "IBSS déjà actif"
  exit 0
fi

ip link set wlan0 down
sleep 1

iw dev wlan0 set type ibss
ip link set wlan0 up
sleep 1

iw dev wlan0 ibss join "$ESSID" "$CHANNEL_FREQ" fixed-freq \
  "02:11:22:33:44:$MAC_SUFFIX"

ip addr flush dev wlan0
ip addr add "${IP}/24" dev wlan0

echo "IBSS configuré"
EOF

chmod +x /usr/local/bin/setup-adhoc.sh

############################################
# [8/12] Service mesh-ibss (ONESHOT)
############################################
echo "[8/12] Service mesh-ibss"

cat > /etc/systemd/system/mesh-ibss.service <<EOF
[Unit]
Description=Mesh IBSS Network (wlan0)
After=network-online.target systemd-udev-settle.service
Wants=network-online.target
Before=olsrv2.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-adhoc.sh
RemainAfterExit=yes
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mesh-ibss.service

############################################
# [9/12] Service OLSRv2
############################################
echo "[9/12] Service OLSRv2"

cat > /etc/systemd/system/olsrv2.service <<EOF
[Unit]
Description=OLSRv2 Routing
After=mesh-ibss.service
Requires=mesh-ibss.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/olsrd2_dynamic \
  -f /etc/olsrd2/olsrd2.conf -d 1
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable olsrv2.service

############################################
# [10/12] add.sh (démarrage tardif)
############################################
echo "[10/12] Service add.sh"

cp /home/rpi/add.sh /usr/local/bin/add.sh
chmod +x /usr/local/bin/add.sh

cat > /etc/systemd/system/add-sh.service <<EOF
[Unit]
Description=Scan réseau add.sh
After=mesh-ibss.service olsrv2.service
Requires=mesh-ibss.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 30
ExecStart=/usr/local/bin/add.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable add-sh.service

############################################
# [11/12] Identité
############################################
echo "$BOARD_ID" > /etc/mesh-id

############################################
# [12/12] Logs
############################################
mkdir -p /var/log
touch /var/log/mesh-adhoc.log

echo "========================================="
echo " INSTALLATION TERMINÉE"
echo " Node ID : $BOARD_ID"
echo " IP      : $IP"
echo " ESSID   : $ESSID"
echo "========================================="
echo "Redémarre : sudo reboot"
