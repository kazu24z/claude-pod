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

# Generate config template if not exists
CLAUDE_POD_CONFIG_DIR="$HOME/.config/claude-pod"
mkdir -p "$CLAUDE_POD_CONFIG_DIR"
if [ ! -f "$CLAUDE_POD_CONFIG_DIR/config" ]; then
    cat > "$CLAUDE_POD_CONFIG_DIR/config" << 'CONFIGEOF'
# claude-pod security configuration
# PROTECTED=true で通信をドメインホワイトリストで制限
PROTECTED=false
CONFIGEOF
    echo "Created config template: $CLAUDE_POD_CONFIG_DIR/config"
fi

# 専用設定ファイルを生成（上書きで常に最新）
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" << 'ENVEOF'
# claude-pod: Claude Container dev environment helper
export CLAUDE_POD_HOME="__REPO_DIR__"

claude() {
  local project_dir protected docker_args
  project_dir=$(pwd)
  protected=""

  # フラグパース
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h)
        echo "Usage: claude [-p] [-- claude-args...]"
        echo ""
        echo "Launch Claude Code in a sandboxed container."
        echo ""
        echo "Options:"
        echo "  -p          Enable protected mode (domain whitelist)"
        echo "  -h, --help  Show this help message"
        echo ""
        echo "Examples:"
        echo "  claude              Launch with no network restriction"
        echo "  claude -p           Launch with domain whitelist protection"
        echo "  claude -- --resume  Pass flags to Claude Code"
        return 0
        ;;
      -p)     protected=true; shift ;;
      --)     shift; break ;;
      -*)     echo "Unknown option: $1" >&2; return 1 ;;
      *)      break ;;
    esac
  done

  # ユーザー設定読み込み（フラグ未指定時、grep でパース。source しない）
  if [ -z "$protected" ] && [ -f "$HOME/.config/claude-pod/config" ] && [ -r "$HOME/.config/claude-pod/config" ]; then
    protected=$(grep '^PROTECTED=' "$HOME/.config/claude-pod/config" | tail -1 | cut -d= -f2 | tr -d '"'"'")
  elif [ -z "$protected" ] && [ -f "$HOME/.config/claude-pod/config" ]; then
    echo "Warning: Cannot read ~/.config/claude-pod/config (permission denied). Using default." >&2
  fi
  protected="${protected:-false}"

  # バリデーション
  case "$protected" in
    true|false) ;;
    *) echo "Invalid PROTECTED value: $protected. Valid: true, false" >&2; return 1 ;;
  esac

  # docker run 引数の動的構築
  docker_args=(
    --rm -it
    --mount "type=bind,source=${HOME}/.claude,target=/home/user/.claude"
    --mount "type=tmpfs,destination=/home/user/.claude/skills/claude-pod"
    --mount "type=bind,source=${project_dir},target=/workspace"
    --mount "type=volume,source=mise-cache,target=/home/user/.local/share/mise"
    --workdir /workspace
    --env "HOST_UID=$(id -u)"
    --env "HOST_GID=$(id -g)"
    --entrypoint bash
  )

  # ユーザー定義の追加マウント（config の EXTRA_MOUNTS）
  if [ -f "$HOME/.config/claude-pod/config" ] && [ -r "$HOME/.config/claude-pod/config" ]; then
    local extra_mounts
    extra_mounts=$(grep '^EXTRA_MOUNTS=' "$HOME/.config/claude-pod/config" | tail -1 | cut -d= -f2- | tr -d '"'"'")
    if [ -n "$extra_mounts" ]; then
      eval "docker_args+=($extra_mounts)"
    fi
  fi

  if [ "$protected" = "true" ]; then
    docker_args+=(
      --cap-add NET_ADMIN
      --env "FIREWALL_MODE=l7"
    )
    [ -f "$HOME/.config/claude-pod/allowed-domains.txt" ] || touch "$HOME/.config/claude-pod/allowed-domains.txt"
    docker_args+=(--mount "type=bind,source=${HOME}/.config/claude-pod/allowed-domains.txt,target=/etc/claude-pod/allowed-domains.txt")
  else
    docker_args+=(--env "FIREWALL_MODE=none")
  fi

  docker run "${docker_args[@]}" claude-pod:latest -c '. /usr/local/bin/entrypoint.sh' _ "$@"
}

claude-pod() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true
  case "$cmd" in
    build)
      echo "Building claude-pod:latest..."
      if docker build -t claude-pod:latest "$CLAUDE_POD_HOME"; then
        echo "Build complete: claude-pod:latest"
      else
        echo "ERROR: docker build failed" >&2
        return 1
      fi
      ;;
    update)
      echo "Updating claude-pod..."
      if ! git -C "$CLAUDE_POD_HOME" pull; then
        echo "ERROR: git pull failed" >&2
        return 1
      fi
      echo "Building claude-pod:latest..."
      if docker build -t claude-pod:latest "$CLAUDE_POD_HOME"; then
        echo "Build complete: claude-pod:latest"
      else
        echo "ERROR: docker build failed" >&2
        return 1
      fi
      ;;
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
