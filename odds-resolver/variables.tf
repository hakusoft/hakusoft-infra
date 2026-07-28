variable "region" {
  description = "デプロイ先リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "github_sub_claim_prefix" {
  description = <<-EOT
    OIDC トークンの sub の接頭辞。owner/repo の数値 ID を含む。
    リポジトリ名を変えても壊れないよう GitHub が ID を埋めるため、
    名前だけで書くと信頼ポリシーが一致しない。
    確認: gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  EOT
  type        = string
  default     = "repo:hakusoft@261719523/odds-resolver@1308241586"
}

variable "surge_alert_email" {
  description = <<-EOT
    オッズ急変アラートの通知先メール（odds-resolver#71）。
    空なら購読を作らない。設定後、本人が確認メールのリンクを承認して
    初めて有効になる。SMS は無料枠がないため使わない。
  EOT
  type        = string
  default     = ""
}
