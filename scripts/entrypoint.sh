#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/iptables, /usr/sbin/squid" \
    > /etc/sudoers.d/claude-pod-network
chmod 0440 /etc/sudoers.d/claude-pod-network

# nsswitch.conf: systemd plugin fails in container, force files-only
sed -i 's/^passwd:.*/passwd: files/' /etc/nsswitch.conf
sed -i 's/^group:.*/group: files/' /etc/nsswitch.conf

# Add HOST_UID to /etc/passwd (direct write, bypass useradd issues)
if ! awk -F: -v uid="${HOST_UID}" '$3==uid{found=1}END{exit !found}' /etc/passwd; then
    printf 'user:x:%s:0::/home/user:/bin/bash\n' "${HOST_UID}" >> /etc/passwd
fi

/usr/local/bin/init-firewall.sh < /dev/null

if [ -d /usr/local/share/claude-pod/skills ]; then
    mkdir -p /home/user/.claude/skills/claude-pod
    cp /usr/local/share/claude-pod/skills/* /home/user/.claude/skills/claude-pod/
fi

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
