---
description: L7 モード（ドメインホワイトリスト）のコンテナ内でネットワーク失敗エラーを検出し、必要なドメインを Squid プロキシの許可リストに追加して allowed-domains.txt に永続化する
---

# network-whitelist スキル

## 概要

L7 モード（ドメインホワイトリスト）の Claude Pod コンテナ内でコマンドのネットワーク接続失敗を検出し、必要なドメインを動的に Squid プロキシのドメイン許可リストへ追加する。永続化のため `/etc/claude-pod/allowed-domains.txt` にも記録する。

## 前提条件

このスキルは FIREWALL_MODE=l7 でコンテナが起動されている場合にのみ動作する。
Squid が稼働していない場合（FIREWALL_MODE=none または l34）は「このスキルは L7 モード（--firewall l7）でのみ動作します」と表示して終了すること。
確認方法: `ss -lnt | grep ':3128'` でポート 3128 が LISTEN されているかを確認する。

## 起動トリガー

コマンド実行の標準エラーに以下のいずれかが含まれる場合、このスキルを自動的に呼び出してエラー出力を渡すこと：

- `connection refused`
- `dial tcp`
- `no such host`
- `ECONNREFUSED`
- `could not connect`
- `Failed to connect`
- `network unreachable`

## 実行手順

### ステップ 1: エラー出力からドメインを抽出する

渡されたエラー出力テキストから、以下のパターンでドメイン名を抽出する。

抽出対象パターン（例）：
- `dial tcp: lookup proxy.golang.org` → `proxy.golang.org`
- `https://registry.npmjs.org:443/` → `registry.npmjs.org`
- `curl: (6) Could not resolve host: example.com` → `example.com`

ポート番号（`:443` 等）は除去してドメイン部分のみを抽出する。

抽出に失敗した場合（ドメイン名が見つからない場合）は次のメッセージを表示し、手動入力を求める：

```
ドメインを自動検出できませんでした。追加するドメインを手動で入力してください（例: registry.npmjs.org）:
```

### ステップ 2: バリデーション

抽出または入力されたドメインを RFC 1123 形式でバリデーションする。

有効なドメイン条件：
- 英数字・ハイフン・ドット（`.`）のみで構成される
- 各ラベルが英数字で始まり英数字で終わる
- 空文字でない
- 255 文字以内

無効な場合は「無効なドメイン名です: [domain]」とエラーを表示して再入力を求める。

`--auto` フラグが指定されており、抽出したドメインが無効な場合はバリデーションエラーを出力して手動入力モードにフォールバックする。

### ステップ 3: ユーザーへの確認（--auto 時はスキップ）

`--auto` フラグが指定されていない場合、以下の形式で内容を提示してユーザーに確認を求める：

```
以下のドメインを Squid 許可リストに追加します：

  ドメイン: <domain>

追加しますか？ (y/n):
```

複数ドメインが抽出された場合は全ドメインをリスト形式で一括提示する（個別選択はスコープ外）。

ユーザーが `n` または `no` を入力した場合は「キャンセルしました」と表示して終了する。

抽出されたドメイン数が 100 件を超える場合は WARNING を表示して処理を継続する：

```
WARNING: 100件を超えるドメインが検出されました（<n>件）。処理を継続します。
```

### ステップ 4: 重複チェック

Bash ツールで以下のコマンドを実行して、既に `allowed-domains.txt` に登録済みかを確認する：

```bash
grep -q "^${domain}$" /etc/claude-pod/allowed-domains.txt 2>/dev/null
```

既に登録済みの場合は「既に登録済みのためスキップ: [domain]」を出力し、`squid -k reconfigure` は実行しない。

### ステップ 5: allowed-domains.txt への永続化

Bash ツールで以下の処理を行う：

1. `/etc/claude-pod/allowed-domains.txt` にドメインを追記する（ファイルが存在しない場合は新規作成）：

```bash
echo "<domain>" >> /etc/claude-pod/allowed-domains.txt
```

書き込みに失敗した場合は次のメッセージを表示して終了し、`squid -k reconfigure` は実行しない：

```
警告: allowed-domains.txt への書き込みに失敗しました（権限を確認してください）。
```

この場合、終了コード 1 を返す。

### ステップ 6: Squid への設定再読み込み

Bash ツールで以下のコマンドを実行して Squid に ACL を再読み込みさせる：

```bash
sudo squid -k reconfigure
```

権限エラー（`sudo: a password is required` 等）が発生した場合は次のメッセージを表示して終了する：

```
エラー: sudo squid -k reconfigure の実行に失敗しました。
sudo NOPASSWD 設定を確認してください（Dockerfile の entrypoint.sh を参照）。
```

Squid プロセスが動作していない場合（`Squid is not running` 等）は次のメッセージを表示して終了する：

```
エラー: Squid is not running。コンテナを再起動してください。
```

### ステップ 7: 結果の出力

処理が正常に完了した場合、以下の形式で結果を出力する：

```
[<タイムスタンプ>] ドメインを追加しました: <domain>
  永続化: /etc/claude-pod/allowed-domains.txt
  Squid reconfigure: 完了

元のコマンドを再実行してください。
```

タイムスタンプは `date '+%Y-%m-%d %H:%M:%S'` で取得する。

## 使用例

### 通常モード（確認あり）

コマンドがネットワークエラーで失敗した場合、Claude Code がエラー出力を検出してこのスキルを自動呼び出しする。

または手動でスキルを呼び出す：

```
/skill network-whitelist
エラー出力: dial tcp: lookup proxy.golang.org on ...: no such host
```

### --auto モード（確認なし）

```
/skill network-whitelist --auto
エラー出力: <エラーテキスト>
```

## 注意事項

- このスキルはコンテナ内でのみ動作する。ホストの iptables には影響しない
- `allowed-domains.txt` にはドメイン名のみを記録する（IP アドレスは記録しない）
- `sudo squid -k reconfigure` は Squid プロセスを再起動せずに設定を再読み込みするため、実行中の接続は切断されない
- コンテナ再起動時に `init-l7.sh` が `allowed-domains.txt` を読み込んで自動的に Squid ACL に反映する
- CDN ドメインはドメイン名での管理により IP 変動の影響を受けない
