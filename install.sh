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
cat > "$CONFIG_FILE" << 'ENVEOF'
# claude-pod: Claude Container dev environment helper
export CLAUDE_POD_HOME="__REPO_DIR__"

claude() {
  local allow_web="false"
  local project_dir
  project_dir=$(pwd)

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --open) allow_web="true"; shift ;;
      --)     shift; break ;;
      -*)     echo "Unknown option: $1" >&2; return 1 ;;
      *)      break ;;
    esac
  done

  docker run --rm -it \
    --cap-add NET_ADMIN \
    --cap-add NET_RAW \
    --mount type=bind,source="${HOME}/.claude",target=/home/user/.claude \
    --mount type=bind,source="${project_dir}",target=/workspace \
    --mount type=volume,source=mise-cache,target=/home/user/.local/share/mise \
    --workdir /workspace \
    --env HOST_UID="$(id -u)" \
    --env HOST_GID="$(id -g)" \
    --env ALLOW_WEB_ACCESS="${allow_web}" \
    --entrypoint bash \
    claude-pod:latest \
    -c 'echo "user${HOST_UID} ALL=(ALL) NOPASSWD: /usr/sbin/ipset, /usr/sbin/iptables" > /etc/sudoers.d/claude-pod-network && chmod 0440 /etc/sudoers.d/claude-pod-network && /usr/local/bin/init-firewall.sh < /dev/null; export HOME=/home/user CLAUDE_CONFIG_DIR=/home/user/.claude; exec gosu ${HOST_UID}:${HOST_GID} /usr/local/bin/claude "$@"' _ "$@"
}

claude-pod() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true
  case "$cmd" in
    build)  docker build -t claude-pod:latest "$CLAUDE_POD_HOME" ;;
    update) git -C "$CLAUDE_POD_HOME" pull && docker build -t claude-pod:latest "$CLAUDE_POD_HOME" ;;
    *)
      echo "Usage: claude-pod <build|update>"
      echo "  build  - Build/rebuild the global claude-pod image"
      echo "  update - Pull latest changes and rebuild the image"
      ;;
  esac
}
alias cpod='claude-pod'
ENVEOF

# REPO_DIR のプレースホルダを実際のパスに置換
sed -i'' -e "s|__REPO_DIR__|$REPO_DIR|" "$CONFIG_FILE"

# RCファイルへの読み込み行を追記（重複しない）
SOURCE_LINE="[ -f \"$CONFIG_FILE\" ] && source \"$CONFIG_FILE\""
if ! grep -qF "$CONFIG_FILE" "$RC_FILE" 2>/dev/null; then
  { echo ""; echo "# claude-pod"; echo "$SOURCE_LINE"; } >> "$RC_FILE"
  echo "Added source line to $RC_FILE"
else
  echo "Source line already exists in $RC_FILE"
fi

# グローバルイメージをビルド
echo "Building claude-pod:latest..."
docker build -t claude-pod:latest "$REPO_DIR"

echo "Installed claude-pod to $CONFIG_FILE"
echo "Run: source $RC_FILE"
