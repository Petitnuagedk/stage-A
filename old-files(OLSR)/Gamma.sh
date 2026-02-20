############################################
# Raspberry Pi Zero W – Mesh IBSS (Bookworm)
# Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]
############################################

### --- Sécurité ---
if [ "$EUID" -ne 0 ]; then
  echo "Lancer ce script avec sudo"
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
# [1/17] Paquets requis
############################################
echo "[1/17] Installation des dépendances..."
step_start "[1/17] Installation des dépendances..."


if [ -f /etc/apt/apt.conf.d/95proxy ]; then
    rm /etc/apt/apt.conf.d/95proxy
fi

cp 95proxy /etc/apt/apt.conf.d/

date -s "12 FEB 2026 16:45:00"

apt update

apt install -y \
  iw iproute2 netcat-openbsd \
  build-essential \
  git \
  cmake \
  pkg-config \
  bison \
  flex \
  libnl-route-3-dev \
  libnl-cli-3-dev \
  libnl-nf-3-dev \
  libnl-3-dev \
  libnl-genl-3-dev \
  libconfig-dev \
  libprotobuf-c-dev \
  protobuf-c-compiler \
  systemd \
  nmap \
  arp-scan \
  nftables \
  rsyslog \
  chrony \
  jq \
  iputils-ping \
  net-tools \
  sshpass

echo "apt pleinement installé"

#cd /usr/src
#git clone https://github.com/OLSR/OONF.git
#cd OONF
#mkdir build
#cd build

echo "Etape 1 OK."

############################################
# [2/17] Désactivation NetworkManager / WPA
############################################
echo "[2/17] Désactivation services conflictuels..."
step_start "[2/17] Désactivation services conflictuels..."

#cd /home/rpi

log "[ACTION] Désactivation NetworkManager"
systemctl disable --now NetworkManager >>"$LOGFILE" 2>&1|| true
log_systemd_status NetworkManager

log "[ACTION] Désactivation wpa_supplicant"
systemctl disable --now wpa_supplicant >>"$LOGFILE"  2>&1 || true
log_systemd_status wpa_supplicant

echo "Etape 2 OK."

############################################
# [3/17] Activation systemd-networkd
############################################
echo "[3/17] Activation systemd-networkd..."
step_start "[3/17] Activation systemd-networkd..."

log "[ACTION] Désactivation systemd-networkd"
systemctl enable systemd-networkd >>"$LOGFILE" 2>&1
systemctl start systemd-networkd >>"$LOGFILE" 2>&1
log_systemd_status systemd-networkd

echo "Etape 3 OK."

############################################
# [4/17] Synchronisation Date & Heure – Mesh Chrony
############################################
echo "[4/17] Configuration NTP Mesh (chrony)..."
step_start "[4/17] Configuration NTP Mesh (chrony)..."

systemctl disable --now systemd-timesyncd >/dev/null 2>&1 || true

if [ "$BOARD_ID" -eq 1 ]; then
  log "NTP Mesh : configuration NOEUD MAÎTRE (10.0.0.1)"

  cat > /etc/chrony/chrony.conf <<EOF
# === Chrony MASTER – Mesh 10.0.0.0/24 ===

# Ce noeud est la référence de temps locale
local stratum 10

# Autoriser les clients du mesh
allow 10.0.0.0/24

# Corriger l'heure brutalement au boot si nécessaire
makestep 1.0 3

# Logs
logdir /var/log/chrony
EOF

else
  log "NTP Mesh : configuration NOEUD CLIENT (sync sur 10.0.0.1)"

  cat > /etc/chrony/chrony.conf <<EOF
# === Chrony CLIENT – Mesh ===

# Serveur NTP unique
server 10.0.0.1 iburst

# Correction rapide si dérive importante
makestep 1.0 3

# Logs
logdir /var/log/chrony
EOF
fi

systemctl enable chrony >>"$LOGFILE" 2>&1
systemctl restart chrony >>"$LOGFILE" 2>&1
log_systemd_status chrony

cat > /usr/local/bin/mesh-ntp-sync.sh <<'EOF'
#!/bin/bash

LOG="/var/log/mesh-ntp.log"
echo "=== Mesh NTP sync $(date) ===" >> "$LOG"

# Attente IP mesh
for i in {1..30}; do
  if ip addr show wlan0 | grep -q "10.0.0."; then
    break
  fi
  sleep 1
done

# Resynchronisation forcée
chronyc -a makestep >> "$LOG" 2>&1
chronyc tracking >> "$LOG" 2>&1
EOF

chmod +x /usr/local/bin/mesh-ntp-sync.sh

cat > /etc/systemd/system/mesh-ntp-sync.service <<EOF
[Unit]
Description=Mesh NTP Resynchronisation (chrony)
After=mesh-ibss.service
Wants=mesh-ibss.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mesh-ntp-sync.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >>"$LOGFILE" 2>&1
systemctl enable mesh-ntp-sync.service >>"$LOGFILE" 2>&1

step_ok
echo "Etape 4 OK."

############################################
# [5/17] Compilation et installation OLSRv2
############################################
echo "[5/17] Compilation OLSRv2 (OONF)..."
step_start "[5/17] Compilation OLSRv2 (OONF)..."

cp -r OONF /usr/src/
sleep 10
cd /usr/src
cd OONF
#mkdir build
cd build

chown -R root:root /usr/src/OONF
#cd /tmp/OONF || { echo " /tmp/OONF introuvable"; exit 1; }

# Build out-of-source
#mkdir -p build
#cd build

#cd /usr/src/OONF/build

echo "Configuration CMake..."
cmake .. -DCMAKE_INSTALL_PREFIX=/usr 

echo "Compilation..."
make -j$(nproc)
echo "== Recherche binaire dans build =="
find . -type f -name "olsrd2_dynamic" || step_fail

echo "Installation..."
make install || step_fail

echo "/usr/lib/oonf" > /etc/ld.so.conf.d/oonf.conf
ldconfig

echo "Vérification binaire OLSRv2"

ls -l /usr/sbin/olsrd2_dynamic || step_fail

if ldd /usr/sbin/olsrd2_dynamic | grep -q "not found"; then
  log "Libs non résolues AVANT reboot (normal à ce stade)"
else
  log "Toutes les libs sont correctement résolues"
fi

echo "Etape 5 OK."

############################################
# [6/17] Configuration OLSRv2
############################################

echo "[6/17] Configuration OLSRv2..."
step_start "[6/17] Configuration OLSRv2..."

mkdir -p /etc/olsrd2

cat > /etc/olsrd2/olsrd2.conf <<EOF
Interface "wlan0"
{
    Type = mesh
    HelloInterval = 2.0
    TcInterval = 5.0
}

Plugin "txtinfo.so"
{
    Port = 2006
    Accept = "0.0.0.0"
}

LogLevel = info
EOF

echo "Configuration OLSRv2 prête"

echo "Etape 6 OK."

############################################
# [7/17] Exclure wlan0 de systemd-networkd
############################################
echo "[7/17] Exclusion de wlan0 de systemd-networkd..."
step_start "[7/17] Exclusion de wlan0 de systemd-networkd..."

rm -f /etc/systemd/network/*wlan0*.network
rm -f /etc/systemd/network/10-mesh.network

rm -f /etc/systemd/network/99-ignore-wlan0.link

cat > /etc/systemd/network/99-ignore-wlan0.link <<EOF
[Match]
OriginalName=wlan0

[Link]
Unmanaged=yes
LinkLocalAddressing=no
DHCP=no
IPv6AcceptRA=no
EOF

log "[ACTION] Restart systemd-networkd"
systemctl restart systemd-networkd >>"$LOGFILE" 2>&1
log_systemd_status systemd-networkd

echo "wlan0 est maintenant unmanaged par systemd-networkd"

echo "Etape 7 OK."

############################################
# [8/17] Passage en IP fiable
############################################
echo "[8/17] Script IBSS..."
step_start "[8/17] Script IBSS..."

cat > /etc/sysctl.d/99-mesh-no-ipv4ll.conf <<EOF
net.ipv4.conf.all.autoconf=0
net.ipv4.conf.default.autoconf=0
net.ipv4.conf.wlan0.autoconf=0
net.ipv4.conf.all.accept_local=0
net.ipv4.conf.default.accept_local=0
EOF

sysctl --system

echo "Etape 8 OK."

############################################
# [9/17] Script IBSS – robuste avec logs
############################################
echo "[9/17] Script IBSS..."
step_start "[9/17] Script IBSS..."

cat > /usr/local/bin/setup-adhoc.sh <<'EOF'
#!/bin/bash

LOGFILE="/var/log/mesh-adhoc.log"
exec >> "$LOGFILE" 2>&1

echo "=== Mesh start $(date) ==="

systemctl stop wpa_supplicant 2>/dev/null || true
pkill wpa_supplicant 2>/dev/null || true

for i in {1..10}; do
  ip link show wlan0 >/dev/null 2>&1 && break
  echo " Attente wlan0..."
  sleep 1
done

BOARD_ID=$(cat /etc/mesh-id)
IP="10.0.0.$BOARD_ID"
ESSID="mesh-test"
CHANNEL_FREQ="2437"

ip link set wlan0 down
sleep 2

iw dev wlan0 set type ibss || {
  echo " set type ibss failed"
  exit 1
}

ip link set wlan0 up
sleep 2

iw dev wlan0 ibss join "$ESSID" "$CHANNEL_FREQ" fixed-freq || {
  echo " ibss join failed"
  exit 1
}
ip link set wlan0 up
sleep 2
ip addr flush dev wlan0
# IP statique finale
ip addr add "${IP}/24" dev wlan0

for i in {1..15}; do
  if iw dev wlan0 info | grep -q "type IBSS"; then
    echo " IBSS stable"
    break
  fi
  echo " Attente stabilisation IBSS..."
  sleep 1
done

# Bloquer link-local et config auto IP au niveau kernel
sysctl -w net.ipv4.conf.wlan0.use_tempaddr=0 >/dev/null
sysctl -w net.ipv4.conf.wlan0.accept_local=0 >/dev/null
sysctl -w net.ipv4.conf.wlan0.autoconf=0 >/dev/null
sysctl -w net.ipv4.conf.wlan0.arp_ignore=1 >/dev/null

ip addr add "${IP}/24" dev wlan0

if ip addr show wlan0 | grep -q "$IP"; then
    echo " wlan0 prêt avec IP ${IP}"
else
    echo " [WARN] IBSS OK mais IP non appliquée"
fi

ip link set wlan0 up

EOF

echo "$(ip addr show wlan0)"

chmod +x /usr/local/bin/setup-adhoc.sh
echo " Script IBSS prêt (logs + IP garantis)"

echo "Etape 9 OK."

############################################
# [10/17] Service systemd – IBSS
############################################
echo "[10/17] Service systemd IBSS..."
step_start "[10/17] Service systemd IBSS..."

cat > /etc/systemd/system/mesh-ibss.service <<EOF
[Unit]
Description=Mesh IBSS Network (wlan0)
After=sys-subsystem-net-devices-wlan0.device
Requires=sys-subsystem-net-devices-wlan0.device

[Service]
Type=simple
ExecStart=/usr/local/bin/setup-adhoc.sh
Restart=on-failure
RestartSec=2
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "$(ip addr show wlan0)"

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

echo "$(ip addr show wlan0)"

echo "Etape 10 OK."

############################################
# [11/17] Ping broadcast périodique (FIXE)
############################################
echo "[11/17] Ping broadcast mesh (fixe)..."
step_start "[11/17] Ping broadcast mesh (fixe)..."

cat > /usr/local/bin/mesh-broadcast-ping.sh <<'EOF'
#!/bin/bash

INTERFACE="wlan0"
BROADCAST_IP="10.0.0.255"
INTERVAL=10

echo "=== Mesh broadcast ping started $(date) ==="
echo "Interface  : $INTERFACE"
echo "Broadcast  : $BROADCAST_IP"
echo "Intervalle : ${INTERVAL}s"

while true; do
  if ip link show "$INTERFACE" | grep -q "UP"; then
    break
  fi
  sleep 1
done

sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 >/dev/null

while true; do
  ping -b -c 1 -W 1 "$BROADCAST_IP" >/dev/null 2>&1
  sleep "$INTERVAL"
done
EOF

echo "$(ip addr show wlan0)"
chmod +x /usr/local/bin/mesh-broadcast-ping.sh

cat > /etc/systemd/system/mesh-broadcast-ping.service <<EOF
[Unit]
Description=Mesh Broadcast Ping (10.0.0.255)
After=mesh-ibss.service
Wants=mesh-ibss.service

[Service]
Type=simple
ExecStart=/usr/local/bin/mesh-broadcast-ping.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mesh-broadcast-ping.service >>"$LOGFILE" 2>&1
systemctl start mesh-broadcast-ping.service  >>"$LOGFILE" 2>&1

echo "$(ip addr show wlan0)"

step_ok
echo "Etape 11 OK."

############################################
# [12/17] Service systemd – OLSRv2
############################################
echo "[12/17] Service systemd OLSRv2..."
step_start "[12/17] Service systemd OLSRv2..."

cat > /etc/systemd/system/olsrv2.service <<EOF
[Unit]
Description=OLSRv2 Routing Daemon (OONF)
After=mesh-ibss.service
Wants=mesh-ibss.service

[Service]
Type=simple

ExecStart=/usr/sbin/olsrd2_dynamic \

# Attente IP SANS FAIL systemd
ExecStartPost=/bin/bash -c '\
for i in {1..30}; do \
  if ip addr show wlan0 | grep -q "10.0.0."; then \
    echo "IP 10.0.0.x détectée sur wlan0"; \
    exit 0; \
  fi; \
  echo "Attente IP mesh ($i/30)..."; \
  sleep 1; \
done; \
echo "WARN: OLSRv2 lancé sans IP 10.0.0.x"; \
exit 0'

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
  log "olsrv2.service FAILED TO START"
  log_systemd_status olsrv2.service
  exit 1
fi

log "olsrv2.service démarré avec succès"
log_systemd_status olsrv2.service

echo "$(ip addr show wlan0)"

step_ok
echo "Etape 12 OK."

############################################
# [13/17] Logs ICMP mesh JSON temps réel – déclenchement maître
############################################
echo "[13/17] Logs ICMP JSON temps réel..."
step_start "[13/17] Logs ICMP JSON temps réel..."

cat > /usr/local/bin/mesh-icmp-json.sh <<'EOF'
#!/bin/bash

LOG_JSON="/var/log/mesh-icmp.json"
INTERFACE="wlan0"
PING_INTERVAL=1
DURATION=600

IPS=$(seq 1 10 | awk -v base="10.0.0." '{print base $1}')

echo "=== Démarrage logs ICMP JSON $(date) ==="

END=$((SECONDS+DURATION))

while [ $SECONDS -lt $END ]; do

  DATA=()
  ROUTES_JSON=()

  for IP in $IPS; do

    PING=$(ping -I "$INTERFACE" -c 1 -W 1 "$IP" 2>/dev/null)

    if [ $? -eq 0 ]; then

      TTL=$(echo "$PING" | grep 'ttl=' | sed -E 's/.*ttl=([0-9]+).*/\1/')
      LATENCY=$(echo "$PING" | grep 'time=' | sed -E 's/.*time=([0-9\.]+).*/\1/')
      ROUTE_INFO=$(ip route get "$IP" dev "$INTERFACE" 2>/dev/null)

      NEXT_HOP=$(echo "$ROUTE_INFO" | awk '/via/ {print $3}')

      if [ -z "$NEXT_HOP" ]; then
          NEXT_HOP="DIRECT"
      fi

      NEXT_HOP=$(ip route get "$IP" dev "$INTERFACE" 2>/dev/null | awk '/via/ {print $3}')
      [ -z "$NEXT_HOP" ] && NEXT_HOP="DIRECT"

      HOPS=0

      ROUTE_LINE=$(echo "/olsrv2info route" | nc 127.0.0.1 2006 2>/dev/null | grep "$IP ")

      if [ -n "$ROUTE_LINE" ]; then
        # OONF affiche souvent la métrique dans la colonne 4
        METRIC=$(echo "$ROUTE_LINE" | awk '{print $4}')
        [ -n "$METRIC" ] && HOPS="$METRIC"
      fi

      DATA+=("{\"SRC\":\"$IP\",\"TTL\":$TTL,\"HOPS\":$HOPS,\"LATENCY_MS\":$LATENCY,\"NEXT_HOP\":\"$NEXT_HOP\"}")
    fi
  done

  while read -r line; do
    IP_ADDR=$(echo "$line" | awk '{print $1}')
    STATE=$(echo "$line" | awk '{print $NF}')

    if [[ "$IP_ADDR" =~ ^10\.0\.0\.[0-9]+$ ]]; then

      LAT=$(ping -I "$INTERFACE" -c 1 -W 1 "$IP_ADDR" 2>/dev/null | \
            grep 'time=' | sed -E 's/.*time=([0-9\.]+).*/\1/')

      [ -z "$LAT" ] && LAT=0

      ROUTES_JSON+=("{\"IP\":\"$IP_ADDR\",\"STATE\":\"$STATE\",\"LATENCY_MS\":$LAT}")
    fi
  done < <(ip -4 neigh show dev "$INTERFACE")

  TMP_FILE="/tmp/mesh-icmp.tmp"

  {
    echo "{"
    echo "  \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
    echo "  \"icmp_table\": ["
    echo "    $(IFS=,; echo "${DATA[*]}")"
    echo "  ],"
    echo "  \"routes\": ["
    echo "    $(IFS=,; echo "${ROUTES_JSON[*]}")"
    echo "  ]"
    echo "}"
  } > "$TMP_FILE"

  mv "$TMP_FILE" "$LOG_JSON"

  sleep $PING_INTERVAL
done

echo "=== Fin logs ICMP JSON $(date) ==="
EOF

chmod +x /usr/local/bin/mesh-icmp-json.sh
sudo systemctl restart mesh-icmp-json.service

cat > /etc/systemd/system/mesh-icmp-json.service <<EOF
[Unit]
Description=Mesh ICMP JSON Logging
After=network.target
Wants=mesh-ibss.service

[Service]
Type=simple
ExecStart=/usr/local/bin/mesh-icmp-json.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl disable mesh-icmp-json.service

log "Service mesh-icmp-json prêt mais inactif"
step_ok
echo "Etape 13 OK."

############################################
# [14/17] Script maître – Déclenchement ICMP global manuel
############################################
echo "[14/17] Préparation déclenchement ICMP global (manuel)..."
step_start "[14/17] Déclenchement ICMP global manuel"

if [ "$BOARD_ID" -eq 1 ]; then

cat > /usr/local/bin/mesh-run-icmp <<'EOF'
#!/bin/bash

USER="pi"
PASS="raspberry"
NETWORK="10.0.0.0/24"
DURATION=600
START_DELAY=30
LOG="/var/log/mesh-master-sync.log"
LOCAL_DIR="/home/pi/mesh-logs"

mkdir -p "$LOCAL_DIR"

echo "===================================" | tee -a "$LOG"
echo "Déclenchement synchronisé $(date)" | tee -a "$LOG"
echo "===================================" | tee -a "$LOG"

START_EPOCH=$(( $(date +%s) + START_DELAY ))
HUMAN_START=$(date -d @$START_EPOCH '+%Y-%m-%d %H:%M:%S')

echo "Départ programmé à $HUMAN_START (epoch $START_EPOCH)" | tee -a "$LOG"

NODES=$(nmap -sn $NETWORK | awk '/Nmap scan report/{print $5}' | grep 10.0.0.)

for IP in $NODES; do
    echo "Envoi ordre à $IP" | tee -a "$LOG"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        $USER@$IP \
        "sudo /usr/local/bin/mesh-icmp-json.sh $START_EPOCH > /dev/null 2>&1 &" &
done

wait

echo "Tous les ordres envoyés" | tee -a "$LOG"
echo "Attente fin acquisition..." | tee -a "$LOG"

sleep $((START_DELAY + DURATION + 5))

for IP in $NODES; do
    ID=$(echo $IP | awk -F. '{print $4}')
    DEST="$LOCAL_DIR/log.$ID.json"

    sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
        $USER@$IP:/var/log/mesh-icmp.json \
        "$DEST" > /dev/null 2>&1

    if [ -f "$DEST" ]; then
        echo "Récupéré $DEST" | tee -a "$LOG"
    else
        echo "Echec récupération $IP" | tee -a "$LOG"
    fi
done

echo "Synchronisation terminée $(date)" | tee -a "$LOG"
EOF

chmod +x /usr/local/bin/mesh-run-icmp

echo "alias mesh-run-icmp='sudo /usr/local/bin/mesh-run-icmp'" >> /home/pi/.bashrc

log "Commande disponible : sudo mesh-run-icmp"

fi

step_ok
echo "Etape 14 OK."

############################################
# [15/17] Service ICMP JSON – durée limitée 600s
############################################
echo "[15/17] Configuration service ICMP JSON..."
step_start "[15/17] Service ICMP JSON"

cat > /usr/local/bin/mesh-icmp-json.sh <<'EOF'
#!/bin/bash

LOG_JSON="/var/log/mesh-icmp.json"
INTERFACE="wlan0"
PING_INTERVAL=1
DURATION=600

START_EPOCH="$1"

if [ -z "$START_EPOCH" ]; then
    echo "Usage: mesh-icmp-json.sh <start_epoch>"
    exit 1
fi

# Attente synchronisée précise
while true; do
    NOW=$(date +%s)
    [ "$NOW" -ge "$START_EPOCH" ] && break
    sleep 0.02
done

REAL_START_EPOCH=$(date +%s)
REAL_START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

BOARD_ID=$(cat /etc/mesh-id 2>/dev/null)
NODE_IP="10.0.0.$BOARD_ID"

TMP_FILE="/tmp/mesh-icmp-full.tmp"

echo "{" > "$TMP_FILE"
echo "  \"node\": \"$NODE_IP\"," >> "$TMP_FILE"
echo "  \"scheduled_start_epoch\": $START_EPOCH," >> "$TMP_FILE"
echo "  \"real_start_epoch\": $REAL_START_EPOCH," >> "$TMP_FILE"
echo "  \"real_start_time\": \"$REAL_START_HUMAN\"," >> "$TMP_FILE"
echo "  \"iterations\": [" >> "$TMP_FILE"

ITER=0
END_TIME=$((REAL_START_EPOCH + DURATION))

while [ "$(date +%s)" -lt "$END_TIME" ]; do

    [ $ITER -gt 0 ] && echo "," >> "$TMP_FILE"

    echo "    {" >> "$TMP_FILE"
    echo "      \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"," >> "$TMP_FILE"
    echo "      \"epoch\": $(date +%s)," >> "$TMP_FILE"
    echo "      \"icmp_table\": [" >> "$TMP_FILE"

    FIRST=true

    ACTIVE_NEIGH=$(ip neigh show dev "$INTERFACE" | \
        awk '/REACHABLE|STALE|DELAY/ {print $1}' | \
        grep '^10\.0\.0\.')

    for IP in $ACTIVE_NEIGH; do

        PING=$(ping -I "$INTERFACE" -c 1 -W 1 "$IP" 2>/dev/null)

        if [ $? -eq 0 ]; then
            TTL=$(echo "$PING" | grep 'ttl=' | sed -E 's/.*ttl=([0-9]+).*/\1/')
            LAT=$(echo "$PING" | grep 'time=' | sed -E 's/.*time=([0-9\.]+).*/\1/')

            ROUTE_INFO=$(ip route get "$IP" dev "$INTERFACE" 2>/dev/null)
            NEXT_HOP=$(echo "$ROUTE_INFO" | awk '/via/ {print $3}')
            [ -z "$NEXT_HOP" ] && NEXT_HOP="DIRECT"

            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo "," >> "$TMP_FILE"
            fi

            echo "        {" >> "$TMP_FILE"
            echo "          \"IP\": \"$IP\"," >> "$TMP_FILE"
            echo "          \"TTL\": $TTL," >> "$TMP_FILE"
            echo "          \"LATENCY_MS\": $LAT," >> "$TMP_FILE"
            echo "          \"NEXT_HOP\": \"$NEXT_HOP\"" >> "$TMP_FILE"
            echo -n "        }" >> "$TMP_FILE"
        fi
    done

    echo "" >> "$TMP_FILE"
    echo "      ]" >> "$TMP_FILE"
    echo -n "    }" >> "$TMP_FILE"

    ITER=$((ITER+1))
    sleep $PING_INTERVAL
done

echo "" >> "$TMP_FILE"
echo "  ]" >> "$TMP_FILE"
echo "}" >> "$TMP_FILE"

mv "$TMP_FILE" "$LOG_JSON"
exit 0
EOF

chmod +x /usr/local/bin/mesh-icmp-json.sh

cat > /etc/systemd/system/mesh-icmp-json.service <<EOF
[Unit]
Description=Mesh ICMP JSON Logging (600s)
After=mesh-ibss.service
Wants=mesh-ibss.service

[Service]
Type=simple
ExecStart=/usr/local/bin/mesh-icmp-json.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl disable mesh-icmp-json.service

log "Service ICMP JSON prêt (manuel uniquement)"

step_ok
echo "Etape 15 OK."

############################################
# [16/17] Reset IP wlan0 après boot
############################################
echo "[16/17] Reset IP wlan0 après boot..."
step_start "[16/17] Reset IP wlan0 après boot..."

cat > /usr/local/bin/mesh-reset-ip.sh <<'EOF'
#!/bin/bash

LOG="/var/log/mesh-reset-ip.log"
echo "=== Mesh reset IP $(date) ===" >> "$LOG"

sleep 15

if [ ! -f /etc/mesh-id ]; then
    echo "Erreur : /etc/mesh-id introuvable" >> "$LOG"
    exit 1
fi
BOARD_ID=$(cat /etc/mesh-id)
IP="10.0.0.$BOARD_ID"
echo "BOARD_ID=$BOARD_ID, IP=$IP" >> "$LOG"

if ! ip link show wlan0 >/dev/null 2>&1; then
    echo "Erreur : wlan0 introuvable" >> "$LOG"
    exit 1
fi

echo "Flush IP wlan0" >> "$LOG"
sudo ip addr flush dev wlan0

sleep 5

echo "Remise IP $IP sur wlan0" >> "$LOG"
sudo ip addr add "${IP}/24" dev wlan0

ip link set wlan0 up

echo "=== Fin Mesh reset IP $(date) ===" >> "$LOG"
EOF

chmod +x /usr/local/bin/mesh-reset-ip.sh

cat > /etc/systemd/system/mesh-reset-ip.service <<EOF
[Unit]
Description=Reset IP wlan0 after boot
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mesh-reset-ip.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >>"$LOGFILE" 2>&1
systemctl enable mesh-reset-ip.service >>"$LOGFILE" 2>&1

step_ok
echo "Etape 16 OK."

############################################
# [17/17] Identité & logs
############################################
echo "[17/17] Finalisation..."
step_start "[17/17] Finalisation..."

echo "$BOARD_ID" > /etc/mesh-id
mkdir -p /var/log
touch /var/log/mesh-adhoc.log
step_ok

echo "========================================="
echo " INSTALLATION TERMINÉE"
echo " Node ID : $BOARD_ID"
echo " IP      : $IP"
echo " ESSID   : $ESSID"
echo "========================================="
echo ""
echo "Redémarrage direct"
sleep 30 
reboot