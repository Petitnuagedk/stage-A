#!/bin/bash

# Raspberry Pi Zero W - Ad-hoc Mesh Network Setup Script
# This script installs OLSR, configures ad-hoc networking, and sets up logging
# Run with: sudo bash setup-mesh.sh [BOARD_ID]
# Example: sudo bash setup-mesh.sh 1  (for Board A with IP 10.0.0.1)
#          sudo bash setup-mesh.sh 2  (for Board B with IP 10.0.0.2)

set -e  # Exit on any error

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Get board ID from argument
if [ -z "$1" ]; then
    echo "ERROR: Please specify board ID (1, 2, 3, etc.)"
    echo "Usage: sudo bash setup-mesh.sh [BOARD_ID]"
    echo "Example: sudo bash setup-mesh.sh 1"
    exit 1
fi

BOARD_ID=$1
BOARD_IP="10.0.0.$BOARD_ID"

echo "=========================================="
echo "Raspberry Pi Mesh Network Setup"
echo "=========================================="
echo "Board ID: $BOARD_ID"
echo "IP Address: $BOARD_IP"
echo "=========================================="
echo ""

# Step 1: Update and install dependencies
echo "[1/8] Installing build dependencies..."
apt-get update
apt-get install -y build-essential iw wireless-tools flex bison git net-tools netcat-openbsd

# Step 2: Clone and build OLSR
echo "[2/8] Cloning OLSR from GitHub..."
cd /tmp
if [ -d "olsrd" ]; then
    rm -rf olsrd
fi
git clone https://github.com/OLSR/olsrd.git
cd olsrd

echo "[3/8] Building OLSR (this may take a few minutes)..."
make

echo "[4/8] Installing OLSR..."
make install

# Verify installation
if ! command -v olsrd &> /dev/null; then
    echo "ERROR: OLSR installation failed!"
    exit 1
fi

echo "OLSR installed successfully: $(olsrd -v | head -n1)"

# Step 3: Create OLSR configuration
echo "[5/8] Creating OLSR configuration..."
mkdir -p /etc/olsrd

cat > /etc/olsrd/olsrd.conf << 'EOF'
# OLSR configuration for mesh network
DebugLevel 2

IpVersion 4

# Load txtinfo plugin for monitoring
#LoadPlugin "olsrd_txtinfo.so.1.1"
#{
#    PlParam "port" "2006"
#    PlParam "Accept" "127.0.0.1"
#}

# Configure mesh interface
Interface "wlan0"
{
    Mode "mesh"
    HelloInterval 2.0
    HelloValidityTime 20.0
    TcInterval 5.0
    TcValidityTime 30.0
    MidInterval 5.0
    MidValidityTime 30.0
    HnaInterval 5.0
    HnaValidityTime 15.0
}
EOF

echo "OLSR configuration created at /etc/olsrd/olsrd.conf"


# Step 4: Configure network interface
echo "[6/8] Configuring network interface..."
mkdir -p /etc/network/interfaces.d

cat > /etc/network/interfaces.d/adhoc << EOF
auto wlan0
iface wlan0 inet static
    address $BOARD_IP
    netmask 255.255.255.0
    wireless-mode ad-hoc
    wireless-essid mesh-test
    wireless-channel 6
EOF

echo "Network interface configured with IP: $BOARD_IP"

# Step 5: Create monitoring/logging script
echo "[7/8] Creating mesh monitoring script..."
cat > /usr/local/bin/mesh-test.sh << 'SCRIPT_EOF'
#!/bin/bash

LOG_DIR="/home/pi/mesh-logs"
mkdir -p $LOG_DIR

LOG_FILE="$LOG_DIR/mesh-test-$(date +%Y%m%d-%H%M%S).log"

echo "=== Mesh Network Test Started at $(date) ===" | tee -a $LOG_FILE

# Wait for system to fully boot
echo "Waiting 30 seconds for system boot..." | tee -a $LOG_FILE
sleep 30

echo "=== Network Interface Status ===" | tee -a $LOG_FILE
ifconfig wlan0 | tee -a $LOG_FILE
iwconfig wlan0 | tee -a $LOG_FILE

echo "" | tee -a $LOG_FILE
echo "=== Starting OLSR ===" | tee -a $LOG_FILE
olsrd -i wlan0 -d 1 >> $LOG_FILE 2>&1 &
OLSR_PID=$!
echo "OLSR started with PID: $OLSR_PID" | tee -a $LOG_FILE

# Wait for OLSR to stabilize
echo "Waiting 45 seconds for OLSR to stabilize..." | tee -a $LOG_FILE
sleep 45

# Determine target IP for ping (ping all other nodes)
MY_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "My IP: $MY_IP" | tee -a $LOG_FILE

# Main monitoring loop - run for 10 minutes (40 checks)
for i in {1..40}; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "" | tee -a $LOG_FILE
    echo "=== Check $i/40 at $TIMESTAMP ===" | tee -a $LOG_FILE
    
    # Check routing table
    echo "--- Routing Table ---" | tee -a $LOG_FILE
    ip route | tee -a $LOG_FILE
    
    # Check OLSR neighbors
    echo "--- OLSR Links ---" | tee -a $LOG_FILE
    echo "/links" | nc -w 2 127.0.0.1 2006 2>/dev/null | tee -a $LOG_FILE
    
    # Check OLSR topology
    echo "--- OLSR Topology ---" | tee -a $LOG_FILE
    echo "/topology" | nc -w 2 127.0.0.1 2006 2>/dev/null | tee -a $LOG_FILE
    
    # Ping test to other boards
    echo "--- Ping Tests ---" | tee -a $LOG_FILE
    for TARGET_IP in 10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4; do
        if [ "$TARGET_IP" != "$MY_IP" ]; then
            echo "Pinging $TARGET_IP..." | tee -a $LOG_FILE
            ping -c 3 -W 2 $TARGET_IP 2>&1 | tee -a $LOG_FILE
        fi
    done
    
    # Check WiFi signal
    echo "--- WiFi Status ---" | tee -a $LOG_FILE
    iw dev wlan0 link 2>&1 | tee -a $LOG_FILE
    iw dev wlan0 station dump 2>&1 | tee -a $LOG_FILE
    
    # LED indicator (fast blink = connected, slow = not connected)
    PING_SUCCESS=false
    for TARGET_IP in 10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4; do
        if [ "$TARGET_IP" != "$MY_IP" ]; then
            if ping -c 1 -W 1 $TARGET_IP &>/dev/null; then
                PING_SUCCESS=true
                break
            fi
        fi
    done
    
    if [ "$PING_SUCCESS" = true ]; then
        # Success - heartbeat pattern
        echo heartbeat > /sys/class/leds/led0/trigger 2>/dev/null || true
    else
        # Failure - slow blink
        echo timer > /sys/class/leds/led0/trigger 2>/dev/null || true
        echo 1000 > /sys/class/leds/led0/delay_on 2>/dev/null || true
        echo 1000 > /sys/class/leds/led0/delay_off 2>/dev/null || true
    fi
    
    # Wait 15 seconds before next check
    sleep 15
done

echo "" | tee -a $LOG_FILE
echo "=== Initial Test Completed at $(date) ===" | tee -a $LOG_FILE
echo "Total runtime: 10 minutes (40 checks)" | tee -a $LOG_FILE
echo "Continuing monitoring in background..." | tee -a $LOG_FILE

# Continue monitoring every minute
while true; do
    sleep 60
    echo "--- Status at $(date) ---" >> $LOG_FILE
    echo "/links" | nc -w 2 127.0.0.1 2006 2>/dev/null >> $LOG_FILE
    
    # Quick ping test
    for TARGET_IP in 10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4; do
        if [ "$TARGET_IP" != "$MY_IP" ]; then
            ping -c 1 -W 1 $TARGET_IP >> $LOG_FILE 2>&1
        fi
    done
done
SCRIPT_EOF

chmod +x /usr/local/bin/mesh-test.sh
echo "Monitoring script created at /usr/local/bin/mesh-test.sh"

# Step 8: Create systemd service for mesh network (runs on boot)
echo "[8/8] Creating systemd service for boot-time configuration..."

# Create the ad-hoc setup script
cat > /usr/local/bin/setup-adhoc.sh << ADHOC_EOF
#!/bin/bash

# Log everything
exec >> /var/log/mesh-adhoc.log 2>&1
echo "=== Ad-hoc setup started at \$(date) ==="

# Wait a bit for system to settle
sleep 5

# Stop conflicting services
systemctl stop wpa_supplicant
systemctl disable wpa_supplicant
systemctl stop dhcpcd

# Configure ad-hoc
ifconfig wlan0 down
iwconfig wlan0 mode ad-hoc
iwconfig wlan0 essid "mesh-test"
iwconfig wlan0 channel 6
ifconfig wlan0 $BOARD_IP netmask 255.255.255.0
ifconfig wlan0 up

echo "Ad-hoc configured at \$(date)"
iwconfig wlan0
ifconfig wlan0

# Start monitoring script
/usr/local/bin/mesh-test.sh &

echo "=== Ad-hoc setup completed at \$(date) ==="
ADHOC_EOF

chmod +x /usr/local/bin/setup-adhoc.sh

# Create systemd service
cat > /etc/systemd/system/mesh-adhoc.service << 'EOF'
[Unit]
Description=Mesh Ad-hoc Network Configuration
After=multi-user.target
Before=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/setup-adhoc.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable service
systemctl daemon-reload
systemctl enable mesh-adhoc.service

echo "Systemd service created and enabled"
echo "Check boot logs with: cat /var/log/mesh-adhoc.log"

echo "[9/8] Finalizing..."

# Create board identifier file
mkdir /home/pi
touch /home/pi/BOARD_$BOARD_ID
chown hugol:hugol /home/pi/BOARD_$BOARD_ID

# Create log directory
mkdir -p /home/pi/mesh-logs
chown hugol:hugol /home/pi/mesh-logs

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo "Board ID: $BOARD_ID"
echo "IP Address: $BOARD_IP"
echo "ESSID: mesh-test"
echo "Channel: 6"
echo ""
echo "Next steps:"
echo "1. Run 'sudo poweroff' to shutdown this board"
echo "2. Repeat this setup on other boards with different IDs"
echo "3. Power on all boards together"
echo "4. Wait 12-15 minutes"
echo "5. Power off and check logs in /home/hugol/mesh-logs/"
echo ""
echo "LED Indicators:"
echo "  - Fast heartbeat = Connected to mesh"
echo "  - Slow blink = Not connected"
echo "=========================================="
echo ""
echo "Ready to power off!"