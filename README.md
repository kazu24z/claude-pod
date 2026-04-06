# claude-pod

Claude Code をコンテナ内で安全に実行するための環境です。
ネットワークをホワイトリストで制限し、ホスト環境を汚さずに Claude Code を使えます。

## セットアップ

**動作環境:** macOS / Linux (Ubuntu 確認済み)

```bash
git clone <this-repo>
cd claude-pod
./install.sh
source ~/.zshrc  # bash の場合は ~/.bashrc
```

## 使い方

任意のプロジェクトディレクトリで：

```bash
claude              # whitelist モードで起動
```

### イメージの管理

```bash
claude-pod build    # イメージを再ビルド（cpod build でも可）
claude-pod update   # git pull + 再ビルド（cpod update でも可）
```

## ファイル構成

```
claude-pod/
├── install.sh              # claude/claude-pod コマンドをシェルに登録 + イメージビルド
├── Dockerfile              # グローバルイメージ定義
└── scripts/
    ├── init-firewall.sh    # iptables ファイアウォール構築
    └── skills/
        └── network-whitelist.md
```

## ネットワークモード

### whitelist モード（デフォルト）

```bash
claude
```

GitHub / npm / Anthropic API など Claude Code の動作に必要なドメインのみ外部通信を許可します。それ以外はブロックされます。

## ネットワーク制限の解除（ドメイン追加）

whitelist モードでコマンドがネットワーク制限に引っかかった場合、`allowed-domains.txt` にドメインを追記することで通信を許可できます。

### allowed-domains.txt

プロジェクトルートに `allowed-domains.txt` を配置：

```
# コメント行（# で始まる行はスキップ）
proxy.golang.org
sum.golang.org
```

コンテナ起動時に Squid の ACL として自動で読み込まれます。追加後は `sudo squid -k reconfigure` を実行すると即時反映されます。

## ネットワークホワイトリストスキル

whitelist モードでコマンドがネットワーク制限に引っかかった場合、Claude Code が自動的に検出してドメインをホワイトリストへ追加できます。
