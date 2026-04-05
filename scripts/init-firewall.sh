#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# Network mode: false = whitelist only, true = allow all HTTPS (443)
ALLOW_WEB_ACCESS="${ALLOW_WEB_ACCESS:-false}"

# --open モードはネットワーク制限なし。iptables 設定をスキップ
if [ "$ALLOW_WEB_ACCESS" = "true" ]; then
    echo "Network mode: open (no restrictions)"
    exit 0
fi

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

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

iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Whitelist mode: fetch IP data BEFORE setting DROP policy
if [ "$ALLOW_WEB_ACCESS" = "false" ]; then
    echo "Network mode: whitelist"

    ipset create allowed-domains hash:net

    # Fetch GitHub meta information and aggregate + add their IP ranges
    echo "Fetching GitHub IP ranges..."
    gh_ranges=$(curl -s https://api.github.com/meta)
    if [ -z "$gh_ranges" ]; then
        echo "ERROR: Failed to fetch GitHub IP ranges"
        exit 1
    fi

    if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
        echo "ERROR: GitHub API response missing required fields"
        exit 1
    fi

    echo "Processing GitHub IPs..."
    while read -r cidr; do
        if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
            exit 1
        fi
        echo "Adding GitHub range $cidr"
        ipset add allowed-domains "$cidr"
    done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

    # Resolve and add other allowed domains
    for domain in \
        "registry.npmjs.org" \
        "api.anthropic.com" \
        "sentry.io" \
        "statsig.anthropic.com" \
        "statsig.com"; do
        echo "Resolving $domain..."
        ips=$(dig +noall +answer "$domain" | awk '$4 == "A" {print $5}')
        if [ -z "$ips" ]; then
            echo "ERROR: Failed to resolve $domain"
            exit 1
        fi

        while read -r ip; do
            if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "ERROR: Invalid IP from DNS for $domain: $ip"
                exit 1
            fi
            # /24 で登録し、同一サブネット内の IP 変動に対応
            local subnet="${ip%.*}.0/24"
            echo "Adding $subnet for $domain (resolved: $ip)"
            ipset add -exist allowed-domains "$subnet"
        done < <(echo "$ips")
    done

    # Load user-added domains from allowed-domains.txt
    ALLOWED_DOMAINS_FILE="/workspace/allowed-domains.txt"
    if [ -f "$ALLOWED_DOMAINS_FILE" ]; then
        echo "Loading user-added domains from allowed-domains.txt..."
        while IFS= read -r domain || [ -n "$domain" ]; do
            # Skip empty lines and comments
            [[ -z "$domain" || "$domain" =~ ^# ]] && continue
            echo "Resolving user domain: $domain"
            ips=$(dig +noall +answer +time=5 +tries=1 A "$domain" | awk '$4 == "A" {print $5}')
            if [ -z "$ips" ]; then
                echo "WARNING: Failed to resolve $domain - skipping"
                continue
            fi
            while read -r ip; do
                echo "Adding $ip for $domain"
                ipset add -exist allowed-domains "$ip"
            done <<< "$ips"
        done < "$ALLOWED_DOMAINS_FILE"
    fi
fi

# Set default policies to DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

if [ "$ALLOW_WEB_ACCESS" = "true" ]; then
    echo "Network mode: web access (HTTPS 443 open)"
    iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
else
    iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
fi

# Reject all other outbound traffic
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."

# Verify GitHub API is accessible (both modes)
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "WARNING: Firewall verification failed - unable to reach https://api.github.com"
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# In whitelist mode, verify example.com is blocked
if [ "$ALLOW_WEB_ACCESS" = "false" ]; then
    if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
        echo "ERROR: Firewall verification failed - was able to reach https://example.com"
        exit 1
    else
        echo "Firewall verification passed - unable to reach https://example.com as expected"
    fi
fi
