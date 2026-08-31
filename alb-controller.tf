# ALB Controller의 IAM 역할 (공식 모듈 사용)
module "alb_controller_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "health-record-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Ingress가 생성한 ALB를 2회차 Apply 조회
data "aws_lb" "app" {
  count = var.alb_created ? 1 : 0

  tags = {
    "ingress.k8s.aws/stack" = "health-record/health-record-ingress"
  }
}
