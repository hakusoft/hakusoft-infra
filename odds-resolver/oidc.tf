# GitHub Actions からのデプロイ用ロール。
#
# 長期のアクセスキーを GitHub に置かない。Actions が OIDC トークンを提示し、
# AWS 側で一時credentialに交換する。漏洩しても再利用できない。

# OIDC プロバイダはアカウント内に 1 つしか作れず、他のリポジトリが既に作っている。
# ここでは参照するだけ（この Terraform の管理外）。
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # odds-resolver リポジトリの main ブランチからのみ引き受け可能にする。
    # sub には owner/repo の数値 ID が埋め込まれる。名前だけで書くと一致しない。
    # 確認: gh api repos/hakusoft/odds-resolver/actions/oidc/customization/sub
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.github_sub_claim_prefix}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name = "${local.name}-github-deploy"
  # IAM の description は ASCII のみ（日本語を入れると ValidationError）
  description        = "Lets GitHub Actions deploy the frontend and write odds data"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

# CI がやるのは次の 3 つだけ。IAM も CloudFront の設定変更も触らせない。
#   1. フロントのビルド成果物を frontend バケットへ sync
#   2. オッズデータを data バケットへ追記
#   3. デプロイ後のキャッシュ無効化
data "aws_iam_policy_document" "github_deploy" {
  # aws s3 sync に必要な一式。--delete で古い成果物を消すため DeleteObject も要る。
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
  }

  # データは append-only。Delete は与えない。
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }

  # sync の差分計算に ListBucket が要る。
  statement {
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.frontend.arn,
      aws_s3_bucket.data.arn,
    ]
  }

  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.frontend.arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
