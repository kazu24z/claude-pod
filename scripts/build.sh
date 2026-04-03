#!/bin/bash
# Usage: ./build.sh /path/to/project
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"

TARGET_DIR="$PROJECT_DIR/.claude-container"

if [ ! -f "$TARGET_DIR/compose.yml" ]; then
    echo "ERROR: $TARGET_DIR/compose.yml not found. Run setup.sh first."
    exit 1
fi

docker compose -f "$TARGET_DIR/compose.yml" build
