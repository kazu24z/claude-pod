#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/squid" \
    > /etc/sudoers.d/claude-pod-network
chmod 0440 /etc/sudoers.d/claude-pod-network

getent group "${HOST_GID}" > /dev/null 2>&1 || \
    groupadd --gid "${HOST_GID}" hostgroup 2>/dev/null || true
getent passwd "${HOST_UID}" > /dev/null 2>&1 || \
    useradd --uid "${HOST_UID}" --gid "${HOST_GID}" \
        --home /home/user --no-create-home \
        --shell /bin/bash \
        user 2>/dev/null || true
echo "DEBUG passwd: $(getent passwd "${HOST_UID}" || echo 'NOT FOUND')" >&2

/usr/local/bin/init-firewall.sh < /dev/null

if [ -d /usr/local/share/claude-pod/skills ]; then
    mkdir -p /home/user/.claude/skills/claude-pod
    cp /usr/local/share/claude-pod/skills/* /home/user/.claude/skills/claude-pod/
fi

gosu "${HOST_UID}:${HOST_GID}" env HOME=/home/user printenv HOME >&2
exec gosu "${HOST_UID}:${HOST_GID}" \
    env HOME=/home/user \
        CLAUDE_CONFIG_DIR=/home/user/.claude \
        http_proxy=http://127.0.0.1:3128 \
        https_proxy=http://127.0.0.1:3128 \
        HTTP_PROXY=http://127.0.0.1:3128 \
        HTTPS_PROXY=http://127.0.0.1:3128 \
        no_proxy=127.0.0.1,localhost \
        NO_PROXY=127.0.0.1,localhost \
    /usr/local/bin/claude "$@"
