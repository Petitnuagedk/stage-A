############################################
# Raspberry Pi Zero W – Mesh IBSS (Bookworm)
# Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]
############################################

### --- Sécurité ---
if [ "$EUID" -ne 0 ]; then                                                              #Test pour vérifier que le scipt et bien exécuter en sudo 
  echo "Lancer ce script avec sudo"                                                     #Ecrit Lancer ce script avec sudo
  exit 1                                                                                #Sort du script si le scipt et pas en sudo
fi                                                                                      #Sortie de la boucle de vérification du mode sudo

if [ -z "$1" ]; then                                                                    #Test de vérification pour être sur de l'argument de lancemant Ex : Delta.sh 1
  echo "Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]"                             #Ecrit Usage: sudo bash setup-mesh-bookworm.sh [BOARD_ID]
  exit 1                                                                                #Sort du scipt si l'argument n'est pas respecté
fi                                                                                      #Sortie de la boucle si l'argument et vérifier

BOARD_ID="$1"                                                                           #Copie de la valeur contenue dans $1 dans un nouvelle variable BOARD_ID
IP="10.0.0.$BOARD_ID"                                                                   #Injection de la valeur contenu dans $BOARD_ID
ESSID="mesh-test"                                                                       #Nom réseau wifi (important qu'il ai tous le même)
CHANNEL_FREQ="2437"   # canal 6                                                         #Fréquence d'émition Wifi, canal 6 = equivalence en ipconfig (mal lu par iwconfig)
MAC_SUFFIX=$(printf "%02x" "$BOARD_ID")                                                 #Permet de transformer et de comparer les addr MAC 

echo "========================================="                                        #Ecrit =========================================
echo " Mesh Bookworm – Node $BOARD_ID ($IP)"                                            #Ecrit L'ip du noeux 
echo "========================================="                                        #Ecrit =========================================

############################################
# Logging & status
############################################
LOGFILE="/var/log/logmaj.txt"                                                            #Premition de renvoie dans le fichier logmaj.txt grâce à la commade >>"$LOGFILE"

mkdir -p /var/log                                                                        #Création des dossiers, même des dossier supérieur si ils existent pas afin de ne pas échoué
touch "$LOGFILE"                                                                         #Création d'un fichier contenue dans LOGFILE
chmod 644 "$LOGFILE"                                                                     #Attibution de droit d'accée suppérieur au fichier contenue dans LOGFILE

log() {                                                                                  #Appel au fichier log
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"                           #Affichage de la date dans le fichier de log
}

step_start() {                                                                           #Lance le démarrage d'une étape
  STEP_NAME="$1"                                                                         #Récupération de son nom
  STEP_ID="$2"                                                                           #Récupération de son ID 
  log "[STEP $STEP_ID] $STEP_NAME : START"                                               #Prépare le lancement des étapes suivantes
}

step_ok() {                                                                              #Affirme la fin d'une étape
  log "[STEP $STEP_ID] $STEP_NAME : OK"                                                  #Réecrie les argument du nom et de l'ID attraper dans le step_start
}

step_fail() {                                                                            #Amorce une fin propre à un programme 
  log "[STEP $STEP_ID] $STEP_NAME : FAIL"                                                #Affiche dans le fichier de log l'ID de l'étape bloquante
  log "Arrêt du script (erreur bloquante)"                                               #Affiche dans le fichier de log Arrêt du script (erreur bloquante)
  exit 1                                                                                 #Sortie du script
}

run() {                                                                                  #Déclare un fonction qui permet de logger une sortie du script  
  "$@" >>"$LOGFILE" 2>&1 || step_fail                                                    #Récupère les arguments contenue dans $@ et les stoks dans LOGFILE
}                                                                                        

############################################
# Systemd logging helpers
############################################
log_systemd_status() {                                                                   #Déclare une fonction qui permet de logger certaine action
  SERVICE="$1"                                                                           #Stock du nom de la variable

  {
    echo "------ systemd status : $SERVICE ------"                                       #Ecrit ------ systemd status : $SERVICE ------
    systemctl is-enabled "$SERVICE" 2>&1 || true                                         #Lance un service et log le lancement de ce service
    systemctl is-active  "$SERVICE" 2>&1 || true                                         #Vérification du lancement du service + affichage dans les log
    systemctl status     "$SERVICE" --no-pager -l 2>&1                                   #Vérification du status d'un service et notification dans les log 
    echo "---------------------------------------"                                       #Ecrit ---------------------------------------
  } >>"$LOGFILE"                                                                         #Direction du fichier de log
}

log "===== DÉMARRAGE INSTALLATION MESH ====="                                            #Ecrit ===== DÉMARRAGE INSTALLATION MESH =====  dans les logs
log "BOARD_ID=$BOARD_ID"                                                                 #Ecrit BOARD_ID=$BOARD_ID dans les logs

############################################
# [1/13] Paquets requis
############################################
echo "[1/13] Installation des dépendances..."                                            #Ecrit [1/13] Installation des dépendances...
step_start "[1/13] Installation des dépendances..."                                      #Ecrit dans les log [1/13] Installation des dépendances...


if [ -f /etc/apt/apt.conf.d/95proxy ]; then                                              #Crée une condition qui cherche à vérifier si le fichier 95proxy
    rm /etc/apt/apt.conf.d/95proxy                                                       #Si il existe il est supprimé
fi                                                                                       #Fin de la condition

cp 95proxy /etc/apt/apt.conf.d/                                                          #Copie du fichier 95proxy dans le répertoire /etc/apt/apt.conf.d/

date -s "06 FEB 2026 16:45:00"                                                           #Change la date en dur

apt update                                                                               #Fais une mise à jour des fichiers de base
apt install -y \                                                                         #Installation des instance mentionne si dessous
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
  arp-scan

echo "apt pleinement installé"                                                           #Ecrit apt pleinement installé

#cd /usr/src                                                                             #Partie réutilisable si vous voulez recherché la version online de Olsv2
#git clone https://github.com/OLSR/OONF.git
#cd OONF
#mkdir build
#cd build

echo "Etape 1 OK."                                                                        #Ecrit Etape 1 OK.
############################################
# [2/13] Désactivation NetworkManager / WPA
############################################
echo "[2/13] Désactivation services conflictuels..."                                      #Ecrit [2/13] Désactivation services conflictuels...
step_start "[2/13] Désactivation services conflictuels..."                                #Ecrit dans les logs [2/13] Désactivation services conflictuels...

#cd /home/rpi                                                                             #Partie à remettre en route si vous installez le repositorie online

log "[ACTION] Désactivation NetworkManager"                                               #Ecrit dans les logs [ACTION] Désactivation NetworkManager
systemctl disable --now NetworkManager >>"$LOGFILE" 2>&1|| true                           #Désactivation d'un service (NetworkManager) et affichage dans les logs
log_systemd_status NetworkManager                                                         #Passage de la mention dans les logs du service

log "[ACTION] Désactivation wpa_supplicant"                                               #Ecrit dans les logs [ACTION] Désactivation wpa_supplicant
systemctl disable --now wpa_supplicant >>"$LOGFILE"  2>&1 || true                         #Désactivation d'un service (wpa_supplicant) et affichage dans les logs
log_systemd_status wpa_supplicant                                                         #Passage de la mention dans les logs du service

echo "Etape 2 OK."                                                                        #Ecrit Etape2 OK.
############################################
# [3/13] Activation systemd-networkd
############################################
echo "[3/13] Activation systemd-networkd..."                                              #Ecrit [3/13] Activation systemd-networkd...
step_start "[3/13] Activation systemd-networkd..."                                        #Ecrit dans les logs [3/13] Activation systemd-networkd...

log "[ACTION] Désactivation systemd-networkd"                                             #Ecrit dans les logs [ACTION] Désactivation systemd-networkd
systemctl enable systemd-networkd >>"$LOGFILE" 2>&1                                       #Activation du service systemd-networkd et inscription dans les logs
systemctl start systemd-networkd >>"$LOGFILE" 2>&1                                        #Démarrage du service systemd-networkd et inscitpion dans les logs
log_systemd_status systemd-networkd                                                       #Passage de la mention dans les logs du service

echo "Etape 3 OK."                                                                        #Ecrit Etape 3 OK.
# ############################################
# # [4/13] Configuration réseau statique
# ############################################
# echo "[4/13] Configuration réseau wlan0..."
# step_start "[4/13] Configuration réseau wlan0..."
# 
# cat > /etc/systemd/network/10-mesh.network <<EOF
# [Match]
# Name=wlan0
#                                                                                         #Passage réactivable au besoin pour mettre l'ip static, possible déplacement recommandé en cas de réactivation
# [Network]
# Address=$IP/24
# ConfigureWithoutCarrier=yes
# EOF
# echo "Etape 4 OK."

############################################
# [5/13] Compilation et installation OLSRv2
############################################
echo "[5/13] Compilation OLSRv2 (OONF)..."                                                #Ecrit [5/13] Compilation OLSRv2 (OONF)...
step_start "[5/13] Compilation OLSRv2 (OONF)..."                                          #Ecrit dans les logs [5/13] Compilation OLSRv2 (OONF)...

# Déplacement des sources
cp -r OONF /usr/src/                                                                      #Copie du fichier contenant Olsrv2 du fichier ~ vers /usr/src/
sleep 10                                                                                  #Pause du script pendant 10s pour laissé le temps à la copie de ce faire
cd /usr/src                                                                               #Déplacement vers le répertoire /usr/src
cd OONF                                                                                   #Déplacement dans le répertoire OONF/
#mkdir build                                                                              #Construction car dans Olsv1 il n'y avais pas le dossier
cd build                                                                                  #Déplacement dans le dossier build

chown -R root:root /usr/src/OONF                                                          #Adminsation des droit root au répertoire OONF

# Build out-of-source
#mkdir -p build                                                                           #J'ai eu des problme de build du dossier à un moment, je laisse en cas
#cd /usr/src/OONF/build

echo "Configuration CMake..."                                                             #Ecrit Configuration CMake...
cmake .. -DCMAKE_INSTALL_PREFIX=/usr                                                      #Création de la liste d'installation 

echo "Compilation..."                                                                     #Ecrit Compliation...
make -j$(nproc)                                                                           #Lancement de la liste CMake, en gros lance la compilation avec tout les coeurs du CPU dispo avec le -j
echo "== Recherche binaire dans build =="                                                 #Ecrit == Recherche binaire dans build ==
find . -type f -name "olsrd2_dynamic" || step_fail                                        #Cherche le fichier olsrd2_dynamic et log si il ne le trouve pas

echo "Installation..."                                                                    #Ecrit Installation...
make install || step_fail                                                                 #Installation des fichiers compiler par le make et log si echoue

# Déclarer les libs OONF au linker
echo "/usr/lib/oonf" > /etc/ld.so.conf.d/oonf.conf                                        #Ecrit /usr/lib/oonf dans le fichier /etc/ld.so.conf.d/oonf.oonf pour donnée à oonf un chemin de recherche des librairies
ldconfig                                                                                  #Construction du cache de la bibliothèque dynamic

echo "Vérification binaire OLSRv2"                                                        #Ecrit Vérification binaire OLSRv2

ls -l /usr/sbin/olsrd2_dynamic || step_fail                                               #Regarde dans le dossier /usr/sbin/olsrd2_dynamic les fichiers présents et leurs droit d'exécution + log en cas d'échec 

# Vérification différée : warning seulement
if ldd /usr/sbin/olsrd2_dynamic | grep -q "not found"; then                               #Début d'une boucle qui vise à retourné un résultat en fonction de si les librairies sont bien crée au bon endroit ou pas.
  log "Libs non résolues avant reboot"                                                    #Ecrit dans les log Libs non résolues avant reboot
else                                                                                      #Sinon
  log "Toutes les libs sont correctement résolues"                                        #Ecrit dans les log Toutes les libs sont correctement résolues
fi                                                                                        #Fin de boucle

echo "Etape 5 OK."                                                                        #Ecrit Etape 5 OK.

############################################
# [6/13] Configuration OLSRv2
############################################
echo "[6/13] Configuration OLSRv2..."                                                     #Ecrit [6/13] Configuration OLSRv2...
step_start "[6/13] Configuration OLSRv2..."                                               #Ecrit dans les logs [6/13] Configuration OLSRv2...

mkdir -p /etc/olsrd2                                                                      #Création du répertoire olsrd2 le tout sans affichage de message d'erreur même si le fichier existe

cat > /etc/olsrd2/olsrd2.conf <<EOF                                                       #Lecture du contenue de /etc/olsrd2/olsrd2.conf et écriture de tout ce qui suit
# OLSRv2 minimal config for Debian ad-hoc wlan0

# Interfaces
Interface "wlan0"                                                                         #Déclaration de gestion de l'interface par Olsrv2
{      
    Type = mesh                                                                           #Indication du type d'interface mesh IBSS
    HelloInterval = 2.0                                                                   #Temps entre les messages d'envoie de Olrv2 qui sert à la création des routes (marche archi pas)
    TcInterval = 5.0                                                                      #Temps d'envoie du message TC qui permet de propager la topologie réseaux (marche surment pas)
}

# Plugins
Plugin "txtinfo.so"                                                                       #Active le plugin "txtinfo" fourni avec OLSRv2
{
    Port = 2006                                                                           #Le plugin écoute sur le port 2006
    Accept = "0.0.0.0"                                                                    #Autorise les connexions depuis toutes les IP
}

# Logging
LogLevel = info                                                                           #Détaillage des informations fournis dans les logs
EOF                                                                                       #Fin de la période d'écriture

echo "Configuration OLSRv2 prête"                                                         #Ecrit Configuration OLSRv2 prête (J'avais une étape intermédiaire entre ce message et le suivant il y as quelque temps dsl)
echo "Etape 6 OK."                                                                        #Ecrit Etape 6 OK.

############################################
# [7/13] Exclure wlan0 de systemd-networkd
############################################
echo "[7/13] Exclusion de wlan0 de systemd-networkd..."                                   #Ecrit [7/13] Exclusion de wlan0 de systemd-networkd...
step_start "[7/13] Exclusion de wlan0 de systemd-networkd..."                             #Ecrit dans les logs [7/13] Exclusion de wlan0 de systemd-networkd...

# Supprimer toute configuration réseau existante pour wlan0
rm -f /etc/systemd/network/*wlan0*.                                                       #Suppressions de toute les fichier qui on dans leurs nom wlan0
rm -f /etc/systemd/network/10-mesh.network                                                #Suppressions d'un fichier qui s'appel 10-mesh.network

# Créer une règle pour rendre wlan0 unmanaged
rm -f /etc/systemd/network/99-ignore-wlan0.link                                           #Suppressions d'un fichier qui s'appel 99-ignore-wlan0.link

cat > /etc/systemd/network/99-ignore-wlan0.link <<EOF                                     #Lecture du contenue de /etc/systemd/network/99-ignore-wlan0.link et écriture de tout ce qui suit
[Match]
OriginalName=wlan0                                                                        #Définition de l'interface

[Link]
Unmanaged=yes                                                                             #Ce message indique à systemd-networkd de ne pas intervenir sur cette interface
LinkLocalAddressing=no                                                                    #Doit normalement interdir l'addressage ipv4 (ne marche pas)
DHCP=no                                                                                   #En cas que systemd-networkd ne soit pas étein, cela l'empêche de prendre une addr IP en DHCP
IPv6AcceptRA=no                                                                           #Bloque normalment l'addressage ipv6 via les Router Advertisements
EOF                                                                                       #Sortie du cat

# Redémarrer systemd-networkd pour appliquer la règle
log "[ACTION] Restart systemd-networkd"                                                   #Ecrit dans les logs [ACTION] Restart systemd-networkd
systemctl restart systemd-networkd >>"$LOGFILE" 2>&1                                      #Redémarrage du service systemd-networkd et envoie de l'info dans les logs
log_systemd_status systemd-networkd                                                       #Ecrit un statu du service redémarrer

echo "Wlan0 est maintenant unmanaged par systemd-networkd"                                #Ecrit Wlan0 est maintenant unmanaged par systemd-networkd
echo "Etape 7 OK."                                                                        #Ecrit Etape 7 OK.

############################################
# [8/13] Passage en IP fiable
############################################
echo "[8/13] Script IBSS..."                                                              #Ecrit [8/13] Script IBSS...
step_start "[8/13] Script IBSS..."                                                        #Ecrit dans les logs [8/13] Script IBSS...

cat > /etc/sysctl.d/99-mesh-no-ipv4ll.conf <<EOF                                          #Lecture du contenue de /etc/sysctl.d/99-mesh-no-ipv4ll.conf et écriture de tout ce qui suit
net.ipv4.conf.all.autoconf=0                                                              #Désactivation de l'ipv4 automatique (pour essayer d'enlever 169.254.x.x, ça ne marche pas)
net.ipv4.conf.default.autoconf=0                                                          #Même choses que au dessus mais pour le future (à chaque recréation de l'interface, marche pas non plus)
net.ipv4.conf.wlan0.autoconf=0                                                            #Désactive pas défault l'auto-configuration de l'interface Wlan0
net.ipv4.conf.all.accept_local=0                                                          #Interdit au kernel d'accepter les paquets destinée à ces addresse personelle (Ex: 169.254.x.x)
net.ipv4.conf.default.accept_local=0                                                      #Applicationd de la même règle mais pour les interfaces future
EOF

sysctl --system                                                                           #Paramètre permettant de lire ou modifier des paramètres du noyaux à la volée. Grâce à lui que les paramètres sont appliqué au noyaux.

echo "Etape 8 OK."                                                                        #Ecrit Etape 8 OK.

############################################
# [9/13] Script IBSS – robuste avec logs
############################################
echo "[9/13] Script IBSS..."                                                              #Ecrit [9/13] Script IBSS...
step_start "[9/13] Script IBSS..."                                                        #Ecrit dans les logs [9/13] Script IBSS...

cat > /usr/local/bin/setup-adhoc.sh <<'EOF'                                               #Lecture du contenue de /usr/local/bin/setup-adhoc.sh et écriture de tout ce qui suit
#!/bin/bash

LOGFILE="/var/log/mesh-adhoc.log"                                                         #Création du fichier de log
exec >> "$LOGFILE" 2>&1                                                                   #Redirection de toute les action logger ou les erreurs dans ce fichier

echo "=== Mesh start $(date) ==="                                                         #Ecrit === Mesh start $(date) ===

############################################
# Sécurité : tuer wpa_supplicant
############################################
systemctl stop wpa_supplicant 2>/dev/null || true                                         #Stop wpa_supplicant avec true pour évité que si elle ne s'exécute pas tout crash
pkill wpa_supplicant 2>/dev/null || true                                                  #Arrêt de wpa_supplicant avec true

############################################
# Attente wlan0
############################################
for i in {1..10}; do                                                                      #Création de la boucle
  ip link show wlan0 >/dev/null 2>&1 && break                                             #Vérifie si l'interface Wlan0 existe toujours si oui, sorti de la boucle
  echo " Attente wlan0..."                                                                #Ecrit Attente wlan0...
  sleep 1                                                                                 #Attente d'une segonde
done                                                                                      #fin de la boucle 

############################################
# Paramètres mesh
############################################
BOARD_ID=$(cat /etc/mesh-id)                                                              #Attribution du numéro de l'interface à BOARD_ID
IP="10.0.0.$BOARD_ID"                                                                     #Complétion de l'addresse IP
ESSID="mesh-test"                                                                         #Donne un nom au wifi
CHANNEL_FREQ="2437"                                                                       #Définition de la fréquence du wifi, (2.4 GHz)

############################################
# Reset contrôlé
############################################
ip link set wlan0 down                                                                    #Passage de l'interface Wlan0 en état éteint
sleep 2                                                                                   #Attente de 2 secondes

iw dev wlan0 set type ibss || {                                                           #Tentative de passé l'interface wlan0 en IBSS
  echo " set type ibss failed"                                                            #Si la commande échoue alors il y as ce message qui s'affiche
  exit 1                                                                                  #Et le scipte et quitté
}

ip link set wlan0 up                                                                      #Tentative de rallumage de l'interface
sleep 2                                                                                   #Attente de 2 secondes

############################################
# JOIN IBSS UNIQUE (CRITIQUE)
############################################
iw dev wlan0 ibss join "$ESSID" "$CHANNEL_FREQ" fixed-freq || {                           #Cette commande vise à appliqué tout les paramètres que l'on as mis en place plustôt
  echo " ibss join failed"                                                                #Si la commande echoue écrit ibss join failed 
  exit 1                                                                                  #Et donc sortir du script
}
ip link set wlan0 up                                                                      #Encore une tentative de rallumage de l'interaface
sleep 2                                                                                   #Attente de 2 secondes
ip addr flush dev wlan0                                                                   #Suppression de toute les interfaces de l'interface Wlan0
# IP statique finale
ip addr add "${IP}/24" dev wlan0                                                          #Mise en place de l'Ip 10.0.0.x/24 sur Wlan0

############################################
# Attente vraie stabilisation IBSS
############################################
for i in {1..15}; do                                                                      #Mise en place d'une boucle
  if iw dev wlan0 info | grep -q "type IBSS"; then                                        #Interogation du driver wifi afin de savoir qui à quel valeur | ensuite, récupération de type IBSS
    echo " IBSS stable"                                                                   #Ecrit IBSS stable
    break                                                                                 #Si tout est ok, sortie de la boucle
  fi                                                                                      #Fin de l'interrogaton du driver wifi
  echo " Attente stabilisation IBSS..."                                                   #Ecrit Attente stabilisation IBSS...
  sleep 1                                                                                 #Attente d'une seconde
done                                                                                      #Fin de la boucle 

############################################
# Nettoyage IP + blocage IPv4LL
############################################

# Bloquer link-local et config auto IP au niveau kernel à chaud (Block important de fou) (Si vous arrivez à le faire marché)

sysctl -w net.ipv4.conf.wlan0.use_tempaddr=0 >/dev/null                                   #Cette commande empêche les addresse IP temporaire (169.254.x.x) sauf que askip inactif car que pour IPv6
sysctl -w net.ipv4.conf.wlan0.accept_local=0 >/dev/null                                   #Cette commande permet d'évité les tempêtes de paquets (équivalent spaning-tree) en n'acceptant les paquets émis localement
sysctl -w net.ipv4.conf.wlan0.autoconf=0 >/dev/null                                       #Encore une commande qui doit arréter les IP (169.254.x.x) en blocant le protocol IPv4LL
sysctl -w net.ipv4.conf.wlan0.arp_ignore=1 >/dev/null                                     #Cette commande agis comme un filtre vers les request ARP afin d'évité les confusions d'interface et les conflit IP 

############################################
# IP statique finale
############################################
ip addr add "${IP}/24" dev wlan0                                                          #Nouvelle tentatice d'attibution de l'addr IP (10.0.0.x)   

############################################
# Vérification
############################################
if ip addr show wlan0 | grep -q "$IP"; then                                               #Affichage de toute les ip de Wlan0 le grep cherche l'ip 10.0.0.x
    echo " wlan0 prêt avec IP ${IP}"                                                      #Ecrit wlan0 prêt avec IP ${IP}
else                                                                                      #Sinon
    echo " [WARN] IBSS OK mais IP non appliquée"                                          #Ecrit [WARN] IBSS OK mais IP non appliquée"
fi                                                                                        #Fin de séquence

ip link set wlan0 up                                                                      #Encore une tentative de UP d'interface

EOF                                                                                       #Fin de ce scipte titanesquement plein de tentative qui échoue

echo "$(ip addr show wlan0)"                                                              #Affichage de l'interface Wlan0 (DOWN)

chmod +x /usr/local/bin/setup-adhoc.sh                                                    #Augmentation des permitions de setup-adhoc.sh
echo " Script IBSS prêt (logs + IP garantis)"                                             #Ecrit Script IBSS prêt (logs+IP garantis)

echo "Etape 9 OK."                                                                        #Ecrit Etape 9 OK.

############################################
# [10/13] Service systemd – IBSS
############################################
echo "[10/13] Service systemd IBSS..."                                                    #Ecrit [10/13] Service systemd IBSS...
step_start "[10/13] Service systemd IBSS..."                                              #Ecrit dans les logs [10/13] Service systemd IBSS...

cat > /etc/systemd/system/mesh-ibss.service <<EOF                                         #Lecture du contenue de /etc/systemd/system/mesh-ibss.service et écriture de tout ce qui suit
[Unit]
Description=Mesh IBSS Network (wlan0)                                                     #Prise d'information du status de mesh-ibss.service
After=sys-subsystem-net-devices-wlan0.device                                              #Demande de démarage de systemd après l'allumage de Wlan0
Requires=sys-subsystem-net-devices-wlan0.device                                           #Si l'interface n'existe pas, ce service ne marche pas 

[Service]                                                                                 #Chatgpt aime pas cette config, à revoir possiblement
Type=simple                                                                               #Avec cette exécution, le service et imaginé en lecture dés le démmarage
ExecStart=/usr/local/bin/setup-adhoc.sh                                                   #Lance le scipt setup-adhoc.sh
Restart=on-failure                                                                        #Permet de relancé setup-ashoc.sh même si il crash
RestartSec=2                                                                              #Attend 2 secondes avant de relancé le script
RemainAfterExit=yes                                                                       #Parle à systemd et lui dis que le service et toujours en activit pour évité qu'il offre une addr en (169.254.x.x)(marche pas)

[Install]
WantedBy=multi-user.target                                                                #Active le service au boot
EOF

echo "$(ip addr show wlan0)"                                                              #Prise d'info sur le statue réseaux (DOWN)

log "[ACTION] systemd daemon-reload"                                                      #Ecriture dans les logs [ACTION] systemd daemon-reload
systemctl daemon-reload >>"$LOGFILE" 2>&1                                                 #Cette fonction oblige le systemd à lire et appliqué les modifications apportés à un service
{
  echo "------ systemd daemon-reload ------"                                              #Ecrit ------ systemd daemon-reload ------
  systemctl show --property=Version                                                       #affichage de la version exact de systemd
  echo "----------------------------------"                                               #Ecrit ----------------------------------
} >>"$LOGFILE"                                                                            #Fin de ce qui est écrit dans le fichier LOGFILE

log "[ACTION] Activation mesh-ibss.service"                                               #Ecrit dans les logs [ACTION] Activation mesh-ibss.service
systemctl enable mesh-ibss.service >>"$LOGFILE" 2>&1                                      #Cette commande permet d'appliqué mesh-ibss.service au démarrage
log_systemd_status mesh-ibss.service                                                      #Ecrit le status de mesh-ibss.service dans les logs

echo "$(ip addr show wlan0)"                                                              #Prise d'info sur le statue réseaux (DOWN) 

echo "Etape 10 OK."                                                                       #Ecrit Etape 10 OK.

############################################
# [11/13] Ping broadcast périodique (FIXE)
############################################
echo "[11/13] Ping broadcast mesh (fixe)..."                                              #Ecrit [11/13] Ping broadcast mesh (fixe)...
step_start "[11/13] Ping broadcast mesh (fixe)..."                                        #Ecrit dans les logs [11/13] Ping broadcast mesh (fixe)...

cat > /usr/local/bin/mesh-broadcast-ping.sh <<'EOF'                                       #Lecture du contenue de /usr/local/bin/mesh-broadcast-ping.sh et écriture de tout ce qui suit
#!/bin/bash

INTERFACE="wlan0"                                                                         #Nom de l'interface du réseaux
BROADCAST_IP="10.0.0.255"                                                                 #Adrresse IP de Broadcast
INTERVAL=10                                                                               #Intervalle entre 2 pings

echo "=== Mesh broadcast ping started $(date) ==="                                        #Ecrit === Mesh broadcast ping started $(date) ===
echo "Interface  : $INTERFACE"                                                            #Ecrit Interface  : $INTERFACE
echo "Broadcast  : $BROADCAST_IP"                                                         #Ecrit Broadcast  : $BROADCAST_IP
echo "Intervalle : ${INTERVAL}s"                                                          #Ecrit Intervalle : ${INTERVAL}s

# Attendre que l’interface soit UP
while true; do                                                                            #Mise en place d'une boucle infini
  if ip link show "$INTERFACE" | grep -q "UP"; then                                       #Recherche de l'IP et d'être sur que l'interface soit UP
    break                                                                                 #Si elle est UP alors on peu sortir 
  fi                                                                                      #Fin d'exécution
  sleep 1                                                                                 #Attente d'une seconde
done                                                                                      #Fin de boucle

# Autoriser ICMP broadcast (indispensable)
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=0 >/dev/null                               #Autorisation de réception et d'envoie de ping broadcast

# Boucle ping broadcast
while true; do                                                                            #Mise en place d'une nouvelle boucle infini
  ping -b -c 1 -W 1 "$BROADCAST_IP" >/dev/null 2>&1                                       #Envoie d'un ping vers l'addr de broadcast
  sleep "$INTERVAL"                                                                       #Attente de la prochaine exécution, 10s pour le moment
done                                                                                      #Fin de boucle
EOF

chmod +x /usr/local/bin/mesh-broadcast-ping.sh                                            #Attibution de droit suppérieur à mesh-broadcast-ping.sh

cat > /etc/systemd/system/mesh-broadcast-ping.service <<EOF                               #Lecture du contenue de /etc/systemd/system/mesh-broadcast-ping.service  et écriture de tout ce qui suit
[Unit]
Description=Mesh Broadcast Ping (10.0.0.255)                                              #Desciption du service
After=mesh-ibss.service                                                                   #Mise en service en suivant du service mesh-ibss.service
Wants=mesh-ibss.service                                                                   #Fichier requis mesh-ibss.service

[Service]
Type=simple                                                                               #Service qui tourne en arrire plan sans pause 
ExecStart=/usr/local/bin/mesh-broadcast-ping.sh                                           #Indique que le service soit être lu au démarrage
Restart=always                                                                            #Rappel que c'est une boucle infini
RestartSec=5                                                                              #Le service redémarre automatique même si il crash ou que l'on redémarre la puce

[Install]
WantedBy=multi-user.target                                                                #Le service sera exécuter peu importe la personne qui cherche à ce connecter à la puce 
EOF

systemctl daemon-reload                                                                   #Recharge systemd
systemctl enable mesh-broadcast-ping.service >>"$LOGFILE" 2>&1                            #Permet d'activer le service au démarage
systemctl start mesh-broadcast-ping.service  >>"$LOGFILE" 2>&1                            #Permet de lancé directment le service de ping broadcast, (peu marché sans redémarrage si IP 10.0.0.x)

echo "$(ip addr show wlan0)"                                                              #Prise d'info sur le statue réseaux (DOWN) 

step_ok                                                                                   #Informe les logs que l'étape et bien fini
echo "Etape 11 OK."                                                                       #Ecrit Etape 11 OK.

############################################
# [12/13] Service systemd – OLSRv2
############################################
echo "[12/13] Service systemd OLSRv2..."                                                  #Ecrit [12/13] Service systemd OLSRv2...
step_start "[12/13] Service systemd OLSRv2..."                                            #Ecrit dans les logs [12/13] Service systemd OLSRv2...

cat > /etc/systemd/system/olsrv2.service <<EOF                                            #Lecture du contenue de /etc/systemd/system/olsrv2.service et écriture de tout ce qui suit
[Unit]
Description=OLSRv2 Routing Daemon (OONF)                                                  #Desciption du service
After=mesh-ibss.service                                                                   #Mise en service en suivant du service mesh-ibss.service
Wants=mesh-ibss.service                                                                   #Fichier requis mesh-ibss.service

[Service]
Type=simple                                                                               #Et considéré comme actif dés que ExexStart le lance
ExecStart=/usr/sbin/olsrd2_dynamic \                                                      #Lance le daemon (service) Olsrv2

# Attente IP SANS FAIL systemd
ExecStartPost=/bin/bash -c '\                                                             #Commande à exécuter après le démarrage
for i in {1..30}; do \                                                                    #Début de la boucle
  if ip addr show wlan0 | grep -q "10.0.0."; then \                                       #Regarde si l'interface Wlan0 possède bien une IP en 10.0.0.x
    echo "IP 10.0.0.x détectée sur wlan0"; \                                              #Ecrit IP 10.0.0.x détectée sur wlan0
    exit 0; \                                                                             #Sorti instantané de la boucle
  fi; \                                                                                   #Fin de la séquence
  echo "Attente IP mesh ($i/30)..."; \                                                    #Si pas d'addresse 10.0.0.x écrit Attete IP mesh (1/30)...
  sleep 1; \                                                                              #Attente d'une seconde
done; \                                                                                   #Sortie de la boucle
echo "WARN: OLSRv2 lancé sans IP 10.0.0.x"; \                                             #Ecrit WARN: OLSRv2 lancé sans IP 10.0.0.x
exit 0'                                                                                   #Sortie de la boucle

Restart=on-failure                                                                        #Relancé en cas d'echec
RestartSec=3                                                                              #Au bout de 3 secondes
StandardOutput=journal                                                                    #Les messages des tentaive seront visible dans le journalctl
StandardError=journal                                                                     #Les messages d'erreur seront visible dans le journalctl

[Install]
WantedBy=multi-user.target                                                                #Oblige le service à ce mettre en place avant l'exécution de multi-user.target
EOF

log "[ACTION] systemd daemon-reload"                                                      #Ecrit dans les logs [ACTION] systemd daemon-reload 
systemctl daemon-reload >>"$LOGFILE" 2>&1                                                 #Redémmarage du service daemon-reload et affichage du status dans les logs 

log "[ACTION] Activation olsrv2.service"                                                  #Ecrit dans les logs [ACTION] Activation olsrv2.service
systemctl enable olsrv2.service >>"$LOGFILE" 2>&1                                         #Lancement du service olsrv2 et affichage du status dans les logs

log "[ACTION] Démarrage olsrv2.service"                                                   #Ecrit dans les logs [ACTION] Démarrage olsrv2.service
systemctl start olsrv2.service >>"$LOGFILE" 2>&1                                          #Démarrage du service olsrv2 et affichage du status dans les logs

if ! systemctl is-active --quiet olsrv2.service; then                                     #Vérification du status de olsrv2 et inversion des résultat obtenue afin de rentrée dans la boucle uniquement si là condition échoue
  log "olsrv2.service FAILED TO START"                                                    #Ecrit dans les logs olsrv2.service FAILED TO START
  log_systemd_status olsrv2.service                                                       #Affiche un status de olsrv2 dans les logs 
  exit 1                                                                                  #Sorti du script
fi                                                                                        #Fin de la condition

log "olsrv2.service démarré avec succès"                                                  #Ecrit dans les logs que olsrv2.service démarré avec succès
log_systemd_status olsrv2.service                                                         #Ectit dans les logs le status de olsrv2.service

echo "$(ip addr show wlan0)"                                                              #Prise d'info sur le statue réseaux (DOWN) 

step_ok                                                                                   #Notification dans les logs que l'étape et fini
echo "Etape 12 OK."                                                                       #Ecrit Etape 12 OK.

############################################
# [13/13] Identité & logs
############################################
echo "[13/13] Finalisation..."                                                             #Ecrit [13/13] Finalisation...
step_start "[13/13] Finalisation..."                                                       #Ecrit dans les logs [13/13] Finalisation...

echo "$BOARD_ID" > /etc/mesh-id                                                            #Ecrit l'ip contenu dans le BOARD_ID du fichier /etc/mesh-id 
mkdir -p /var/log                                                                          #Création de dossier et de tout ces sous répertoires /var/log
touch /var/log/mesh-adhoc.log                                                              #Création du fichier mesh-adhoc.log
step_ok                                                                                    #Notification dans les logs que l'étape et fini

echo "========================================="                                           #Ecrit =========================================
echo " INSTALLATION TERMINÉE"                                                              #Ecrit INSTALLATION TERMINÉE
echo " Node ID : $BOARD_ID"                                                                #Ecrit Node ID : $BOARD_ID
echo " IP      : $IP"                                                                      #Ecrit IP      : $IP
echo " ESSID   : $ESSID"                                                                   #Ecrit ESSID   : $ESSID
echo "========================================="                                           #Ecrit =========================================
echo ""                                                                                    #Ecrit
echo "Redémarre maintenant : sudo reboot"                                                  #Ecrit Redémarre maintenant : sudo reboot