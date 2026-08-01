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
    設定後、本人が確認メールのリンクを承認して初めて有効になる。
    SMS は無料枠がないため使わない。

    購読を作りたくない場合は "none" を明示的に指定する。デフォルト値は
    持たない: 値を渡し忘れた時に「購読を作らない」と解釈され、既存の
    購読が黙って destroy されるのを防ぐため（渡し忘れなら plan が
    「変数が未設定」で止まる）。実値は terraform.tfvars に置く
    （.gitignore 済み。terraform.tfvars.example を参照）。
  EOT
  type        = string

  validation {
    condition     = var.surge_alert_email == "none" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.surge_alert_email))
    error_message = "メールアドレスの形式で指定するか、購読を作らない場合は \"none\" と書くこと。"
  }
}
