# hakusoft-infra

hakusoft の各プロジェクト向け AWS リソースを Terraform で管理するモノレポ。
サービスごとにディレクトリを分け、state もディレクトリ単位で分離している。

## プロジェクト

| ディレクトリ | 対象 | 詳細 |
| --- | --- | --- |
| [`odds-resolver/`](odds-resolver/) | [odds-resolver](https://github.com/hakusoft/odds-resolver)（競馬オッズ可視化サイト）のインフラ一式 | [README](odds-resolver/README.md) |
| [`mcp-test/`](mcp-test/) | Terraform / CI・OIDC の検証用サンドボックス | [README](mcp-test/README.md) |

各ディレクトリのリソース構成・運用手順はそれぞれの README を参照。
このファイルにはリポジトリ全体に共通する事柄だけを置く。

## CI/CD

`.github/workflows/` に 3 本。**現時点の対象は `mcp-test/` ディレクトリのみ**で、
`odds-resolver/` は手元 `terraform apply` で運用している（CI 対象化は #15）。

| ワークフロー | 契機 | 内容 |
| --- | --- | --- |
| `terraform-check.yml` | PR | `fmt` / `validate` |
| `terraform-plan.yml` | PR | `plan` を実行し結果を PR にコメント |
| `terraform-apply.yml` | `main` への push | `apply` |

権限は plan / apply で別々の IAM Role に分離し、認証は OIDC による一時認証情報を使う。
設計の理由と仕組みは [mcp-test/README.md](mcp-test/README.md) に書いている。

## 運用ルール

- `main` への直接 push は禁止（ブランチ保護で PR 経由のみ）
- Issue 起点 → ブランチ → 実装 → PR → CI 確認 → セルフレビュー → 人間のレビュー・マージ
- `apply` の自動実行は `main` マージ後のみ。PR の時点では `plan`（読み取り専用の予告）まで
- 秘匿値や取得元サイトの詳細はコミットしない
