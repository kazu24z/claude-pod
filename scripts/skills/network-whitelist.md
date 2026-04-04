---
description: whitelist モードのコンテナ内でネットワーク失敗エラーを検出し、必要なドメインを ipset に追加して allowed-domains.txt に永続化する
---

# network-whitelist スキル

## 概要

whitelist モードの Claude Pod コンテナ内でコマンドのネットワーク接続失敗を検出し、必要なドメインを動的に ipset ホワイトリストへ追加する。永続化のため `/workspace/.claude-container/allowed-domains.txt` にも記録する。

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
IP アドレス（例: `192.168.1.1`）のみが含まれ、ドメイン名がない場合は「IP アドレスを直接 ipset に追加しますか？」とユーザーに確認する。

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

### ステップ 3: DNS 解決

Bash ツールで以下のコマンドを実行して IP アドレスを解決する：

```bash
dig +noall +answer +time=5 +tries=1 A <domain> | awk '$4 == "A" {print $5}'
```

A レコードが得られない場合（NXDOMAIN または空応答）は次のメッセージを表示して終了する：

```
DNS 解決に失敗しました: <domain>
```

`dig` コマンドが存在しない場合もエラーを出力して終了する。

### ステップ 4: ユーザーへの確認（--auto 時はスキップ）

`--auto` フラグが指定されていない場合、以下の形式で内容を提示してユーザーに確認を求める：

```
以下のドメイン・IP を ipset に追加します：

  ドメイン: <domain>
  IP アドレス: <ip1>, <ip2>, ...

追加しますか？ (y/n):
```

複数ドメインが抽出された場合は全ドメインをリスト形式で一括提示する（個別選択はスコープ外）。

ユーザーが `n` または `no` を入力した場合は「キャンセルしました」と表示して終了する。

抽出されたドメイン数が 100 件を超える場合は WARNING を表示して処理を継続する：

```
WARNING: 100件を超えるドメインが検出されました（<n>件）。処理を継続します。
```

### ステップ 5: ipset への追加

Bash ツールで以下のコマンドを実行する（解決された各 IP アドレスに対して）：

```bash
sudo ipset add -exist allowed-domains <ip>
```

権限エラー（`sudo: a password is required` 等）が発生した場合は次のメッセージを表示して終了する：

```
エラー: sudo ipset の実行に失敗しました。
sudo NOPASSWD 設定を確認してください（Dockerfile の entrypoint.sh を参照）。
```

`allowed-domains` ipset セットが存在しない場合（whitelist モード未使用）は次のメッセージを表示して終了する：

```
エラー: ipset セット 'allowed-domains' が存在しません。
whitelist モードで起動していません。ALLOW_WEB_ACCESS=false で起動してください。
```

### ステップ 6: allowed-domains.txt への永続化

Bash ツールで以下の処理を行う：

1. `/workspace/.claude-container/allowed-domains.txt` に既に同じドメインが記録されているか確認する：

```bash
grep -qxF "<domain>" /workspace/.claude-container/allowed-domains.txt 2>/dev/null
```

2. 既に記録済みの場合は「既に登録済みのためスキップ: [domain]」を出力する。

3. 未記録の場合はファイルに追記する（ファイルが存在しない場合は新規作成）：

```bash
echo "<domain>" >> /workspace/.claude-container/allowed-domains.txt
```

書き込みに失敗した場合は次のメッセージを表示する（ipset への追加は成功済みのためロールバックしない）：

```
警告: allowed-domains.txt への書き込みに失敗しました（権限を確認してください）。
ipset への追加は成功しています。コンテナ再起動後はドメインが失われます。
```

この場合、終了コード 1 を返す。

### ステップ 7: 結果の出力

処理が正常に完了した場合、以下の形式で結果を出力する：

```
[<タイムスタンプ>] ドメインを追加しました: <domain>
  追加した IP: <ip1>, <ip2>, ...
  永続化: /workspace/.claude-container/allowed-domains.txt

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
- コンテナ再起動時に `init-firewall.sh` が `allowed-domains.txt` を読み込んで自動的に IP を再解決・追加する
- CDN ドメインは再起動のたびに IP が変わる場合があるため、ドメイン名での管理が重要
