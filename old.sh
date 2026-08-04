#!/bin/sh
# ==============================================================================
# HOMEBRIDGE UXC MASTER INITIALIZATION ENGINE
# Production Deployment Script
# OpenWrt + UXC + ARM64 Homebridge Bundle
# ==============================================================================

# Safe mode: stop immediately on errors
set -e

echo "========================================================"
echo " ⚡ HOMEBRIDGE UXC MASTER INITIALIZATION ENGINE ⚡"
echo "========================================================"
printf '\n\n\n'


# ==============================================================================
# PART 1: MASTER CONFIGURATION VARIABLES
# ==============================================================================


# ==============================================================================
# GITHUB DOWNLOAD CONFIGURATION
# ==============================================================================

BUNDLE_URL="https://github.com/micpro7/test2/releases/latest/download/homebridge-arm64.tar.gz"


# ==============================================================================
# INSTALLATION VARIABLES
# ==============================================================================

CONTAINER_NAME="homebridge"

# Physical SSD mount location
TARGET_MOUNT="/mnt/X6"


# ==============================================================================
# DERIVED STORAGE PATHS
# ==============================================================================

# Download archive location
ARCHIVE="$TARGET_MOUNT/homebridge.tar.gz"

# UXC OCI bundle location
BUNDLE_PATH="$TARGET_MOUNT/UXC/$CONTAINER_NAME/bundle"

# Persistent Homebridge data location
PERSISTENT_DATA_SOURCE="$TARGET_MOUNT/UXC/$CONTAINER_NAME/data"



# ==============================================================================
# ENVIRONMENT SETTINGS
# ==============================================================================

# System timezone
TIMEZONE="Europe/London"

# Interface used for mDNS advertisements
MDNS_NET_INTERFACE="br-lan"

# Node.js heap allocation
NODE_MEMORY_LIMIT="256"

# Libuv worker threads
THREAD_POOL_SIZE="4"

# Homebridge UI bind address
BIND_IP="0.0.0.0"



# ==============================================================================
# SECURITY SETTINGS
# ==============================================================================

# Prevent privilege escalation inside container
# true = restricted
# false = normal container behaviour

NO_NEW_PRIVILEGES=false



# ==============================================================================
# PHASE 0: CREATE MASTER VARIABLE MAP
# ==============================================================================

echo "📝 Creating persistent Homebridge variable map..."


cat > /etc/homebridge.conf << EOF
# ==============================================================================
# Auto-generated Homebridge UXC configuration
# ==============================================================================

CONTAINER_NAME="$CONTAINER_NAME"

TARGET_MOUNT="$TARGET_MOUNT"

BUNDLE_PATH="$BUNDLE_PATH"

PERSISTENT_DATA_SOURCE="$PERSISTENT_DATA_SOURCE"


TIMEZONE="$TIMEZONE"

MDNS_NET_INTERFACE="$MDNS_NET_INTERFACE"

NODE_MEMORY_LIMIT="$NODE_MEMORY_LIMIT"

THREAD_POOL_SIZE="$THREAD_POOL_SIZE"

BIND_IP="$BIND_IP"


NO_NEW_PRIVILEGES="$NO_NEW_PRIVILEGES"

EOF


chmod 600 /etc/homebridge.conf


echo "✅ Variable map saved:"
echo "   /etc/homebridge.conf"

echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'



# ==============================================================================
# PHASE 1: ENVIRONMENT & DEPENDENCY CHECK
# ==============================================================================


echo "🔄 [Phase 1] Syncing OpenWrt dependencies..."


echo "🔍 Checking SSD mount..."


if ! grep -qs " $TARGET_MOUNT " /proc/mounts; then

    echo "❌ ERROR: $TARGET_MOUNT is not mounted."
    echo "Aborting to prevent writing into RAM."

    exit 1

fi


echo "✅ $TARGET_MOUNT mounted successfully."


echo "📦 Installing required packages..."


apk update


apk add --no-cache \
    uxc \
    procd-ujail \
    kmod-veth \
    jq \
    curl


echo "✅ Dependencies installed."


echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'



# ==============================================================================
# PHASE 2: REMOVE OLD UXC INSTANCE
# ==============================================================================


echo "🧹 [Phase 2] Removing previous Homebridge runtime..."


uxc kill "$CONTAINER_NAME" 2>/dev/null || true

uxc delete "$CONTAINER_NAME" --force 2>/dev/null || true



echo "🗑 Removing old bundle..."


rm -rf "$BUNDLE_PATH"



echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'



# ==============================================================================
# PHASE 3: CREATE STORAGE STRUCTURE
# ==============================================================================


echo "📂 [Phase 3] Creating Homebridge storage layout..."


mkdir -p "$BUNDLE_PATH"

mkdir -p "$PERSISTENT_DATA_SOURCE"


sync


echo "Bundle:"
echo " $BUNDLE_PATH"

echo

echo "Persistent data:"
echo " $PERSISTENT_DATA_SOURCE"


echo "========(+) DONE ✅ (+)========"

printf '\n\n\n'

# ==============================================================================
# PART 4: DOWNLOAD AND VERIFY HOMEBRIDGE UXC BUNDLE
# ==============================================================================


echo "📥 [Phase 4] Downloading production Homebridge bundle..."


if ! wget -q --show-progress \
    -O "$ARCHIVE" \
    "$BUNDLE_URL"; then

    echo "❌ ERROR: Failed to download Homebridge bundle."
    exit 1

fi


echo
echo "📦 Extracting bundle into:"
echo "   $BUNDLE_PATH"


if ! tar -xpf "$ARCHIVE" -C "$BUNDLE_PATH"; then

    echo "❌ ERROR: Failed to extract bundle."

    rm -f "$ARCHIVE"
    rm -rf "$BUNDLE_PATH"

    exit 1

fi


sync


rm -f "$ARCHIVE"



# ==============================================================================
# BUNDLE STRUCTURE VALIDATION
# ==============================================================================


echo "🔍 Validating bundle structure..."


if [ ! -f "$BUNDLE_PATH/config.json" ]; then

    echo "❌ ERROR: Missing OCI config.json."

    rm -rf "$BUNDLE_PATH"

    exit 1

fi



if [ ! -d "$BUNDLE_PATH/rootfs" ]; then

    echo "❌ ERROR: Missing rootfs directory."

    rm -rf "$BUNDLE_PATH"

    exit 1

fi



if [ ! -f "$BUNDLE_PATH/rootfs/init" ]; then

    echo "❌ ERROR: Missing container init script."

    rm -rf "$BUNDLE_PATH"

    exit 1

fi



echo "   config.json detected       ✅"
echo "   rootfs detected            ✅"
echo "   init script detected       ✅"



# ==============================================================================
# JSON VALIDATION
# ==============================================================================


if ! jq empty "$BUNDLE_PATH/config.json" >/dev/null 2>&1; then

    echo "❌ ERROR: config.json is invalid JSON."

    rm -rf "$BUNDLE_PATH"

    exit 1

fi


echo "   OCI JSON validated         ✅"


echo "🚀 Homebridge UXC bundle authenticated."


echo "========(+) DONE ✅ (+)========"


printf '\n\n\n'



# ==============================================================================
# PART 5: OCI CONFIGURATION INJECTION
# ==============================================================================


echo "📝 [Phase 5] Applying runtime configuration..."



# ==============================================================================
# 1. Persistent Homebridge Storage Mount
#
# Dockerfile:
#     VOLUME ["/homebridge"]
#
# Therefore UXC must mount:
#     /homebridge -> SSD persistent folder
# ==============================================================================


jq --arg src "$PERSISTENT_DATA_SOURCE" '

.mounts |= map(
    if .destination == "/homebridge"
    then .source = $src
    else .
    end
)

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ Persistent storage:"
echo "      $PERSISTENT_DATA_SOURCE"



# ==============================================================================
# 2. Timezone
# ==============================================================================


jq --arg value "TZ=$TIMEZONE" '

.process.env |= map(
    if startswith("TZ=")
    then $value
    else .
    end
)

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ Timezone:"
echo "      $TIMEZONE"



# ==============================================================================
# 3. mDNS Interface
# ==============================================================================


jq --arg value "MDNS_INTERFACE=$MDNS_NET_INTERFACE" '

.process.env |= map(
    if startswith("MDNS_INTERFACE=")
    then $value
    else .
    end
)

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ mDNS interface:"
echo "      $MDNS_NET_INTERFACE"



# ==============================================================================
# 4. Node.js Memory Limit
# ==============================================================================


jq --arg value "NODE_OPTIONS=--max-old-space-size=$NODE_MEMORY_LIMIT" '

.process.env |= map(
    if startswith("NODE_OPTIONS=")
    then $value
    else .
    end
)

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ Node memory:"
echo "      ${NODE_MEMORY_LIMIT}MB"



# ==============================================================================
# 5. Libuv Thread Pool
# ==============================================================================


jq --arg value "UV_THREADPOOL_SIZE=$THREAD_POOL_SIZE" '

.process.env |= map(
    if startswith("UV_THREADPOOL_SIZE=")
    then $value
    else .
    end
)

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ Libuv threads:"
echo "      $THREAD_POOL_SIZE"



# ==============================================================================
# 6. Homebridge Config UI Host
#
# Replace existing value or create if missing
# ==============================================================================


jq --arg value "HOMEBRIDGE_CONFIG_UI_HOST=$BIND_IP" '

.process.env |=
(
    if map(select(startswith("HOMEBRIDGE_CONFIG_UI_HOST="))) | length > 0

    then
        map(
            if startswith("HOMEBRIDGE_CONFIG_UI_HOST=")
            then $value
            else .
            end
        )

    else
        . + [$value]

    end
)

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ Homebridge UI host:"
echo "      $BIND_IP"



# ==============================================================================
# 7. noNewPrivileges Security Setting
# ==============================================================================


jq --argjson value "$NO_NEW_PRIVILEGES" '

.process.noNewPrivileges = $value

' "$BUNDLE_PATH/config.json" \
> "$BUNDLE_PATH/config.json.tmp" \
&& mv "$BUNDLE_PATH/config.json.tmp" "$BUNDLE_PATH/config.json"



echo "   ↳ noNewPrivileges:"
echo "      $NO_NEW_PRIVILEGES"



echo

echo "⚙️ OCI blueprint compiled."

echo "========(+) DONE ✅ (+)========"


printf '\n\n\n'

# ==============================================================================
# PART 6: UXC CONTAINER REGISTRATION & STARTUP
# ==============================================================================


echo "🏗️ [Phase 6] Registering Homebridge with UXC engine..."


# Remove any previous registration just in case

uxc kill "$CONTAINER_NAME" 2>/dev/null || true

uxc delete "$CONTAINER_NAME" --force 2>/dev/null || true



echo "📦 Creating UXC container instance..."


if ! uxc create "$CONTAINER_NAME" \
    --bundle "$BUNDLE_PATH" \
    --mounts "$TARGET_MOUNT"; then

    echo "❌ ERROR: Failed to create UXC container."

    exit 1

fi



echo "✅ UXC container registered."


printf '\n\n'


echo "⏳ Waiting for runtime stabilization..."

sleep 3


printf '\n\n'


echo "🚀 Starting Homebridge..."


if ! uxc start "$CONTAINER_NAME"; then

    echo "❌ ERROR: Failed to start Homebridge."

    exit 1

fi



printf '\n\n'


echo "✨ Current UXC status:"

uxc list



echo "========(+) DONE ✅ (+)========"


printf '\n\n\n'



# ==============================================================================
# PART 7: INSTALL PROCD AUTOSTART SERVICE
# ==============================================================================


echo "🛠️ Installing persistent Homebridge procd service..."



cat > /etc/init.d/homebridge << 'EOF'
#!/bin/sh /etc/rc.common


START=99
STOP=10


# Allow:
# /etc/init.d/homebridge status

extra_command "status" "Show Homebridge container status"



# ==============================================================================
# LOAD CONFIGURATION
# ==============================================================================


if [ -f /etc/homebridge.conf ]; then

    . /etc/homebridge.conf

else

    logger -t homebridge_init \
    "[CRITICAL] Missing /etc/homebridge.conf"

    exit 1

fi



# ==============================================================================
# START
#
# Flow:
# Wait SSD
# Verify bundle
# Remove stale runtime
# Register container
# Start Homebridge
# ==============================================================================


start()
{

logger -t homebridge_init \
"Waiting for $TARGET_MOUNT..."



for i in $(seq 1 30)
do

    if grep -qs " $TARGET_MOUNT " /proc/mounts
    then

        logger -t homebridge_init \
        "$TARGET_MOUNT mounted."

        break

    fi


    sleep 1

done



if ! grep -qs " $TARGET_MOUNT " /proc/mounts
then

    logger -t homebridge_init \
    "[CRITICAL] SSD mount unavailable."

    return 1

fi



if [ ! -f "$BUNDLE_PATH/config.json" ]
then

    logger -t homebridge_init \
    "[CRITICAL] Missing UXC bundle."

    return 1

fi



logger -t homebridge_init \
"Cleaning previous container state..."



/sbin/uxc kill "$CONTAINER_NAME" \
>/dev/null 2>&1 || true


/sbin/uxc delete "$CONTAINER_NAME" \
--force >/dev/null 2>&1 || true



logger -t homebridge_init \
"Registering Homebridge UXC instance..."



if ! /sbin/uxc create \
"$CONTAINER_NAME" \
--bundle "$BUNDLE_PATH" \
--mounts "$TARGET_MOUNT"
then

    logger -t homebridge_init \
    "[CRITICAL] UXC create failed."

    return 1

fi



sleep 1



logger -t homebridge_init \
"Starting Homebridge container..."



if ! /sbin/uxc start "$CONTAINER_NAME"
then

    logger -t homebridge_init \
    "[CRITICAL] UXC start failed."

    return 1

fi



logger -t homebridge_init \
"Homebridge started successfully."



}



# ==============================================================================
# STOP
#
# Graceful shutdown first
# Force kill fallback
# ==============================================================================


stop()
{


logger -t homebridge_init \
"Stopping Homebridge..."



/sbin/uxc kill "$CONTAINER_NAME" \
>/dev/null 2>&1 || true



for i in 1 2 3
do


STATE=$(
/sbin/uxc state "$CONTAINER_NAME" \
2>/dev/null | jq -r '.status'
)



if [ "$STATE" != "running" ]
then

    logger -t homebridge_init \
    "Homebridge stopped."

    return 0

fi



sleep 1


done



logger -t homebridge_init \
"Force stopping Homebridge..."



/sbin/uxc kill "$CONTAINER_NAME" \
--signal KILL \
>/dev/null 2>&1 || true



sleep 1



logger -t homebridge_init \
"Homebridge force stopped."



}



# ==============================================================================
# STATUS
# ==============================================================================


status()
{


if [ ! -x /sbin/uxc ]
then

    echo "uxc missing"

    return 1

fi



JSON=$(
/sbin/uxc state "$CONTAINER_NAME" \
2>/dev/null
)



if [ -n "$JSON" ]
then

    echo "$JSON" | jq -r '.status'


    echo "$JSON" \
    | jq -e '.status=="running"' \
    >/dev/null 2>&1


    return $?

fi



echo "stopped"

return 1



}



EOF



chmod +x /etc/init.d/homebridge



/etc/init.d/homebridge enable



echo "✅ Homebridge procd service installed."


echo "========(+) DONE ✅ (+)========"


printf '\n\n\n'

# ==============================================================================
# PART 8: FINAL VERIFICATION & DEPLOYMENT COMPLETION
# ==============================================================================


echo "🔎 Performing final Homebridge deployment verification..."


printf '\n\n'



# ==============================================================================
# VERIFY PROCD SERVICE
# ==============================================================================


echo "🛠 Checking procd service..."


if [ -x /etc/init.d/homebridge ]; then

    echo "   Homebridge init service found ✅"

else

    echo "❌ ERROR: Homebridge init service missing."

    exit 1

fi



echo "   Service enabled:"

ls -l /etc/rc.d/ | grep homebridge || true



printf '\n\n'



# ==============================================================================
# VERIFY UXC CONTAINER
# ==============================================================================


echo "📦 Checking UXC container state..."


uxc list



printf '\n\n'



# ==============================================================================
# VERIFY STORAGE
# ==============================================================================


echo "💾 Checking persistent storage..."


echo

echo "Bundle location:"
echo " $BUNDLE_PATH"


echo

echo "Persistent data:"
echo " $PERSISTENT_DATA_SOURCE"



if [ -d "$PERSISTENT_DATA_SOURCE" ]; then

    echo "   Persistent directory exists ✅"

else

    echo "❌ ERROR: Persistent directory missing."

    exit 1

fi



printf '\n\n'



# ==============================================================================
# DISPLAY DISK USAGE
# ==============================================================================


echo "📊 Homebridge bundle size:"


du -sh "$BUNDLE_PATH"



echo


echo "📊 Persistent data size:"


du -sh "$PERSISTENT_DATA_SOURCE" 2>/dev/null || true



printf '\n\n'



# ==============================================================================
# VERIFY OCI CONFIG AFTER PATCHING
# ==============================================================================


echo "🔍 Checking final OCI configuration..."


if jq empty "$BUNDLE_PATH/config.json" >/dev/null 2>&1; then

    echo "   config.json valid JSON ✅"

else

    echo "❌ ERROR: config.json corrupted after modification."

    exit 1

fi



echo

echo "Environment variables:"


jq -r '
.process.env[]
' "$BUNDLE_PATH/config.json"



printf '\n\n'



# ==============================================================================
# FINAL SYNC
# ==============================================================================


echo "💾 Syncing filesystem..."


sync



sleep 2



# ==============================================================================
# FINAL STATUS
# ==============================================================================


echo
echo "========================================================"
echo " 🎉 HOMEBRIDGE UXC DEPLOYMENT COMPLETE 🎉"
echo "========================================================"


echo

echo "Container:"
echo " $CONTAINER_NAME"


echo

echo "Bundle:"
echo " $BUNDLE_PATH"


echo

echo "Persistent Data:"
echo " $PERSISTENT_DATA_SOURCE"


echo

echo "Web UI:"
echo " http://$(uci -q get network.lan.ipaddr):8581"


echo

echo "Management:"
echo " /etc/init.d/homebridge start"
echo " /etc/init.d/homebridge stop"
echo " /etc/init.d/homebridge restart"
echo " /etc/init.d/homebridge status"



echo

echo "========================================================"


printf '\n\n'


echo "⚡ Homebridge is now running under OpenWrt UXC ⚡"


echo "========(+) DONE ✅ (+)========"
