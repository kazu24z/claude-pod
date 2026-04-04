#!/bin/bash
# Install claude-pod to ~/.config/claude-pod/env.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$HOME/.config/claude-pod/env.sh"

# シェルに応じてRCファイルを選択
if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
  RC_FILE="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ] || [ "$(basename "$SHELL")" = "bash" ]; then
  RC_FILE="$HOME/.bashrc"
else
  echo "ERROR: Unsupported shell. Please add claude-pod manually to your shell config."
  exit 1
fi

# 専用設定ファイルを生成（上書きで常に最新）
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" << EOF
# claude-pod: Claude Container dev environment helper
export CLAUDE_POD_HOME="$REPO_DIR"
claude-pod() {
  local cmd="\${1:-help}"
  shift 2>/dev/null || true
  case "\$cmd" in
    setup)  "\$CLAUDE_POD_HOME/scripts/setup.sh" "\$@" ;;
    update) "\$CLAUDE_POD_HOME/scripts/update.sh" "\$@" ;;
    run)    "\$CLAUDE_POD_HOME/scripts/run.sh" "\$@" ;;
    build)  "\$CLAUDE_POD_HOME/scripts/build.sh" "\$@" ;;
    *)
      echo "Usage: claude-pod <setup|update|run|build> [options]"
      echo "  setup  - Set up Claude Container for a project"
      echo "  update - Update existing Claude Container config"
      echo "  run    - Run Claude Container in a project (--open to allow full HTTPS)"
      echo "  build  - Build Claude Container image"
      ;;
  esac
}
alias cpod='claude-pod'
EOF

# RCファイルへの読み込み行を追記（重複しない）
SOURCE_LINE="[ -f \"$CONFIG_FILE\" ] && source \"$CONFIG_FILE\""
if ! grep -qF "$CONFIG_FILE" "$RC_FILE" 2>/dev/null; then
  echo "" >> "$RC_FILE"
  echo "# claude-pod" >> "$RC_FILE"
  echo "$SOURCE_LINE" >> "$RC_FILE"
  echo "Added source line to $RC_FILE"
else
  echo "Source line already exists in $RC_FILE"
fi

echo "Installed claude-pod to $CONFIG_FILE"
echo "Run: source $RC_FILE"
