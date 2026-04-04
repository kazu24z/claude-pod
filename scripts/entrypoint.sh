#!/bin/bash
set -euo pipefail

# Generate NOPASSWD sudoers for ipset and iptables
echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/ipset, /usr/sbin/iptables" \
    > /etc/sudoers.d/claude-pod-network
chmod 0440 /etc/sudoers.d/claude-pod-network

/usr/local/bin/init-firewall.sh

export HOME=/home/user
export CLAUDE_CONFIG_DIR=/home/user/.claude
exec gosu "${HOST_UID}:${HOST_GID}" /usr/local/bin/claude
