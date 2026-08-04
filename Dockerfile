# syntax=docker/dockerfile:1

# Using node:24-alpine3.22 for stable, reproducible ARM64 builds
FROM node:24-alpine3.22

ARG HOMEBRIDGE_VERSION=latest
ARG CONFIG_UI_VERSION=latest

LABEL org.opencontainers.image.title="openwrt-uxc-homebridge" \
      org.opencontainers.image.description="Homebridge deployment for OpenWrt using native UXC containers" \
      org.opencontainers.image.source="https://github.com/micpro7/openwrt-uxc-homebridge"

# ==========================================================
# System dependencies
# ==========================================================
RUN apk add --no-cache \
    tzdata \
    ca-certificates \
    avahi-compat-libdns_sd \
    libstdc++ \
    libc6-compat \
    curl \
    ffmpeg \
    python3 \
    make \
    g++ \
    git \
    linux-headers \
    sudo \
    bash \
    openssh-client

# ==========================================================
# UXC FIX: Replace sudo binary with robust option-stripping wrapper
# Bypasses setresuid() capability/seccomp restrictions.
# Intentionally drops flags like -u, -g, -E to force execution as root.
# Validates that a target command is provided before executing.
# ==========================================================
RUN rm -f /usr/bin/sudo \
 && cat > /usr/bin/sudo <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        -n|-E|-H|-S|-k|-K|-b|-v)
            shift
            ;;
        -u|-g|-C)
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "sudo: no command specified" >&2
    exit 1
fi

exec "$@"
EOF
RUN chmod 0755 /usr/bin/sudo

# ==========================================================
# READ-ONLY ROOTFS FIX: Redirect npm cache/config/build to /tmp
# Pre-creates directories and redirects /root/.npm and /root/.config
# to the writable /tmp mount preventing ENOENT mkdir errors.
# ==========================================================
RUN mkdir -p /tmp/.npm /tmp/.config /tmp/.node-gyp \
 && rm -rf /root/.npm /root/.config \
 && ln -s /tmp/.npm /root/.npm \
 && ln -s /tmp/.config /root/.config

# ==========================================================
# CRITICAL FIX:
# Ensure deterministic npm global install location and module path
# ==========================================================
ENV NPM_CONFIG_PREFIX=/usr/local \
    NODE_PATH=/usr/local/lib/node_modules \
    npm_config_unsafe_perm=true \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

RUN npm config set prefix /usr/local \
 && npm config set update-notifier false \
 && npm config set audit false \
 && npm config set fund false \
 && npm cache verify

# ==========================================================
# Install Homebridge stack
# ==========================================================
RUN npm install -g --unsafe-perm \
    homebridge@${HOMEBRIDGE_VERSION} \
    homebridge-config-ui-x@${CONFIG_UI_VERSION} \
 && npm cache clean --force

# ==========================================================
# HARD VALIDATION (fail fast if install breaks)
# ==========================================================
RUN set -eux; \
    test -f /usr/local/lib/node_modules/homebridge/package.json; \
    test -f /usr/local/lib/node_modules/homebridge-config-ui-x/package.json; \
    command -v homebridge; \
    command -v hb-service; \
    node -e "console.log('Node.js Version:', process.version)"; \
    node -e "console.log('Homebridge OK:', require('/usr/local/lib/node_modules/homebridge/package.json').version)"; \
    node -e "console.log('UI OK:', require('/usr/local/lib/node_modules/homebridge-config-ui-x/package.json').version)"

# ==========================================================
# Create explicit mount points for persistent storage
# LINK FIX: Symlink /var/lib/homebridge/plugins -> node_modules
# guarantees backward compatibility whether plugins are searched 
# via -P or standard local node_modules resolution.
# ==========================================================
RUN mkdir -p \
    /var/lib/homebridge \
    /var/lib/homebridge/node_modules \
    /var/lib/homebridge/persist \
    /var/lib/homebridge/accessories \
 && ln -sf /var/lib/homebridge/node_modules /var/lib/homebridge/plugins

# ==========================================================
# Runtime environment & Container Launch
# ==========================================================
ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production \
    NPM_CONFIG_CACHE=/tmp/.npm \
    NPM_CONFIG_DEVDIR=/tmp/.node-gyp \
    XDG_CONFIG_HOME=/tmp/.config

WORKDIR /var/lib/homebridge

# RUNTIME LAUNCH COMMAND:
# Runs hb-service explicitly using local storage scope without locking -P flags
CMD ["/usr/local/bin/hb-service", "run", "--allow-root", "-U", "/var/lib/homebridge"]
