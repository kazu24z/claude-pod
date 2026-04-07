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

# Build JSON payload with args array
args_json="["
first=true
for arg in "$@"; do
    # Escape special JSON chars
    escaped=$(printf '%s' "$arg" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if $first; then
        args_json="${args_json}\"${escaped}\""
        first=false
    else
        args_json="${args_json},\"${escaped}\""
    fi
done
args_json="${args_json}]"

# Include TMUX env vars so bridge can set them for cmux __tmux-compat
tmux_escaped=$(printf '%s' "${TMUX:-}" | sed 's/\\/\\\\/g; s/"/\\"/g')
tmux_pane_escaped=$(printf '%s' "${TMUX_PANE:-}" | sed 's/\\/\\\\/g; s/"/\\"/g')

payload="{\"args\":${args_json},\"env\":{\"TMUX\":\"${tmux_escaped}\",\"TMUX_PANE\":\"${tmux_pane_escaped}\"}}"

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
