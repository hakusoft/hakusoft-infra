output "cloudfront_url" {
  description = "配信 URL"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "キャッシュ無効化に使う distribution ID"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_bucket" {
  description = "フロント配信用バケット名（aws s3 sync の宛先）"
  value       = aws_s3_bucket.frontend.id
}

output "data_bucket" {
  description = "オッズデータ用バケット名"
  value       = aws_s3_bucket.data.id
}

output "github_deploy_role_arn" {
  description = "GitHub Actions の role-to-assume に設定する ARN"
  value       = aws_iam_role.github_deploy.arn
}
