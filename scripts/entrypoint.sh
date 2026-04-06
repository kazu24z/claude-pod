#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/squid" \
    > /etc/sudoers.d/claude-pod-network
chmod 0440 /etc/sudoers.d/claude-pod-network

if ! getent passwd "${HOST_UID}" > /dev/null 2>&1; then
    echo "user:x:${HOST_UID}:${HOST_GID}::/home/user:/bin/bash" >> /etc/passwd
    echo "user:x:${HOST_GID}:" >> /etc/group
fi

/usr/local/bin/init-firewall.sh < /dev/null

if [ -d /usr/local/share/claude-pod/skills ]; then
    mkdir -p /home/user/.claude/skills/claude-pod
    cp /usr/local/share/claude-pod/skills/* /home/user/.claude/skills/claude-pod/
fi

export HOME=/home/user \
    CLAUDE_CONFIG_DIR=/home/user/.claude \
    http_proxy=http://127.0.0.1:3128 \
    https_proxy=http://127.0.0.1:3128 \
    HTTP_PROXY=http://127.0.0.1:3128 \
    HTTPS_PROXY=http://127.0.0.1:3128 \
    no_proxy=127.0.0.1,localhost \
    NO_PROXY=127.0.0.1,localhost

exec gosu "${HOST_UID}:${HOST_GID}" /usr/local/bin/claude "$@"
