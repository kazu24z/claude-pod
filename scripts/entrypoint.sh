#!/bin/bash
set -euo pipefail

/usr/local/bin/init-firewall.sh

export HOME=/home/user
export CLAUDE_CONFIG_DIR=/home/user/.claude
exec gosu "${HOST_UID}:${HOST_GID}" /usr/local/bin/claude
