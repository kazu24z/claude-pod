# claude-pod

Claude Code をコンテナ内で安全に実行するための環境設定テンプレートです。
特定プロジェクトのフォルダのみ Claude Code に見せることができます。

## セットアップ

**動作環境:** macOS / Linux (Ubuntu 確認済み) 

```bash
git clone <this-repo>
cd claude-pod
./install.sh
source ~/.zshrc  # bash の場合は ~/.bashrc
```

以降、`cpod` コマンドが使えます（`claude-pod` の短縮形）。

インストール後、任意のプロジェクトで：

```bash
claude-pod setup /path/to/your-project  # または cpod setup /path/to/your-project
# またはカレントディレクトリ
claude-pod setup  # または cpod setup
```

## ファイル構成

```
claude-pod/
├── install.sh          # claude-pod コマンドをシェルに登録
├── Dockerfile          # Claude Code ベースイメージ
└── scripts/
    ├── setup.sh        # プロジェクトへの初期セットアップ
    ├── build.sh        # Docker イメージのビルド
    ├── run.sh          # コンテナの起動
    ├── update.sh       # Dockerfile / スクリプト類の更新
    ├── init-firewall.sh
    └── entrypoint.sh
```

## セットアップ後のプロジェクト構成

```
your-project/
├── .claude-container/
│   ├── Dockerfile
│   ├── compose.yml
│   ├── mise.toml       # ランタイム・ツールをここに追加
│   ├── init-firewall.sh
│   └── entrypoint.sh
```

## 使い方

```bash
# ビルド
claude-pod build  # または cpod build

# 起動
claude-pod run  # または cpod run
```

## ランタイム・ツールの追加

`.claude-container/mise.toml` に必要なランタイムを追記してください。

```toml
[tools]
node = "22"
python = "3.12"
bun = "latest"
```

追記後は再ビルドが必要です：

```bash
claude-pod build  # または cpod build
```

## ネットワークモード

### whitelist モード（デフォルト）

```bash
claude-pod run  # または cpod run
```

以下のみ外部通信を許可します：

- GitHub（コード取得）
- `registry.npmjs.org`
- `api.anthropic.com`
- `sentry.io`, `statsig.com`（Claude Code テレメトリ）
- DNS / SSH

コンテナ起動時に `iptables` / `ipset` でファイアウォールを構築します。GitHub の IP レンジは起動時に [GitHub API](https://api.github.com/meta) から動的に取得します。その他のドメインは DNS 解決した IP をホワイトリストに登録します。

### open モード

```bash
claude-pod run --open  # または cpod run --open
```

HTTPS（443番ポート）を全開放します。

> **注意：** 任意の HTTPS 宛先への通信が可能になります。

## 既存プロジェクトの更新

`claude-pod` を `git pull` した後：

```bash
claude-pod update /path/to/your-project  # または cpod update /path/to/your-project
claude-pod build  # または cpod build
```

## ネットワークホワイトリストスキル

whitelist モードでコマンドがネットワーク制限に引っかかった場合、Claude Code が自動的に検出してドメインをホワイトリストへ追加できます。

### スキルの仕組み

1. Claude Code がコマンドのエラー出力から接続先ドメインを自動検出する
2. 追加するドメインと解決された IP アドレスをユーザーに提示する
3. 承認後、`sudo ipset add` でファイアウォールへ即時追加する
4. `/workspace/.claude-container/allowed-domains.txt` に永続化する
5. コンテナ再起動時に `allowed-domains.txt` を自動読み込みして復元する

### スキルの自動起動

コマンド実行後のエラー出力に `dial tcp`・`connection refused`・`no such host` 等が含まれる場合、Claude Code が自動的にスキルを呼び出します。

### スキルの手動呼び出し

```
/skill network-whitelist
エラー出力: dial tcp: lookup proxy.golang.org on ...: no such host
```

### --auto フラグ（確認なし）

```
/skill network-whitelist --auto
```

確認プロンプトを省略して即時追加します。

### allowed-domains.txt の手動編集

追加するドメインを手動で管理したい場合は、`.claude-container/allowed-domains.txt` を直接編集できます。

```
# コメント行（# で始まる行はスキップ）
proxy.golang.org
sum.golang.org
registry.npmjs.org
```

コンテナを再起動すると、ファイルに記載されたドメインが自動的に ipset に追加されます。

### セットアップ後のプロジェクト構成（スキル追加後）

```
your-project/
├── .claude-container/
│   ├── Dockerfile
│   ├── compose.yml
│   ├── mise.toml
│   ├── init-firewall.sh
│   ├── entrypoint.sh
│   ├── allowed-domains.txt   # スキル実行後に自動生成（手動編集も可）
│   └── skills/
│       └── network-whitelist.md
```
