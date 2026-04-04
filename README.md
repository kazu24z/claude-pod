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
claude --open       # ネットワーク制限なしで起動
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

以下のみ外部通信を許可します：

- GitHub（コード取得）
- `registry.npmjs.org`
- `api.anthropic.com`
- `sentry.io`, `statsig.com`（Claude Code テレメトリ）
- DNS / SSH

プロジェクトに `allowed-domains.txt` を置くと、追加ドメインも許可されます。

### open モード

```bash
claude --open
```

ネットワーク制限なしで起動します。

## ネットワークホワイトリストスキル

whitelist モードでコマンドがネットワーク制限に引っかかった場合、Claude Code が自動的に検出してドメインをホワイトリストへ追加できます。

### allowed-domains.txt

プロジェクトルートに `allowed-domains.txt` を配置：

```
# コメント行（# で始まる行はスキップ）
proxy.golang.org
sum.golang.org
```

コンテナ起動時に自動で ipset に追加されます。
