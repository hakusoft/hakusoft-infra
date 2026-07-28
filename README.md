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

`.github/workflows/` に 3 本。**対象ディレクトリはワークフローごとに異なる。**

| ワークフロー | 契機 | 対象 | 内容 |
| --- | --- | --- | --- |
| `terraform-check.yml` | PR / `main` push | 両方 | `fmt` / `validate` |
| `terraform-plan.yml` | PR | 両方 | `plan` を実行しディレクトリごとに PR へコメント |
| `terraform-apply.yml` | `main` への push | `mcp-test` のみ | `apply` |

`odds-resolver` の **apply だけは手元で実行する**。自動 apply には CI ロールへ
IAM の `CreateRole` / `PassRole` を渡す必要があり、「CI が自分より強い権限を作れる」
経路になるため、そこは人間の手に残している（#15）。plan は読み取りのみなので CI に載せてよい。

権限は plan / apply で別々の IAM Role に分離し、認証は OIDC による一時認証情報を使う。
設計の理由と仕組みは [mcp-test/README.md](mcp-test/README.md) に書いている。

## 運用ルール

- `main` への直接 push は禁止（ブランチ保護で PR 経由のみ）
- Issue 起点 → ブランチ → 実装 → PR → CI 確認 → セルフレビュー → 人間のレビュー・マージ
- `apply` の自動実行は `main` マージ後のみ。PR の時点では `plan`（読み取り専用の予告）まで
- 秘匿値や取得元サイトの詳細はコミットしない
