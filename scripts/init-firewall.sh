#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# Allow DNS, SSH, localhost
iptables -A OUTPUT -p udp -d 127.0.0.11 --dport 53 -j ACCEPT
iptables -A INPUT -p udp -s 127.0.0.11 --sport 53 -j ACCEPT

iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

SQUID_UID=$(id -u proxy 2>/dev/null) || { echo "ERROR: Failed to get proxy user UID"; exit 1; }
if [ -z "$SQUID_UID" ]; then
    echo "ERROR: Failed to get proxy user UID"
    exit 1
fi

iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Allow Squid process (proxy user) direct outbound access
iptables -A OUTPUT -m owner --uid-owner "$SQUID_UID" -j ACCEPT

# Set default policies to DROP (fail-safe: before Squid starts)
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Make stdout/stderr writable by Squid (proxy user)
chmod a+w /dev/stdout /dev/stderr 2>/dev/null || true

# Ensure allowed-domains.txt exists (required for squid -k reconfigure to work)
touch /workspace/allowed-domains.txt
sed -i 's/\r$//' /workspace/allowed-domains.txt

# Generate squid.conf
USER_DOMAINS_CONF="
acl user_domains dstdomain \"/workspace/allowed-domains.txt\""

USER_DOMAINS_ACCESS="
http_access allow CONNECT user_domains
http_access allow user_domains"

SQUID_CONF_CONTENT="http_port 3128

acl allowed_domains dstdomain .github.com
acl allowed_domains dstdomain .npmjs.org
acl allowed_domains dstdomain .anthropic.com
acl allowed_domains dstdomain .sentry.io
acl allowed_domains dstdomain .statsig.com
acl allowed_domains dstdomain .googleapis.com
acl allowed_domains dstdomain .claude.com${USER_DOMAINS_CONF}

http_access allow CONNECT allowed_domains${USER_DOMAINS_ACCESS}
http_access allow allowed_domains
http_access deny all

access_log none
cache_log /dev/null
cache_store_log none
cache deny all"

if ! printf '%s\n' "$SQUID_CONF_CONTENT" > /etc/squid/squid.conf; then
    echo "ERROR: Failed to write squid.conf" && exit 1
fi

# Start Squid in background
squid -N &
# shellcheck disable=SC2034
SQUID_PID=$!

# Wait for Squid to listen on port 3128 (timeout 10 seconds)
SQUID_TIMEOUT=50
SQUID_WAIT=0
until ss -lnt | grep -q ':3128'; do
    if [ "$SQUID_WAIT" -ge "$SQUID_TIMEOUT" ]; then
        echo "ERROR: Squid failed to start within timeout"
        exit 1
    fi
    sleep 0.2
    SQUID_WAIT=$((SQUID_WAIT + 1))
done
echo "Squid started and listening on port 3128"

# Export proxy environment variables for all processes
export http_proxy=http://127.0.0.1:3128
export https_proxy=http://127.0.0.1:3128
export HTTP_PROXY=http://127.0.0.1:3128
export HTTPS_PROXY=http://127.0.0.1:3128
export no_proxy=127.0.0.1,localhost
export NO_PROXY=127.0.0.1,localhost
echo "Proxy environment variables set: http_proxy=$http_proxy"

echo "Firewall + Squid configuration complete"
echo "Verifying firewall rules..."

# Verify GitHub API is accessible (both modes)
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "WARNING: Firewall verification failed - unable to reach https://api.github.com"
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# Verify example.com is blocked
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi
