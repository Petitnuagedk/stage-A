#!/bin/bash
set -e

LOGFILE="/var/log/mesh-adhoc.log"
TARGET_FILE="/var/log/mesh-targets.txt"

# Tout écrire dans mesh-adhoc.log
exec >> "$LOGFILE" 2>&1

echo "=== Scan réseau start $(date) ==="

# Nettoyage anciens résultats
> "$TARGET_FILE"

echo "Scan nmap 169.254.0.0/16..."
nmap -sn 169.254.0.0/16 | \
grep "Nmap scan report for" | \
awk '{print $5}' > "$TARGET_FILE"

echo "Machines détectées :"
cat "$TARGET_FILE"

echo "=== Scan terminé $(date) ==="
echo "Début des ping toutes les 10s"

# Boucle infinie de ping
while true; do
    while read -r IP; do
        [ -z "$IP" ] && continue

        if ping -c 1 -W 1 "$IP" >/dev/null 2>&1; then
            echo "$(date) PING OK $IP"
        else
            echo "$(date) PING FAIL $IP"
        fi
    done < "$TARGET_FILE"

    sleep 10
done
