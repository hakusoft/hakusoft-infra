# フロント配信。S3 に静的ファイルを置き、CloudFront から配信する。
#
# S3 は直接公開しない。OAC（Origin Access Control）で CloudFront からのみ
# 読めるようにする。バケットを公開すると、CloudFront を迂回して S3 の URL を
# 直接叩かれ、キャッシュも効かなくなるため。
#
# 独自ドメインは使わない。CloudFront 既定の *.cloudfront.net で足りる。

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name}-frontend-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront が S3 を読むための署名方式。OAC は OAI の後継で、SigV4 に対応する。
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${local.name} frontend"

  # 無料枠に収まる最安クラス。北米・欧州のみのエッジ。日本からは少し遅いが
  # 個人サイト用途では十分で、PriceClass_All より安い。
  price_class = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    # AWS 管理の CachingOptimized ポリシー。ID は全アカウント共通の固定値。
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # オッズデータ（/data/*）はキャッシュ時間を短くする。
  # 開催中はオッズが動くため、長時間キャッシュすると古い値を配り続ける。
  # 過去レースは静的化して immutable にする想定だが、その制御は
  # オブジェクト側の Cache-Control ヘッダで行う（CachingOptimized は
  # オリジンのヘッダを尊重する）ので、behavior の分岐は増やさない。

  # SPA。存在しないパスはルーティングを index.html に委ねる。
  # S3 が返す 403/404 を index.html + 200 に読み替える。
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# CloudFront(OAC) からのみ GetObject を許可する。
# 条件で「この distribution から来た要求」に限定し、他の CloudFront からは読ませない。
data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}
