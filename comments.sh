### ✅ What is 100% Spot On
 1. **"readonly": false in root**: Allows native npm install for Homebridge plugins without tripping procd-ujail overlay restrictions.
 2. **"noNewPrivileges": false**: Allows spawned plugin child processes to run without kernel jail privilege errors.
 3. **Optimized env Array**:
   * npm_config_cache=/tmp/.npm and npm_config_devdir=/tmp/.node-gyp redirect volatile builds to host RAM (/tmp).
   * Baseline NODE_OPTIONS=--max-old-space-size=256 and UV_THREADPOOL_SIZE=4 are correctly positioned to be overridden dynamically by install.sh.
 4. **Capabilities**: CAP_NET_BIND_SERVICE, CAP_NET_RAW, and CAP_SYS_ADMIN are present for mDNS and raw socket access required by smart home plugins.
