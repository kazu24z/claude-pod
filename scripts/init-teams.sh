#!/bin/bash
# init-teams.sh - Agent Teams setup (sourced by entrypoint.sh when AGENT_TEAMS=1)
# Installs tmux shim, queries cmux for surface IDs, sets env vars.

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
