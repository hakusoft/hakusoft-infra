# オッズデータの置き場。append-only の時系列 JSON をここに溜める。
#
# フロント配信用バケットとは分ける。理由:
#   - ライフサイクル・バージョニングの方針が違う（フロントは毎回上書き、
#     データは追記のみで上書きしない）
#   - CI に渡す書き込み権限を「データはスクレイパー、フロントはデプロイ」と
#     別々に絞れる
#
# 配信は CloudFront の /data/* パスから読む構成も考えられるが、まずは
# フロントのビルド時（または別ジョブ）に必要分を frontend バケットへ
# コピーする素朴な形で始める。配信経路を増やすのはデータ量が見えてから。

resource "aws_s3_bucket" "data" {
  bucket = "${local.name}-data-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# append-only の保険。上書き・削除があっても旧版が残り、事故に気づける。
# 非現行版は 30 日で消して保存料の膨張を防ぐ（正規データは常に現行版）。
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
