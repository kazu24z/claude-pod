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

cpod() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true

  case "$cmd" in
    run)    _cpod_run "$@" ;;
    build)  _cpod_build ;;
    update) _cpod_update ;;
    help|--help|-h) _cpod_help ;;
    *)
      echo "Unknown command: $cmd" >&2
      _cpod_help >&2
      return 1
      ;;
  esac
}

_cpod_help() {
  cat << 'HELPEOF'
Usage: cpod <command> [options]

Commands:
  run [-p] [-t] [-- args...]  Launch Claude Code in a sandboxed container
  build                        Build/rebuild the claude-pod image
  update                       Pull latest changes and rebuild

Options for 'run':
  -p          Enable protected mode (domain whitelist)
  -t|--teams  Enable Agent Teams (requires cmux)
  -- args     Pass flags through to Claude Code

Examples:
  cpod run              Launch with no network restriction
  cpod run -p           Launch with domain whitelist protection
  cpod run -t           Launch with Agent Teams (cmux panes)
  cpod run -- --resume  Pass --resume to Claude Code
HELPEOF
}

# --- Agent Teams helpers (cpod run -t) ---

_cpod_teams_setup() {
  local project_dir="$1"
  local cmux_bridge_port=19876
  local cmux_bridge_log="${CLAUDE_POD_HOME}/.bridge.log"
  CMUX_BRIDGE_PID=""
  _CPOD_BRIDGE_STARTED=""

  if ! lsof -i ":${cmux_bridge_port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Starting cmux TCP bridge on port ${cmux_bridge_port}..."
    python3 "${CLAUDE_POD_HOME}/scripts/cmux-bridge.py" --port "$cmux_bridge_port" \
      >"$cmux_bridge_log" 2>&1 &
    CMUX_BRIDGE_PID=$!
    sleep 0.5
    if ! kill -0 "$CMUX_BRIDGE_PID" 2>/dev/null; then
      echo "ERROR: cmux bridge failed to start. Check $cmux_bridge_log" >&2
      return 1
    fi
    _CPOD_BRIDGE_STARTED=true
    echo "cmux bridge started (PID: $CMUX_BRIDGE_PID, log: $cmux_bridge_log)"
  else
    echo "cmux bridge already running on port ${cmux_bridge_port}"
  fi

  # cmux ヘルスチェック（ブリッジ経由で ping が通るか）
  if ! echo '{"id":"hc","method":"system.ping","params":{}}' | \
      nc -w3 127.0.0.1 "$cmux_bridge_port" 2>/dev/null | grep -q '"ok":true'; then
    echo "ERROR: cmux bridge started but cannot reach cmux. Is cmux running?" >&2
    [ -n "${_CPOD_BRIDGE_STARTED:-}" ] && kill "$CMUX_BRIDGE_PID" 2>/dev/null
    return 1
  fi
  echo "cmux health check passed"

  docker_args+=(
    --env "AGENT_TEAMS=1"
    --env "CMUX_BRIDGE=tcp:host.docker.internal:${cmux_bridge_port}"
    --env "HOST_PROJECT_DIR=${project_dir}"
  )
}

_cpod_teams_cleanup() {
  if [ -n "${_CPOD_BRIDGE_STARTED:-}" ] && [ -n "${CMUX_BRIDGE_PID:-}" ] && kill -0 "$CMUX_BRIDGE_PID" 2>/dev/null; then
    kill "$CMUX_BRIDGE_PID" 2>/dev/null
    echo "cmux bridge stopped (PID: $CMUX_BRIDGE_PID)"
  fi
}

# --- Main run command ---

_cpod_run() {
  local project_dir protected docker_args
  project_dir=$(pwd)
  protected=""
  teams=""

  # フラグパース
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) _cpod_help; return 0 ;;
      -p)       protected=true; shift ;;
      -t|--teams) teams=true; shift ;;
      --)       shift; break ;;
      -*)       echo "Unknown option: $1" >&2; return 1 ;;
      *)        break ;;
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

  if [ "$teams" = "true" ]; then
    _cpod_teams_setup "$project_dir" || return 1
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

  _cpod_teams_cleanup
}

_cpod_build() {
  echo "Building claude-pod:latest..."
  if docker build -t claude-pod:latest "$CLAUDE_POD_HOME"; then
    echo "Build complete: claude-pod:latest"
  else
    echo "ERROR: docker build failed" >&2
    return 1
  fi
}

_cpod_update() {
  echo "Updating claude-pod..."
  if ! git -C "$CLAUDE_POD_HOME" pull; then
    echo "ERROR: git pull failed" >&2
    return 1
  fi
  _cpod_build
}
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
