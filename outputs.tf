# Kubernetes 매니페스트의 플레이스홀더를 채우는 데 사용될 출력값

output "db_endpoint" {
  description = "RDS endpoint (host only, without port)"
  value = aws_db_instance.main.address
}

output "s3_bucket" {
  description = "S3 bucket name for prescription/checkup images"
  value = aws_s3_bucket.files.bucket
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value = aws_ecr_repository.app.repository_url
}

output "eks_cluster_name" {
  description = "EKS cluster name (for aws eks update-kubeconfig)"
  value = module.eks.cluster_name
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller (Helm install)"
  value = module.alb_controller_irsa.iam_role_arn
}

output "app_irsa_role_arn" {
  description = "IRSA role ARN for the app service account (k8s/serviceaccount.yaml <APP_ROLE_ARN>)"
  value = module.app_irsa.iam_role_arn
}

output "alb_security_group_id" {
  description = "Security group for the ALB (k8s/ingress.yaml <ALB_SG_ID>)"
  value = aws_security_group.alb.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC (GitHub secret AWS_ROLE_ARN)"
  value = aws_iam_role.github_actions.arn
}

output "cloudfront_url" {
  description = "HTTPS entry point (CloudFront default certificate). Available after alb_created = true"
  value = var.alb_created ? "https://${aws_cloudfront_distribution.main[0].domain_name}" : "(run 2nd apply with alb_created = true)"
}
