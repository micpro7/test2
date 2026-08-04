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
# (nodejs and npm are inherently provided by the base image)
# 
# Notes on compilation tools:
# - git, openssh-client: Required by npm to install beta plugins or dependencies hosted directly on GitHub URLs.
# - linux-headers: Required by node-gyp to compile native C/C++ plugins that need kernel/hardware access.
# - python3, make, g++: Standard node-gyp requirements for compiling native modules.
# - sudo, bash: Added for debugging, container maintenance, and plugin shell scripts.
# - libc6-compat: Required for running pre-compiled glibc-linked binaries or certain native modules on Alpine (musl).
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
# FIX: Repair sudo ownership & setuid bit for UXC compatibility
# ==========================================================
RUN chown -R root:root /etc/sudo* /usr/bin/sudo /usr/libexec/sudo 2>/dev/null || true \
 && chmod 4755 /usr/bin/sudo

# ==========================================================
# CRITICAL FIX:
# Ensure deterministic npm global install location and module path
# (prevents “missing package.json” / wrong prefix issues)
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
# Create explicit mount points for read-only rootfs compatibility
# ==========================================================
RUN mkdir -p \
    /var/lib/homebridge \
    /var/lib/homebridge/plugins \
    /var/lib/homebridge/persist \
    /var/lib/homebridge/accessories

# ==========================================================
# Runtime environment
# ==========================================================
ENV HOME=/root \
    TZ=UTC \
    NODE_ENV=production

WORKDIR /var/lib/homebridge
