#!/bin/bash
# Usage: ./run.sh /path/to/project [--open]
set -euo pipefail

WEB_ACCESS="false"
PROJECT_DIR=""

for arg in "$@"; do
    if [ "$arg" = "--open" ]; then
        WEB_ACCESS="true"
    elif [ -z "$PROJECT_DIR" ]; then
        PROJECT_DIR="$arg"
    fi
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

TARGET_DIR="$PROJECT_DIR/.claude-container"

if [ ! -f "$TARGET_DIR/compose.yml" ]; then
    echo "ERROR: $TARGET_DIR/compose.yml not found. Run: claude-pod setup"
    exit 1
fi

# イメージが存在するか確認
IMAGE_NAME=$(docker compose -f "$TARGET_DIR/compose.yml" config --images 2>/dev/null | head -1)
if [ -n "$IMAGE_NAME" ] && ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "ERROR: Docker image not built yet. Run: claude-pod build"
    exit 1
fi

HOST_UID=$(id -u) HOST_GID=$(id -g) ALLOW_WEB_ACCESS="$WEB_ACCESS" docker compose -f "$TARGET_DIR/compose.yml" run --rm claude
