#!/bin/bash
# Usage: ./update.sh /path/to/project
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"

TARGET_DIR="$PROJECT_DIR/.claude-container"

if [ ! -d "$TARGET_DIR" ]; then
    echo "ERROR: $TARGET_DIR not found. Run: claude-pod setup"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cp "$REPO_DIR/Dockerfile" "$TARGET_DIR/"
cp "$SCRIPT_DIR/init-firewall.sh" "$TARGET_DIR/"
cp "$SCRIPT_DIR/entrypoint.sh" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/init-firewall.sh" "$TARGET_DIR/entrypoint.sh"

# Copy skills
if [ -d "$SCRIPT_DIR/skills" ]; then
    mkdir -p "$TARGET_DIR/skills"
    cp -r "$SCRIPT_DIR/skills/." "$TARGET_DIR/skills/"
fi

if [ ! -f "$TARGET_DIR/mise.toml" ]; then
    cat > "$TARGET_DIR/mise.toml" << 'MISE'
[tools]
# 必要なランタイムをここに追加
# node = "22"
# python = "3.12"
# bun = "latest"
MISE
fi

echo "Updated: $TARGET_DIR"
echo ""
echo "NOTE: compose.yml は更新されていません。"
echo "手動で更新するか、削除後に claude-pod setup を再実行してください。"
