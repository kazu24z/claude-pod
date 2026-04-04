#!/bin/bash
# Usage: ./setup.sh /path/to/project
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Directory not found: $PROJECT_DIR"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$PROJECT_DIR/.claude-container"

if [ -d "$TARGET_DIR" ]; then
    echo "ERROR: $TARGET_DIR already exists. Run: claude-pod update"
    exit 1
fi

mkdir -p "$TARGET_DIR"

cp "$REPO_DIR/Dockerfile" "$TARGET_DIR/"
cp "$SCRIPT_DIR/init-firewall.sh" "$TARGET_DIR/"
cp "$SCRIPT_DIR/entrypoint.sh" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/init-firewall.sh" "$TARGET_DIR/entrypoint.sh"

cat > "$TARGET_DIR/compose.yml" << 'COMPOSE'
services:
  claude:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - "${HOME}/.claude:/home/user/.claude"
      - "..:/workspace"
      - "./init-firewall.sh:/usr/local/bin/init-firewall.sh"
      - "./entrypoint.sh:/usr/local/bin/entrypoint.sh"
    working_dir: /workspace
    environment:
      - HOST_UID=${HOST_UID}
      - HOST_GID=${HOST_GID}
      - ALLOW_WEB_ACCESS=false
    cap_add:
      - NET_ADMIN
      - NET_RAW
    stdin_open: true
    tty: true
    command: /usr/local/bin/entrypoint.sh
COMPOSE

cat > "$TARGET_DIR/mise.toml" << 'MISE'
[tools]
# 必要なランタイムをここに追加
# node = "22"
# python = "3.12"
# bun = "latest"
MISE

echo "Setup complete: $TARGET_DIR"
echo ""
echo "次のステップ:"
echo "  1. $TARGET_DIR/mise.toml にランタイムを追加"
echo "  2. HTTPS 全開放が必要なら claude-pod run --open で起動"
echo "  3. cd $PROJECT_DIR && claude-pod build && claude-pod run"
