# 환경 의존 값과 비밀값 선언
# 실제 값 terraform.tfvars(gitignore) 또는 -var 주입

variable "aws_region" {
  description = "AWS region"
  type = string
  default = "ap-northeast-2"
}

variable "db_password" {
  description = "RDS master password"
  type = string
  sensitive = true
}

variable "alert_email" {
  description = "CloudWatch alarm notification email"
  type = string
  sensitive = true
}

variable "github_repo" {
  description = "GitHub OIDC 신뢰 대상 저장소 (owner/repo). 이 저장소의 main 브랜치만 배포 역할을 assume할 수 있다"
  type = string
}

# ALB는 Kubernetes Ingress가 생성해 Terraform이 1회차 Apply 참조 불가
# 1회차는 false로 apply → Ingress 적용 → ALB 생성 확인 → 2회차는 true로 apply
variable "alb_created" {
  description = "Ingress로 ALB가 생성된 뒤 true로 전환 (2단계 apply)"
  type = bool
  default = false
}

variable "cloudfront_origin_secret" {
  description = "CloudFront → ALB 요청에 붙는 검증 헤더 값, ALB는 헤더가 없는 직접 접근 403 처리"
  type = string
  sensitive = true
}
