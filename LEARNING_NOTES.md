# Terraform 学習メモ

## Terraform とは

インフラ構成を `.tf` ファイルに書いておくと、その通りに AWS 上へリソースを
作る・変える・消してくれるツール。手動でコンソールをポチポチする代わりに、
コードで宣言する。

Terraform 自体は CLI ツール。Web画面（Terraform Cloud, Atlantis等）は、
この CLI 操作を裏側で実行して結果を見せてくれる仕組みに過ぎない。

## 3つの基本コマンド

1. `terraform init` — 使うプロバイダー（今回はAWS用プラグイン）をダウンロードする。最初の1回、または設定を変えた時に実行
2. `terraform plan` — 「これから何を作る・変える・消すか」を予告するだけ。何も実行しない
3. `terraform apply` — 実際にクラウド上へ適用する。ここで初めてリソースが作られる

**`apply` の前に必ず `plan` で予告を確認する**のが基本の流れ。

## 重要な概念

- **State（状態）**: Terraformが「今何を作ったか」を記録するファイル
  (`terraform.tfstate`)。これを見て、次の `plan` で何が変わったか判断する。
  中身にリソースIDなど実際の情報が入るので、**絶対にGitにコミットしない**。
- **Provider（プロバイダー）**: Terraform本体はクラウド非依存。「AWSを操作する」
  ための専用プラグインを `providers.tf` で明示的に指定する。
- **Resource（リソース）**: `resource "種類" "コード内での呼び名" { ... }`
  という書き方で、作りたいものを1つずつ宣言する。

## 今回作ったもの

`mcp-test/` ディレクトリに、AWS S3バケットを1つ作るだけの最小構成。

- `providers.tf`: AWSプロバイダーとリージョン(東京)の宣言
- `main.tf`: `aws_s3_bucket.sandbox` というリソースを1つ定義

`terraform init` → `terraform plan`(予告確認) → `terraform apply` の順で実行し、
実際に `hakusoft-mcp-test-sandbox` という名前のS3バケットが作成された。

## 気をつけたこと

- `.gitignore` で `*.tfstate` と `.terraform/` を除外（stateには機微な情報が
  入りうるため、絶対にコミットしない）
- `.terraform.lock.hcl` は逆に **コミットする**（プロバイダーのバージョンを
  固定するファイル。`package-lock.json` と同じ役割）
- S3バケット名はAWS全体で一意である必要がある

## 次にやること

- 作ったバケットを試しに `terraform destroy` で消してみる（作る/消すが
  コードだけで完結することを体感する）
- state を S3 に置く「リモートバックエンド」に移行する（今はローカルの
  `terraform.tfstate` のみ）
