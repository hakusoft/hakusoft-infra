# 当日レース取り込みの基盤（Issue: odds-resolver#16）。
#
# 器だけを先に作る。EventBridge ルールは全て無効で作成し、フェッチャ・
# 朝ジョブ・夜間バッチのコードが載った時点で有効化する（別 PR）。
#
# DynamoDB は単一テーブル。必要な問いが全てキー直撃になるよう設計する:
#   - 当日の全レース表        → Query PK = DAY#{YYYYMMDD}
#   - あるレースの時系列       → Query PK = RACE#{race_id}
#   - 最新スナップショット     → 同上を降順 Limit 1
# race_id はサイト独自形式 {YYYYMMDD}-{slug}-{RR}（odds-resolver/docs/race-id.md）。

resource "aws_dynamodb_table" "hot" {
  name         = "${local.name}-hot"
  billing_mode = "PROVISIONED"

  # 常設無料枠（25/25）の範囲内に固定する
  read_capacity  = 10
  write_capacity = 10

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # 夜間バッチで S3 へ移送済みのデータを自動失効させる（削除コードは書かない）
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

# ---- Lambda（骨格のみ・実装は別 PR） ----------------------------------

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/build/placeholder.zip"

  source {
    content  = "def handler(event, context):\n    return {\"status\": \"not implemented\"}\n"
    filename = "main.py"
  }
}

# 取得系（朝ジョブ・毎分フェッチャ共用のロール。書くのは DynamoDB だけ）
resource "aws_iam_role" "ingest_lambda" {
  name = "${local.name}-ingest-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ingest_lambda" {
  name = "ingest"
  role = aws_iam_role.ingest_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoWrite"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.hot.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# 夜間バッチ（DynamoDB を読み、S3 data バケットへ焼く。削除権限は持たない）
resource "aws_iam_role" "archive_lambda" {
  name = "${local.name}-archive-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "archive_lambda" {
  name = "archive"
  role = aws_iam_role.archive_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoRead"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = aws_dynamodb_table.hot.arn
      },
      {
        Sid      = "DataWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.data.arn}/*"
      },
      {
        Sid      = "DataList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.data.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# VPC 外・最小構成。取得系はホストへの行儀（間隔制御）を関数内で持つため
# タイムアウトは余裕を持たせる
resource "aws_lambda_function" "fetch" {
  function_name = "${local.name}-fetch"
  role          = aws_iam_role.ingest_lambda.arn
  runtime       = "python3.13"
  handler       = "main.handler"
  timeout       = 55
  memory_size   = 128

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.hot.name
    }
  }

  lifecycle {
    # コードは別リポジトリの CI がデプロイする。Terraform は器だけを見る
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_function" "morning" {
  function_name = "${local.name}-morning"
  role          = aws_iam_role.ingest_lambda.arn
  runtime       = "python3.13"
  handler       = "main.handler"
  timeout       = 300
  memory_size   = 128

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.hot.name
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

resource "aws_lambda_function" "archive" {
  function_name = "${local.name}-archive"
  role          = aws_iam_role.archive_lambda.arn
  runtime       = "python3.13"
  handler       = "main.handler"
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.hot.name
      DATA_BUCKET = aws_s3_bucket.data.id
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# ---- EventBridge（全ルール無効で作成。実装が載る PR で有効化する） ------

resource "aws_cloudwatch_event_rule" "fetch_minutely" {
  name                = "${local.name}-fetch-minutely"
  schedule_expression = "rate(1 minute)"
  state               = "DISABLED"
}

resource "aws_cloudwatch_event_target" "fetch_minutely" {
  rule = aws_cloudwatch_event_rule.fetch_minutely.name
  arn  = aws_lambda_function.fetch.arn
}

resource "aws_lambda_permission" "fetch_minutely" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fetch.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.fetch_minutely.arn
}

# 日付が変わったら当日の器を作る。0:00 ちょうどは取得元側の日次切替と
# 重なりうるため 0:15 JST = 前日 15:15 UTC にずらす
resource "aws_cloudwatch_event_rule" "morning_daily" {
  name                = "${local.name}-morning-daily"
  schedule_expression = "cron(15 15 * * ? *)"
  state               = "DISABLED"
}

resource "aws_cloudwatch_event_target" "morning_daily" {
  rule = aws_cloudwatch_event_rule.morning_daily.name
  arn  = aws_lambda_function.morning.arn
}

resource "aws_lambda_permission" "morning_daily" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.morning.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.morning_daily.arn
}

# その日のうちに焼く（23:30 JST = 14:30 UTC）。日付が変わると当日/過去の
# 分岐が切り替わり S3 を見に行くため、跨ぐ前にアーカイブを済ませておく。
# 順序: 23:30 焼く → 0:15 翌日の器を作る
resource "aws_cloudwatch_event_rule" "archive_nightly" {
  name                = "${local.name}-archive-nightly"
  schedule_expression = "cron(30 14 * * ? *)"
  state               = "DISABLED"
}

resource "aws_cloudwatch_event_target" "archive_nightly" {
  rule = aws_cloudwatch_event_rule.archive_nightly.name
  arn  = aws_lambda_function.archive.arn
}

resource "aws_lambda_permission" "archive_nightly" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.archive.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.archive_nightly.arn
}

# ---- 当日読み取り API（Issue: odds-resolver#19） ----------------------
# DynamoDB のホットデータを JSON で返す。Lambda Function URL で公開し、
# API Gateway を挟まない（最小構成）。読むだけなので権限は Query のみ。

resource "aws_iam_role" "read_api_lambda" {
  name = "${local.name}-read-api-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "read_api_lambda" {
  name = "read"
  role = aws_iam_role.read_api_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoRead"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = aws_dynamodb_table.hot.arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "read_api" {
  function_name = "${local.name}-read-api"
  role          = aws_iam_role.read_api_lambda.arn
  runtime       = "python3.13"
  handler       = "ingest.api.handler"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.hot.name
    }
  }

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }
}

# 公開は API Gateway(HTTP API) の Lambda プロキシ統合で行う。
# Function URL + OAC は署名段階で到達せず断念（枯れた HTTP API を採用）。
# CloudFront の /api/* オリジンとしてこの API を使う。
resource "aws_apigatewayv2_api" "read_api" {
  name          = "${local.name}-read-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "read_api" {
  api_id                 = aws_apigatewayv2_api.read_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.read_api.invoke_arn
  payload_format_version = "2.0"
}

# 全パス・全メソッドを Lambda へ。ルーティングは Lambda が query で判断する
resource "aws_apigatewayv2_route" "read_api" {
  api_id    = aws_apigatewayv2_api.read_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.read_api.id}"
}

resource "aws_apigatewayv2_stage" "read_api" {
  api_id      = aws_apigatewayv2_api.read_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "read_api_apigw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.read_api.execution_arn}/*/*"
}

output "read_api_endpoint" {
  value = aws_apigatewayv2_api.read_api.api_endpoint
}
