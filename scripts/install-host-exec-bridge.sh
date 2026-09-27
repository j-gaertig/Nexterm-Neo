#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="${1:-/opt/nexterm}"
BRIDGE_DIR="/usr/local/lib/nexterm-host-exec"
SOURCE_BASE="${NEXTERM_SOURCE_BASE:-https://raw.githubusercontent.com/j-gaertig/Nexterm-Neo/${NEXTERM_SOURCE_REF:-main}/scripts}"

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run this installer as root.\n' >&2
    exit 1
fi

if [ ! -d /run/systemd/system ] || ! command -v systemctl >/dev/null 2>&1; then
    printf 'The host command bridge requires systemd.\n' >&2
    exit 1
fi

if [ ! -r /etc/os-release ]; then
    printf 'Cannot identify the host distribution.\n' >&2
    exit 1
fi

. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *)
        printf 'The host command bridge currently supports Debian and Ubuntu.\n' >&2
        exit 1
        ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3
fi

case "$INSTALL_DIR" in
    *'"'*|*$'\n'*)
        printf 'The AIO installation directory cannot contain quotes or line breaks.\n' >&2
        exit 1
        ;;
esac

mkdir -p "$BRIDGE_DIR" /etc/systemd/system /etc/tmpfiles.d /etc/default
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$LOCAL_DIR/host_exec_bridge.py" ]; then
    install -m 0644 "$LOCAL_DIR/host_exec_bridge.py" "$BRIDGE_DIR/host_exec_bridge.py"
else
    command -v curl >/dev/null 2>&1 || { printf 'curl is required to download the host bridge.\n' >&2; exit 1; }
    curl -fsSL "$SOURCE_BASE/host_exec_bridge.py" -o "$BRIDGE_DIR/host_exec_bridge.py"
    chmod 0644 "$BRIDGE_DIR/host_exec_bridge.py"
fi

printf 'NEXTERM_HOST_EXEC_CWD="%s"\n' "$INSTALL_DIR" > /etc/default/nexterm-host-exec
cat > /etc/tmpfiles.d/nexterm-host-exec.conf <<'EOF'
d /run/nexterm-host-exec 0700 root root -
EOF
cat > /etc/systemd/system/nexterm-host-exec.service <<'EOF'
[Unit]
Description=Nexterm AIO host command bridge
After=local-fs.target

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=/etc/default/nexterm-host-exec
ExecStart=/usr/bin/python3 /usr/local/lib/nexterm-host-exec/host_exec_bridge.py
Restart=on-failure
RestartSec=2
UMask=0177
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemd-tmpfiles --create /etc/tmpfiles.d/nexterm-host-exec.conf
systemctl enable --now nexterm-host-exec.service
systemctl is-active --quiet nexterm-host-exec.service
printf 'Nexterm host command bridge is active. Add /run/nexterm-host-exec:/run/nexterm-host-exec to the AIO container volumes.\n'
