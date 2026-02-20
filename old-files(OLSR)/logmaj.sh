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
# Logging & status
############################################
LOGFILE="/var/log/logmaj.txt"

mkdir -p /var/log
touch "$LOGFILE"
chmod 644 "$LOGFILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

step_start() {
  STEP_NAME="$1"
  STEP_ID="$2"
  log "[STEP $STEP_ID] $STEP_NAME : START"
}

step_ok() {
  log "[STEP $STEP_ID] $STEP_NAME : OK"
}

step_fail() {
  log "[STEP $STEP_ID] $STEP_NAME : FAIL"
  log "Arrêt du script (erreur bloquante)"
  exit 1
}

run() {
  "$@" >>"$LOGFILE" 2>&1 || step_fail
}

############################################
# Systemd logging helpers
############################################
log_systemd_status() {
  SERVICE="$1"

  {
    echo "------ systemd status : $SERVICE ------"
    systemctl is-enabled "$SERVICE" 2>&1 || true
    systemctl is-active  "$SERVICE" 2>&1 || true
    systemctl status     "$SERVICE" --no-pager -l 2>&1
    echo "---------------------------------------"
  } >>"$LOGFILE"
}


log "===== DÉMARRAGE INSTALLATION MESH ====="
log "BOARD_ID=$BOARD_ID"

############################################
# [1/11] Paquets requis
############################################
echo "[1/11] Installation des dépendances..."
step_start "[1/11] Installation des dépendances..."


if [ -f /etc/apt/apt.conf.d/95proxy ]; then
    rm /etc/apt/apt.conf.d/95proxy
fi

cp 95proxy /etc/apt/apt.conf.d/

date -s "02 FEB 2026 16:45:00"

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

echo "Etape 1 OK."
############################################
# [2/11] Désactivation NetworkManager / WPA
############################################
echo "[2/11] Désactivation services conflictuels..."
step_start "[2/11] Désactivation services conflictuels..."

log "[ACTION] Désactivation NetworkManager"
systemctl disable --now NetworkManager >>"$LOGFILE" 2>&1|| true
log_systemd_status NetworkManager

log "[ACTION] Désactivation wpa_supplicant"
systemctl disable --now wpa_supplicant >>"$LOGFILE"  2>&1 || true
log_systemd_status wpa_supplicant

echo "Etape 2 OK."
############################################
# [3/11] Activation systemd-networkd
############################################
echo "[3/11] Activation systemd-networkd..."
step_start "[3/11] Activation systemd-networkd..."

log "[ACTION] Désactivation systemd-networkd"
systemctl enable systemd-networkd >>"$LOGFILE" 2>&1
systemctl start systemd-networkd >>"$LOGFILE" 2>&1
log_systemd_status systemd-networkd

echo "Etape 3 OK."
# ############################################
# # [4/11] Configuration réseau statique
# ############################################
# echo "[4/11] Configuration réseau wlan0..."
# step_start "[4/11] Configuration réseau wlan0..."
# 
# cat > /etc/systemd/network/10-mesh.network <<EOF
# [Match]
# Name=wlan0
# 
# [Network]
# Address=$IP/24
# ConfigureWithoutCarrier=yes
# EOF
# echo "Etape 4 OK."

############################################
# [5/11] Compilation et installation OLSRv2
############################################
echo "[5/11] Compilation OLSRv2 (OONF)..."
step_start "[5/11] Compilation OLSRv2 (OONF)..."

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

echo "Etape 5 OK."
############################################
# [6/11] Configuration OLSRv2
############################################

echo "[6/11] Configuration OLSRv2..."
step_start "[6/11] Configuration OLSRv2..."

mkdir -p /etc/olsrd2

cat > /etc/olsrd2/olsrd2.conf <<EOF
[olsrd]
# Version de debug
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

echo "Etape 6 OK."
############################################
# [7/11] Exclure wlan0 de systemd-networkd
############################################
echo "[7/11] Exclusion de wlan0 de systemd-networkd..."
step_start "[7/11] Exclusion de wlan0 de systemd-networkd..."

# Supprimer toute configuration réseau existante pour wlan0
rm -f /etc/systemd/network/*wlan0*.network
rm -f /etc/systemd/network/10-mesh.network

# Créer une règle pour rendre wlan0 unmanaged
rm -f /etc/systemd/network/99-ignore-wlan0.link

cat > /etc/systemd/network/99-ignore-wlan0.link <<EOF
[Match]
OriginalName=wlan0

[Link]
Unmanaged=yes
EOF

# Redémarrer systemd-networkd pour appliquer la règle
log "[ACTION] Restart systemd-networkd"
systemctl restart systemd-networkd >>"$LOGFILE" 2>&1
log_systemd_status systemd-networkd

echo "✅ wlan0 est maintenant unmanaged par systemd-networkd"

echo "Etape 7 OK."
############################################
# [8/11] Script IBSS – robuste avec logs
############################################
echo "[8/11] Script IBSS..."
step_start "[8/11] Script IBSS..."

cat > /usr/local/bin/setup-adhoc.sh <<'EOF'
#!/bin/bash

LOGFILE="/var/log/mesh-adhoc.log"
exec >> "$LOGFILE" 2>&1

echo "=== Mesh start $(date) ==="

# Sécurité : tuer wpa_supplicant
systemctl stop wpa_supplicant 2>/dev/null || true
pkill wpa_supplicant 2>/dev/null || true

# Attendre wlan0
for i in {1..10}; do
  if ip link show wlan0 >/dev/null 2>&1; then
    break
  fi
  echo " Attente wlan0..."
  sleep 1
done

# Lecture ID
BOARD_ID=$(cat /etc/mesh-id)
IP="10.0.0.$BOARD_ID"
ESSID="mesh-test"
CHANNEL_FREQ="2437"

# Reset propre
ip link set wlan0 down
sleep 2

# IBSS
if ! iw dev wlan0 set type ibss; then
  echo " set type ibss failed"
  exit 1
fi

ip link set wlan0 up
sleep 2

# JOIN SANS BSSID
if ! iw dev wlan0 ibss join "$ESSID" "$CHANNEL_FREQ" fixed-freq; then
  echo " ibss join failed"
  exit 1
fi

# IP
ip addr flush dev wlan0
ip addr add "${IP}/24" dev wlan0

echo " IBSS OK – IP $IP"

ip link set wlan0 up
sleep 2

echo " Join SSID $ESSID sur channel $CHANNEL_FREQ..."
if ! iw dev wlan0 ibss join "$ESSID" "$CHANNEL_FREQ" fixed-freq ; then
    echo " Impossible de rejoindre le réseau IBSS"
    echo " [WARN] échec temporaire IBSS"
    exit 0
fi

# Attribution IP
ip addr flush dev wlan0
ip addr add "${IP}/24" dev wlan0

# Vérification
if ip addr show wlan0 | grep -q "$IP"; then
    echo " wlan0 prêt avec IP ${IP}"
else
    echo " IP non appliquée sur wlan0"
    echo " [WARN] échec temporaire IBSS"
    exit 0
fi
EOF

chmod +x /usr/local/bin/setup-adhoc.sh
echo " Script IBSS prêt (logs + IP garantis)"

echo "Etape 8 OK."
############################################
# [9/11] Service systemd – IBSS
############################################
echo "[9/11] Service systemd IBSS..."
step_start "[9/11] Service systemd IBSS..."

cat > /etc/systemd/system/mesh-ibss.service <<EOF
[Unit]
Description=Mesh IBSS Network (wlan0)
After=sys-subsystem-net-devices-wlan0.device
Requires=sys-subsystem-net-devices-wlan0.device

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-adhoc.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

log "[ACTION] systemd daemon-reload"
systemctl daemon-reload >>"$LOGFILE" 2>&1
{
  echo "------ systemd daemon-reload ------"
  systemctl show --property=Version
  echo "----------------------------------"
} >>"$LOGFILE"

log "[ACTION] Activation mesh-ibss.service"
systemctl enable mesh-ibss.service >>"$LOGFILE" 2>&1
log_systemd_status mesh-ibss.service

echo "Etape 9 OK."
############################################
# [10/11] Service systemd – OLSRv2
############################################
echo "[10/11] Service systemd OLSRv2..."
step_start "[10/11] Service systemd OLSRv2..."

cat > /etc/systemd/system/olsrv2.service <<EOF
[Unit]
Description=OLSRv2 Routing Daemon (OONF)
After=mesh-ibss.service
Wants=mesh-ibss.service

[Service]
ExecStartPre=/bin/bash -c '\
echo "Attente d une adresse IP 10.0.0.x sur wlan0..."; \
for i in {1..20}; do \
  if ip addr show wlan0 | grep -q "10.0.0."; then \
    echo "IP détectée sur wlan0, démarrage de olsrd2"; \
    exit 0; \
  fi; \
  echo "Tentative $i/20 : IP non disponible, nouvelle tentative dans 1s"; \
  sleep 1; \
done; \
echo "Erreur : aucune IP 10.0.0.x détectée après 20 secondes"; \
exit 1'
ExecStart=/usr/local/sbin/olsrd2_dynamic -f /etc/olsrd2/olsrd2.conf -d 1
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log "[ACTION] systemd daemon-reload"
systemctl daemon-reload >>"$LOGFILE" 2>&1

log "[ACTION] Activation olsrv2.service"
systemctl enable olsrv2.service >>"$LOGFILE" 2>&1

log "[ACTION] Démarrage olsrv2.service"
systemctl start olsrv2.service >>"$LOGFILE" 2>&1

if ! systemctl is-active --quiet olsrv2.service; then
  log "❌ olsrv2.service FAILED TO START"
  log_systemd_status olsrv2.service
  exit 1
fi

log "✅ olsrv2.service démarré avec succès"
log_systemd_status olsrv2.service

step_ok
echo "Etape 10 OK."
############################################
# [11/11] Identité & logs
############################################
echo "[11/11] Finalisation..."
step_start "[11/11] Finalisation..."

echo "$BOARD_ID" > /etc/mesh-id
mkdir -p /var/log
touch /var/log/mesh-adhoc.log
step_ok

echo "========================================="
echo " ✅ INSTALLATION TERMINÉE"
echo " Node ID : $BOARD_ID"
echo " IP      : $IP"
echo " ESSID   : $ESSID"
echo "========================================="
echo ""
echo "👉 Redémarre maintenant : sudo reboot"