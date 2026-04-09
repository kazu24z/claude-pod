#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =====================================================
# entrypoint.sh - Claude Pod container entrypoint
# Branches initialization based on FIREWALL_MODE
#
# Architecture:
#   sandbox-core : Firewall, user mapping, proxy (tool-agnostic)
#   adapter      : Tool-specific setup (Claude Code by default)
# =====================================================

# --- Sandbox core: common processing (all modes) ---

export HOME=/home/user

# Symlink host-config files to / as fallback (some tools override HOME=/)
[ -f /home/user/.gitconfig ] && ln -sf /home/user/.gitconfig /.gitconfig

# Ensure .ssh directory exists (for known_hosts mount and ssh-agent)
mkdir -p /home/user/.ssh && chmod 700 /home/user/.ssh && chown "${HOST_UID}:${HOST_GID}" /home/user/.ssh

# Add user to /etc/passwd if not present (required by ssh, sudo, etc.)
if ! awk -F: -v uid="${HOST_UID}" '$3==uid{found=1}END{exit !found}' /etc/passwd; then
    printf 'user%s:x:%s:%s::/home/user:/bin/bash\n' "${HOST_UID}" "${HOST_UID}" "${HOST_GID}" >> /etc/passwd
fi

# --- Adapter: tool-specific setup ---

SANDBOX_CMD="${SANDBOX_CMD:-/usr/local/bin/claude}"

# Claude Code adapter (skip if running a different tool)
if [ "$SANDBOX_CMD" = "/usr/local/bin/claude" ]; then
    # Symlink /.claude -> /home/user/.claude (Claude Code looks for /.claude when HOME=/)
    ln -sf /home/user/.claude /.claude

    # Copy skill files into user config
    if [ -d /usr/local/share/claude-pod/skills ]; then
        mkdir -p /home/user/.claude/skills/claude-pod
        cp /usr/local/share/claude-pod/skills/* /home/user/.claude/skills/claude-pod/
    fi

    export CLAUDE_CONFIG_DIR=/home/user/.claude

    # Force git to use HTTPS instead of SSH (security: eliminates SSH tunnel bypass)
    # Uses --system (/etc/gitconfig) because ~/.gitconfig is bind-mounted readonly
    if command -v gh >/dev/null 2>&1 && [ -f /home/user/.config/gh/hosts.yml ]; then
        git config --system credential."https://github.com".helper '!/usr/bin/gh auth git-credential'
    fi
    git config --system url."https://github.com/".insteadOf "git@github.com:"
    git config --system --add url."https://github.com/".insteadOf "ssh://git@github.com/"
fi

# --- Agent Teams setup (optional, -t flag only) ---

AGENT_TEAMS="${AGENT_TEAMS:-}"
if [ "$AGENT_TEAMS" = "1" ]; then
    . /usr/local/bin/init-teams.sh
fi

# --- FIREWALL_MODE branching ---

FIREWALL_MODE="${FIREWALL_MODE:-}"

case "$FIREWALL_MODE" in
    none|"")
        # No network restrictions - container isolation only
        ;;
    l7)
        # Capability check
        if ! iptables -L -n >/dev/null 2>&1; then
            echo "ERROR: FIREWALL_MODE=${FIREWALL_MODE} requires NET_ADMIN capability. Add --cap-add NET_ADMIN to docker run." >&2
            exit 1
        fi

        # sudoers setup for squid reload only (iptables runs as root in entrypoint)
        echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/squid -k reconfigure" \
            > /etc/sudoers.d/claude-pod-network
        chmod 0440 /etc/sudoers.d/claude-pod-network

        # Add user to /etc/shadow if not present (required for sudo)
        if ! awk -F: -v uid="user${HOST_UID}" '$1==uid{found=1}END{exit !found}' /etc/shadow; then
            printf 'user%s:!:19000:0:99999:7:::\n' "${HOST_UID}" >> /etc/shadow
        fi

        /usr/local/bin/init-l7.sh < /dev/null

        # Proxy environment variables (L7 only - forces traffic through Squid)
        export http_proxy=http://127.0.0.1:3128 \
            https_proxy=http://127.0.0.1:3128 \
            HTTP_PROXY=http://127.0.0.1:3128 \
            HTTPS_PROXY=http://127.0.0.1:3128 \
            no_proxy=127.0.0.1,localhost \
            NO_PROXY=127.0.0.1,localhost
        ;;
    *)
        echo "ERROR: Unknown FIREWALL_MODE: ${FIREWALL_MODE}. Valid values: none, l7" >&2
        exit 1
        ;;
esac

# コンテナ識別表示
if [ -n "${CPOD_NAME:-}" ]; then
    printf '\033]0;%s\033\\' "$CPOD_NAME"
    echo "📦 $CPOD_NAME"
fi

exec gosu "${HOST_UID}:${HOST_GID}" "${SANDBOX_CMD}" "$@"
