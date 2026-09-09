# 朝のチェック（morning-check）をクラウドの Claude Routine で回すための
# 読み取り専用ユーザー（#31）。
#
# 手元の Claude Code からしか回せないと PC が起きている必要があるため、
# claude.ai のルーチン環境から観測できるようにする。
#
# ## 実行環境の実測（2026-09-09）
#
# ルーチン環境には egress プロキシがあり、**組織ポリシーの許可リスト**で
# 宛先が絞られている。実測では:
#
#   *.amazonaws.com  到達可（S3 307 / DynamoDB 200 / STS 302 ほか）
#   api.github.com   到達可（200）
#   pypi.org         到達可（aws CLI は無いが boto3 を pip で入れられる）
#   CloudFront       **遮断**（CONNECT が organization policy で拒否）
#   任意ドメイン     遮断（example.com も同様）
#
# **CloudFront が使えないので、配信物（days.json / calibration.json）は
# S3 から直接読む。** 配信経路の確認（キャッシュ・invalidation 漏れの検出）は
# クラウド側では行えないので、それは手元の morning-check が担う。
#
# ## アクセスキーは Terraform で作らない
#
# `aws_iam_access_key` を使うと **state に平文で残る**。ユーザーとポリシーだけを
# ここで作り、キーはコンソールか CLI で手動発行してルーチンの環境変数に入れる。
# 止めたくなった時に Terraform を触らずコンソールで無効化できる利点もある。

resource "aws_iam_user" "morning_check" {
  name = "${local.name}-morning-check"
  # IAM の description は使えないため tags で意図を残す。
  # **タグの値は [\p{L}\p{Z}\p{N}_.:/=+\-@] のみ。`#` は使えない**
  # （2026-09-09 の apply が "hakusoft-infra#31" で ValidationError になった）。
  # 日本語は通るが、他のリソースに合わせて ASCII にしておく。
  tags = {
    Purpose = "Read-only observation for the morning check routine"
    Issue   = "hakusoft-infra-31"
  }
}

# morning-check が実際に使う操作だけを与える。
#
# **lambda:InvokeFunction は与えない。** morning-check の付録にある recalc
# （S3 起点で集計をやり直す）は書き込みで、誤判断で過去日の calibration.json が
# 焼き直されうる。復旧操作は人間の手元に残す。
#
# 同じ理由で、判定スクリプト（judge_forward など）の実行もクラウドでは行わない。
# あれは 1 回きりで取り消せない（#106 の作法）。
data "aws_iam_policy_document" "morning_check" {
  # Lambda の設定読み取り。DATA_BUCKET の解決と Timeout の確認に使う。
  # 4 関数に限定する（github_deploy_ingest と同じ絞り方）。
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

  # 当日の器（DAY#YYYYMMDD）と、レース単位のスナップショット（RACE#...）。
  # Query のみ。Scan も書き込みも与えない。
  statement {
    sid       = "QueryHotTable"
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.hot.arn]
  }

  # 較正・前向きログ・レースの生データ。データバケットのみ
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
  # 読み取り専用なので許容するが、ここだけは全リソースが対象になる点に注意。
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

resource "aws_iam_user_policy" "morning_check" {
  name   = "morning-check-readonly"
  user   = aws_iam_user.morning_check.name
  policy = data.aws_iam_policy_document.morning_check.json
}
