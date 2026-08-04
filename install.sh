#!/bin/sh

echo "======================================="
echo " HomeBridge UXC Installer"
echo "======================================="
echo -e "\n\n\n"

# =========================
# Install prerequisites
# =========================
echo "[i] Installing packages..."

apk update
apk add uxc procd-ujail kmod-veth
# optional for editing config.json
apk add jq
echo -e "\n\n\n"

# =========================
# Configuration
# =========================
BUNDLE_URL="https://github.com/micpro7/test2/releases/latest/download/homebridge-arm64.tar.gz"

CONTAINER_NAME="homebridge"

BUNDLE_PATH="/mnt/X6/UXC/homebridge"

CONFIG_PATH="/mnt/SSD/Config/OpenWrt/UXC/homebridge"

ARCHIVE="/mnt/X6/homebridge.tar.gz"
echo -e "\n\n\n"

# =========================
# Remove Previous Container
# =========================
echo "[i] Removing previous container..."

uxc kill "$CONTAINER_NAME" 2>/dev/null || true

uxc delete "$CONTAINER_NAME" --force 2>/dev/null || true
echo -e "\n\n\n"

# =========================
# Create directories
# =========================
echo "[i] Creating directories..."

mkdir -p "$BUNDLE_PATH"

mkdir -p "$CONFIG_PATH"
mkdir -p "$CONFIG_PATH/accessories"
mkdir -p "$CONFIG_PATH/persist"
mkdir -p "$CONFIG_PATH/backups"
mkdir -p "$CONFIG_PATH/plugins"

sync
echo -e "\n\n\n"

# =========================
# Delete Old bundle
# =========================
echo "[i] Deleting old directories..."

rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH"
echo -e "\n\n\n"

# =========================
# Download bundle
# =========================
echo "[i] Downloading bundle..."

wget -O "$ARCHIVE" "$BUNDLE_URL"
echo -e "\n\n\n"

# =========================
# Extract bundle
# =========================
echo "[i] Extracting bundle..."

tar -xpf "$ARCHIVE" -C "$BUNDLE_PATH"

sync
echo -e "\n\n\n"


# =========================
# Validate Bundle
# =========================
echo "[i] Validating OCI bundle..."

# Check config.json
if [ -f "$BUNDLE_PATH/config.json" ]; then
    echo "config.json validated ✅"
else
    echo "[ERROR] Missing config.json"
    exit 1
fi
printf '\n\n\n'

# Check rootfs directory
if [ -d "$BUNDLE_PATH/rootfs" ]; then
    echo "rootfs directory validated ✅"
else
    echo "[ERROR] Missing rootfs"
    exit 1
fi
printf '\n\n\n'

echo "[OK] OCI bundle fully validated."
printf '\n\n\n'


# =========================
# Create Container
# =========================
echo "[i] Creating container..."

uxc create "$CONTAINER_NAME" \
    --bundle "$BUNDLE_PATH" \
    --autostart \
    --mounts /mnt/SSD,/mnt/X6
echo -e "\n\n\n"

# =========================
# Sleep 3
# Add a small delay to ensure filesystem buffers are flushed
# =========================
echo "[i] Sleep 3 Seconds..."
sleep 3

# =========================
# Start Container
# =========================
echo "[i] Starting container..."

uxc start "$CONTAINER_NAME"

echo "[OK] Container started successfully."

echo -e "\n\n\n"

# =========================
# Check Container State
# =========================
echo
echo "Container status:"
uxc state "$CONTAINER_NAME"
echo -e "\n\n\n"

# =========================
# List All Container
# =========================
echo
echo "Configured containers:"
uxc list
echo -e "\n\n\n"

# =========================
# Autostart on boot
# =========================
echo
echo "Configuring Homebridge autostart on boot"
# 1. Create init script
cat > /etc/init.d/homebridge << 'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

CONTAINER_NAME="homebridge"

start_service() {
    procd_open_instance
    procd_set_param command /sbin/uxc start "$CONTAINER_NAME"
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    /sbin/uxc kill "$CONTAINER_NAME"
}

# This function maps 'service homebridge status' to the container status
status_service() {
    local status
    status=$(/sbin/uxc state "$CONTAINER_NAME" | grep '"status"' | cut -d'"' -f4)
    
    if [ -n "$status" ]; then
        echo "Homebridge container status: $status"
    else
        echo "Homebridge container status: unknown (is uxc running?)"
    fi
}
EOF

# 2. Apply and enable
chmod +x /etc/init.d/homebridge
/etc/init.d/homebridge enable
/etc/init.d/homebridge start
##########################################
echo "========(+) FINISHED (+)========"
echo -e "\n\n\n"
