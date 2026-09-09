# 朝のチェック（morning-check）を GitHub Actions から回すためのロール（#35）。
#
# 手元の Claude Code からしか回せないと PC が起きている必要があるため、
# クラウドで自動実行できるようにする。
#
# ## なぜ GitHub Actions なのか（IAM ユーザーをやめた経緯）
#
# 当初は claude.ai のルーチンから直接 AWS を読む設計だった（#31）。
# ルーチン環境の実測では AWS への到達も boto3 の導入も可能で、読み取り専用の
# IAM ユーザーまで作った。だが**アクセスキーをルーチンへ渡す経路が無かった**:
#
#   - ルーチンの環境変数は API 経由でしか設定できない
#   - その API は Claude Code の OAuth トークンのスコープ外（404 / 403）
#   - 残る手段は会話にシークレットを貼ることだけで、それは避けたい
#
# GitHub Actions なら **OIDC で一時認証情報を取れるので鍵を持たなくてよい**。
# 既にこのリポジトリで実績のある仕組み（github_deploy / github_deploy_ingest）。
#
# 役割を分けるため既存ロールに相乗りせず、専用ロールを立てる。デプロイ用は
# 書き込みを持つが、こちらは**読み取りのみ**。
#
# ## 読み取り専用を保つ
#
# lambda:InvokeFunction は与えない。morning-check の付録にある recalc は
# 書き込みで、誤判断で過去日の calibration.json が焼き直されうる。
# 判定スクリプト（judge_forward）も 1 回きりで取り消せない（#106 の作法）。
# **取り消せない操作は無人環境に置かない。**

resource "aws_iam_role" "github_morning_check" {
  name = "${local.name}-github-morning-check"
  # IAM の description は ASCII のみ（日本語を入れると ValidationError）
  description        = "Lets GitHub Actions read metrics and data for the morning check"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

# morning-check が実際に使う操作のうち、読み取りだけを与える。
# リソースも既存の github_deploy_ingest と同じく ARN で絞る。
data "aws_iam_policy_document" "github_morning_check" {
  # Lambda の設定読み取り。DATA_BUCKET の解決と Timeout の確認に使う。
  statement {
    sid     = "ReadLambdaConfig"
    actions = ["lambda:GetFunctionConfiguration"]
    resources = [
      aws_lambda_function.fetch.arn,
      aws_lambda_function.morning.arn,
      aws_lambda_function.archive.arn,
      aws_lambda_function.read_api.arn,
    ]
  }

  # 当日の器（DAY#YYYYMMDD）。Query のみで Scan も書き込みも与えない。
  statement {
    sid       = "QueryHotTable"
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.hot.arn]
  }

  # 較正・前向きログ・レースの生データ。data バケットのみ
  # （フロント配信用バケットは含めない）。
  statement {
    sid       = "ListDataBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]
  }

  statement {
    sid       = "ReadDataObjects"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }

  # Lambda のエラーログ。ロググループを odds-resolver の 4 関数に絞る。
  statement {
    sid     = "ReadLambdaLogs"
    actions = ["logs:FilterLogEvents", "logs:DescribeLogGroups"]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name}-*",
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name}-*:*",
    ]
  }

  # **この 2 つはリソース指定が効かない**（IAM の仕様で * になる）。
  # 読み取り専用なので許容するが、ここだけ全リソースが対象になる。
  #
  #   cloudwatch:GetMetricStatistics — Lambda のエラー数・呼び出し数
  #   events:ListRules               — EventBridge の 4 本が ENABLED か
  statement {
    sid = "ReadMetricsAndRules"
    actions = [
      "cloudwatch:GetMetricStatistics",
      "events:ListRules",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_morning_check" {
  name   = "morning-check-readonly"
  role   = aws_iam_role.github_morning_check.id
  policy = data.aws_iam_policy_document.github_morning_check.json
}
