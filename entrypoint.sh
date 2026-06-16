#!/bin/bash
set -euo pipefail

DEV_HOME="${DEV_HOME:-/home/dev}"
DEV_USER="dev"
DEV_SHELL="/bin/bash"

if [ -d "$DEV_HOME" ]; then
    HOST_UID=$(stat -c "%u" "$DEV_HOME")
    HOST_GID=$(stat -c "%g" "$DEV_HOME")
else
    HOST_UID="${DEV_UID:-1000}"
    HOST_GID="${DEV_GID:-1000}"
fi

if [ "$HOST_UID" = "0" ]; then
    echo ">>> Mounted home owned by root — running as root"
    RUN_USER="root"
else
    RUN_USER="$DEV_USER"
    if ! getent group "$HOST_GID" >/dev/null 2>&1; then
        groupadd --gid "$HOST_GID" "$DEV_USER"
    fi
    EXISTING_GROUP=$(getent group "$HOST_GID" | cut -d: -f1)

    if ! id -u "$DEV_USER" >/dev/null 2>&1; then
        useradd --uid "$HOST_UID" --gid "$HOST_GID" --groups "$EXISTING_GROUP" \
                --home-dir "$DEV_HOME" --shell "$DEV_SHELL" "$DEV_USER"
    fi

    chown "$HOST_UID:$HOST_GID" "$DEV_HOME" 2>/dev/null || true

    echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$DEV_USER"
    chmod 0440 /etc/sudoers.d/"$DEV_USER"
fi

DOCKER_SOCK="/var/run/docker.sock"
if [ -S "$DOCKER_SOCK" ]; then
    DOCKER_GID=$(stat -c "%g" "$DOCKER_SOCK")
    if ! getent group "$DOCKER_GID" >/dev/null 2>&1; then
        groupadd --gid "$DOCKER_GID" "host-docker"
    fi
    HOST_DOCKER_GROUP=$(getent group "$DOCKER_GID" | cut -d: -f1)
    if [ "$RUN_USER" != "root" ]; then
        usermod -aG "$HOST_DOCKER_GROUP" "$RUN_USER"
    fi
fi

MISE_DATA="${DEV_HOME}/.local/share/mise"
MISE_CONFIG="${DEV_HOME}/.config/mise"

export MISE_DATA_DIR="$MISE_DATA"
export MISE_CONFIG_DIR="$MISE_CONFIG"

# Ensure mise data dir is writable before install (handles stale root-owned dirs)
mkdir -p "$MISE_DATA"
chown -R "$HOST_UID:$HOST_GID" "${DEV_HOME}/.local" 2>/dev/null || true

if command -v mise &>/dev/null; then
    MISE_BIN="$(command -v mise)"
else
    MISE_BIN="${DEV_HOME}/.local/bin/mise"
    if [ ! -f "$MISE_BIN" ]; then
        echo ">>> Installing mise …"
        sudo -u "$RUN_USER" sh -c "$(curl -fsSL https://mise.run)" -- --yes
    fi
fi

export PATH="$PATH:${DEV_HOME}/.local/bin"
eval "$("$MISE_BIN" activate bash 2>/dev/null)" || true

# Persist PATH for `docker compose exec` shells
cat > /etc/profile.d/mise.sh <<-PROFILE
export MISE_DATA_DIR="$MISE_DATA"
export MISE_CONFIG_DIR="$MISE_CONFIG"
export PATH="\$PATH:${DEV_HOME}/.local/share/mise/shims:${DEV_HOME}/.local/bin"
PROFILE

if [ -n "${MISE_DEFAULT_TOOLS:-}" ]; then
    echo ">>> Installing mise default tools: $MISE_DEFAULT_TOOLS"
    # shellcheck disable=SC2086
    sudo -u "$RUN_USER" "$MISE_BIN" use --global $MISE_DEFAULT_TOOLS
    sudo -u "$RUN_USER" "$MISE_BIN" install
fi

if [ -n "${AIONUI_CLI_AGENTS:-}" ] && [ -x /usr/local/bin/install-agents.sh ]; then
    echo ">>> Installing CLI agents …"
    # shellcheck disable=SC2086
    sudo -u "$RUN_USER" AIONUI_CLI_AGENTS="$AIONUI_CLI_AGENTS" \
        "$MISE_BIN" x $MISE_DEFAULT_TOOLS -- /usr/local/bin/install-agents.sh
fi

CODE_SERVER_CONFIG="${DEV_HOME}/.config/code-server/config.yaml"
if [ ! -f "$CODE_SERVER_CONFIG" ]; then
    sudo -u "$RUN_USER" mkdir -p "$(dirname "$CODE_SERVER_CONFIG")"
    cat > "$CODE_SERVER_CONFIG" <<-CODECONF
bind-addr: 0.0.0.0:8443
auth: password
password: "${CODE_SERVER_PASSWORD:-devpass}"
cert: false
CODECONF
    chown "$HOST_UID:$HOST_GID" "$CODE_SERVER_CONFIG"
fi

mkdir -p "${DEV_HOME}/.local/share/code-server/User"
chown -R "$HOST_UID:$HOST_GID" "${DEV_HOME}/.local" 2>/dev/null || true

start_aionui() {
    local aionui_dir="/app/aionui"
    if [ ! -d "$aionui_dir/out/renderer" ]; then
        echo ">>> AionUI renderer not built, skipping"
        return
    fi
    local aionui_port="${AIONUI_PORT:-3000}"
    local aionui_log="/tmp/aionui-$$.log"
    echo ">>> Starting AionUI Web on port $aionui_port …"
    sudo -u "$RUN_USER" env \
        AIONUI_PORT="$aionui_port" \
        AIONUI_HOST="0.0.0.0" \
        AIONUI_ALLOW_REMOTE=true \
        AIONUI_DATA_DIR="${DEV_HOME}/.aionui-web" \
        bun "$aionui_dir/scripts/webui.ts" --remote --no-build > "$aionui_log" 2>&1 &
    local aionui_pid=$!
    echo ">>> AionUI Web PID: $aionui_pid"
    for i in $(seq 1 15); do
        sleep 1
        if grep -q "Initial admin password\|Login username" "$aionui_log" 2>/dev/null; then
            break
        fi
        if ! kill -0 $aionui_pid 2>/dev/null; then
            echo ">>> AionUI Web failed to start:"
            head -10 "$aionui_log"
            return
        fi
    done
    grep -E "Initial admin|Login username|password:" "$aionui_log" 2>/dev/null | while read -r line; do
        echo ">>> AionUI: $line"
    done

    if [ -n "${AIONUI_PASSWORD:-}" ]; then
        echo ">>> AionUI: applying AIONUI_PASSWORD via change-password API …"
        for i in $(seq 1 6); do
            local status
            status=$(sudo -u "$RUN_USER" curl -s -o /dev/null -w "%{http_code}" \
                -X POST "http://127.0.0.1:$aionui_port/api/webui/change-password" \
                -H "Content-Type: application/json" \
                -d "{\"new_password\":\"$AIONUI_PASSWORD\"}" 2>/dev/null || echo "000")
            if [ "$status" = "200" ]; then
                echo ">>> AionUI: password set from AIONUI_PASSWORD env var"
                break
            fi
            sleep 2
        done
    fi
}

LAUNCH_AIONUI=false
if [ "$1" = "code-server" ] && [ "${AIONUI_ENABLED:-true}" = "true" ]; then
    LAUNCH_AIONUI=true
fi
if [ "${AIONUI_ENABLED:-false}" = "true" ] && [ "$1" != "code-server" ]; then
    LAUNCH_AIONUI=true
fi

if [ "$LAUNCH_AIONUI" = true ]; then
    start_aionui
fi

export HOME="$DEV_HOME"
exec su-exec "$RUN_USER" "$@"
