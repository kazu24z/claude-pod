#!/bin/bash
# PoC test: verify cmux socket communication from inside the container
# Run this INSIDE the container: bash /usr/local/bin/poc-cmux-test.sh

set -euo pipefail

CMUX_BRIDGE="${CMUX_BRIDGE:-}"
SOCKET="${CMUX_SOCKET_PATH:-/tmp/cmux.sock}"

# Helper: send JSON-RPC to cmux (TCP bridge or Unix socket)
cmux_send() {
    if [ -n "$CMUX_BRIDGE" ]; then
        local host port
        host=$(echo "$CMUX_BRIDGE" | cut -d: -f2)
        port=$(echo "$CMUX_BRIDGE" | cut -d: -f3)
        echo "$1" | socat -t5 - "TCP:${host}:${port}" 2>/dev/null
    else
        echo "$1" | socat -t5 - "UNIX-CONNECT:${SOCKET}" 2>/dev/null
    fi
}

echo "=== cmux Socket PoC Test ==="
echo ""

if [ -n "$CMUX_BRIDGE" ]; then
    echo "Mode: TCP bridge ($CMUX_BRIDGE)"
else
    echo "Mode: Unix socket ($SOCKET)"
fi
echo ""

# Test 1: Connectivity
echo "[1/4] Checking connectivity..."
if [ -n "$CMUX_BRIDGE" ]; then
    echo "  TCP bridge mode — skipping socket file check"
    echo "  OK"
elif [ -S "$SOCKET" ]; then
    echo "  OK: Socket exists"
else
    echo "  FAIL: Socket not found at $SOCKET"
    echo "  Ensure cmux is running and the socket is mounted."
    exit 1
fi

# Test 2: Ping
echo "[2/4] Sending ping..."
result=$(cmux_send '{"id":"poc-ping","method":"system.ping","params":{}}' || echo "FAIL")
if echo "$result" | grep -q '"ok":true'; then
    echo "  OK: Ping successful"
    echo "  Response: $result"
else
    echo "  FAIL: Ping failed"
    echo "  Response: $result"
    echo ""
    echo "  If empty/error, check CMUX_SOCKET_MODE=allowAll in cmux settings."
    exit 1
fi

# Test 3: Identify current surface
echo "[3/4] Identifying current surface..."
result=$(cmux_send '{"id":"poc-id","method":"system.identify","params":{}}' || echo "FAIL")
echo "  Response: $result"

# Test 4: Create a split and send a test command
echo "[4/4] Creating a split pane and sending test command..."
result=$(cmux_send '{"id":"poc-split","method":"surface.split","params":{"direction":"right"}}' || echo "FAIL")
if echo "$result" | grep -q '"ok":true'; then
    echo "  OK: Split created"
    echo "  Response: $result"
    sleep 1
    # Send a harmless test command to the new pane
    cmux_send '{"id":"poc-send","method":"surface.send_text","params":{"text":"echo hello from claude-pod container\n"}}' >/dev/null
    echo "  Sent 'echo hello from claude-pod container' to new pane"
else
    echo "  FAIL: Could not create split"
    echo "  Response: $result"
    exit 1
fi

echo ""
echo "=== All tests passed! cmux bridge is viable. ==="
