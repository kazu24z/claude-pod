#!/bin/bash
# tmux-shim.sh — Forwards ALL tmux commands to host's cmux __tmux-compat
# via TCP bridge. This gives 100% compatibility with cmux's tmux translation.

CMUX_BRIDGE="${CMUX_BRIDGE:-}"
if [ -z "$CMUX_BRIDGE" ]; then
    echo "tmux-shim: CMUX_BRIDGE not set" >&2
    exit 1
fi

BRIDGE_HOST=$(echo "$CMUX_BRIDGE" | cut -d: -f2)
BRIDGE_PORT=$(echo "$CMUX_BRIDGE" | cut -d: -f3)
# tmux-compat port = socket port + 1
TMUX_PORT=$((BRIDGE_PORT + 1))

# Build JSON payload with jq (handles all special chars correctly)
args_json=$(printf '%s\0' "$@" | jq -Rs 'split("\u0000") | .[:-1]')

payload=$(jq -nc \
    --argjson args "$args_json" \
    --arg tmux "${TMUX:-}" \
    --arg tmux_pane "${TMUX_PANE:-}" \
    '{args: $args, env: {TMUX: $tmux, TMUX_PANE: $tmux_pane}}')

# Send to bridge, get response
response=$(printf '%s' "$payload" | socat -t10 - "TCP:${BRIDGE_HOST}:${TMUX_PORT}" 2>/dev/null)

if [ -z "$response" ]; then
    exit 1
fi

# Extract stdout, stderr, returncode from JSON response
stdout=$(echo "$response" | jq -r '.stdout // empty' 2>/dev/null)
stderr=$(echo "$response" | jq -r '.stderr // empty' 2>/dev/null)
rc=$(echo "$response" | jq -r '.returncode // 0' 2>/dev/null)

[ -n "$stdout" ] && printf '%s' "$stdout"
[ -n "$stderr" ] && printf '%s' "$stderr" >&2
exit "${rc:-0}"
