# claude-pod

Claude Code をコンテナ内で実行する環境。protected モードではドメインホワイトリストによるネットワーク制限を適用できる。

## セットアップ

動作環境: macOS / Linux（Docker 必須）

```bash
git clone <this-repo>
cd claude-pod
./install.sh
source ~/.zshrc  # bash の場合は ~/.bashrc
```

`install.sh` は以下を行う:

1. `~/.config/claude-pod/` に設定ファイルを生成
2. `claude` / `claude-pod` / `cpod` コマンドをシェルに登録
3. `claude-pod:latest` Docker イメージをビルド

## 使い方

任意のプロジェクトディレクトリで実行する。

### デフォルト（ネットワーク制限なし）

```bash
claude
```

コンテナ隔離のみ。ネットワーク制限はかからない。

### protected モード（ドメインホワイトリスト）

```bash
claude -p
```

Squid プロキシ + iptables により、許可されたドメインへの通信のみ許可する。GitHub / npm / Anthropic API など Claude Code の動作に必要なドメインはデフォルトで許可済み。

### Agent Teams モード（cmux 連携）

```bash
cpod run -t
cpod run -t -p    # protected モードとの併用も可
```

[cmux](https://cmux.com) 上で実行すると、Claude Code の Agent Teams 機能でサブエージェントが cmux のネイティブ pane として起動する。各 teammate は独立したコンテナで実行される。

前提条件:
- cmux がインストール済みで起動していること
- cmux のターミナル上で `cpod run -t` を実行すること

仕組み: コンテナ内の tmux コマンドを TCP ブリッジ経由でホスト側の cmux に中継する。ブリッジは `cpod run -t` 実行時に自動で起動・停止する。

### Claude Code にフラグを渡す

```bash
claude -- --resume
claude -p -- --resume
```

`--` 以降の引数は Claude Code にそのまま渡される。

### ヘルプ

```bash
claude -h
```

## 設定

設定ファイルは `~/.config/claude-pod/` に格納される。

### config

```bash
# デフォルトで protected モードを有効にする
PROTECTED=true
```

`PROTECTED=true` に設定すると、`-p` フラグなしでも常に protected モードで起動する。`-p` フラグは config の設定に関わらず protected モードを有効にする。

### allowed-domains.txt

protected モードで追加のドメインを許可する場合に使用する。

```
# コメント行
proxy.golang.org
sum.golang.org
registry.yarnpkg.com
```

コンテナ起動時に Squid の ACL として読み込まれる。

## ドメインの追加

protected モードでコマンドがネットワーク制限に引っかかった場合、2つの方法でドメインを追加できる。

### network-whitelist スキル（自動検出）

protected モードのコンテナ内で、Claude Code がネットワークエラーを検出すると `network-whitelist` スキルが自動的に起動し、ドメインの追加を提案する。手動で呼び出すこともできる:

```
/skill network-whitelist
エラー出力: dial tcp: lookup proxy.golang.org on ...: no such host
```

スキルは以下を行う:

1. エラー出力からドメインを抽出
2. ユーザーに確認
3. `allowed-domains.txt` に追記
4. `sudo squid -k reconfigure` で即時反映

### 手動追加

`~/.config/claude-pod/allowed-domains.txt` にドメインを追記し、コンテナ内で再読み込みする:

```bash
# ホスト側
echo "proxy.golang.org" >> ~/.config/claude-pod/allowed-domains.txt

# コンテナ内で即時反映
sudo squid -k reconfigure
```

コンテナを再起動しても反映される。

## イメージ管理

```bash
claude-pod build    # イメージを再ビルド
claude-pod update   # git pull + 再ビルド
cpod build          # claude-pod のエイリアス
cpod update
```

## ファイル構成

```
claude-pod/
├── install.sh              # claude/claude-pod コマンドをシェルに登録 + イメージビルド
├── Dockerfile              # グローバルイメージ定義（Ubuntu 24.04 ベース）
└── scripts/
    ├── entrypoint.sh       # コンテナ起動時の初期化（FIREWALL_MODE で分岐）
    ├── init-l7.sh          # Squid + iptables 設定（protected モード）
    ├── init-teams.sh       # Agent Teams 初期化（tmux shim + cmux ID 取得）
    ├── tmux-shim.sh        # コンテナ内 tmux → ホスト cmux ブリッジ転送
    ├── cmux-bridge.py      # TCP ブリッジ（ホスト側で実行、cmux socket 中継）
    └── skills/
        └── SKILL.md        # network-whitelist スキル定義
```

```
~/.config/claude-pod/
├── config                  # PROTECTED=true/false
├── allowed-domains.txt     # ドメインホワイトリスト（protected モード用）
└── env.sh                  # claude() 関数定義（install.sh が生成）
```
