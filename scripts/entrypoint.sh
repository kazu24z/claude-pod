#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =====================================================
# entrypoint.sh - Claude Pod container entrypoint
# Branches initialization based on FIREWALL_MODE
# =====================================================

# --- Common processing (all modes) ---

# Symlink /.claude -> /home/user/.claude (Claude Code looks for /.claude when HOME=/)
ln -sf /home/user/.claude /.claude

# Copy skill files into user config
if [ -d /usr/local/share/claude-pod/skills ]; then
    mkdir -p /home/user/.claude/skills/claude-pod
    cp /usr/local/share/claude-pod/skills/* /home/user/.claude/skills/claude-pod/
fi

export HOME=/home/user \
    CLAUDE_CONFIG_DIR=/home/user/.claude

# --- Agent Teams setup ---

AGENT_TEAMS="${AGENT_TEAMS:-}"
if [ "$AGENT_TEAMS" = "1" ]; then
    # Install tmux shim — intercepts tmux calls and bridges to host cmux
    SHIM_DIR="/usr/local/lib/tmux-shim"
    mkdir -p "$SHIM_DIR"
    ln -sf /usr/local/bin/tmux-shim.sh "$SHIM_DIR/tmux"
    export PATH="${SHIM_DIR}:${PATH}"

    # Query cmux for real workspace/surface IDs via TCP bridge
    CMUX_BRIDGE="${CMUX_BRIDGE:-}"
    if [ -n "$CMUX_BRIDGE" ]; then
        _bridge_host=$(echo "$CMUX_BRIDGE" | cut -d: -f2)
        _bridge_port=$(echo "$CMUX_BRIDGE" | cut -d: -f3)
        _identify=$(echo '{"id":"init","method":"system.identify","params":{}}' \
            | socat -t5 - "TCP:${_bridge_host}:${_bridge_port}" 2>/dev/null || echo "{}")
        _workspace_id=$(echo "$_identify" | jq -r '.result.focused.workspace_id // empty' 2>/dev/null || true)
        _window_id=$(echo "$_identify" | jq -r '.result.focused.window_id // empty' 2>/dev/null || true)
        _pane_id=$(echo "$_identify" | jq -r '.result.focused.pane_id // empty' 2>/dev/null || true)
        _surface_id=$(echo "$_identify" | jq -r '.result.focused.surface_id // empty' 2>/dev/null || true)
    fi

    # Set TMUX/TMUX_PANE in cmux-compatible format
    if [ -n "${_workspace_id:-}" ] && [ -n "${_window_id:-}" ] && [ -n "${_pane_id:-}" ]; then
        export TMUX="/tmp/cmux-claude-teams/${_workspace_id},${_window_id},${_pane_id}"
        export TMUX_PANE="%${_pane_id}"
    else
        echo "WARNING: Could not query cmux IDs, using fallback TMUX values" >&2
        export TMUX="/tmp/cmux-pod-fake,0,0"
        export TMUX_PANE="%0"
    fi

    export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
    export CLAUDECODE=1
    export CLAUDE_CODE_ENTRYPOINT=cli
fi

# --- FIREWALL_MODE branching ---

FIREWALL_MODE="${FIREWALL_MODE:-}"

case "$FIREWALL_MODE" in
    none|"")
        # No network restrictions - container isolation only
        ;;
    l7)
        # Capability check
        if ! iptables -L -n >/dev/null 2>&1; then
            echo "ERROR: FIREWALL_MODE=${FIREWALL_MODE} requires NET_ADMIN capability. Add --cap-add NET_ADMIN to docker run." >&2
            exit 1
        fi

        # sudoers setup for squid reload only (iptables runs as root in entrypoint)
        echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/squid -k reconfigure" \
            > /etc/sudoers.d/claude-pod-network
        chmod 0440 /etc/sudoers.d/claude-pod-network

        # Add user to /etc/passwd and /etc/shadow if not present (for sudo)
        if ! awk -F: -v uid="${HOST_UID}" '$3==uid{found=1}END{exit !found}' /etc/passwd; then
            printf 'user%s:x:%s:0::/home/user:/bin/bash\n' "${HOST_UID}" "${HOST_UID}" >> /etc/passwd
            printf 'user%s:!:19000:0:99999:7:::\n' "${HOST_UID}" >> /etc/shadow
        fi

        /usr/local/bin/init-l7.sh < /dev/null

        # Proxy environment variables (L7 only - forces traffic through Squid)
        export http_proxy=http://127.0.0.1:3128 \
            https_proxy=http://127.0.0.1:3128 \
            HTTP_PROXY=http://127.0.0.1:3128 \
            HTTPS_PROXY=http://127.0.0.1:3128 \
            no_proxy=127.0.0.1,localhost \
            NO_PROXY=127.0.0.1,localhost
        ;;
    *)
        echo "ERROR: Unknown FIREWALL_MODE: ${FIREWALL_MODE}. Valid values: none, l7" >&2
        exit 1
        ;;
esac

exec gosu "${HOST_UID}:${HOST_GID}" /usr/local/bin/claude "$@"
