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

### web access モード

```bash
claude-pod run --web  # または cpod run --web
```

上記に加えて HTTPS（443番ポート）を全開放します。Claude Code がドキュメントや外部情報を調査できるようになります。

> **注意：** 任意の HTTPS 宛先への通信が可能になります。

## 既存プロジェクトの更新

`claude-pod` を `git pull` した後：

```bash
claude-pod update /path/to/your-project  # または cpod update /path/to/your-project
claude-pod build  # または cpod build
```
