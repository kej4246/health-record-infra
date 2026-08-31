# 앱이 사용할 S3 접근 정책
# AmazonS3ReadOnlyAccess (계정 내 전체 버킷 읽기) → 해당 버킷만 허용
# 최소 권한 원칙 맞춤으로 프로젝트 버킷 하나로 범위 좁힘
resource "aws_iam_policy" "app_s3_read" {
  name = "health-record-app-s3-read"
  description = "Read-only access limited to the health-record bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        # head_bucket은 s3:ListBucket, 객체 조회는 s3:GetObject 필요
        Action = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.files.arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.files.arn}/*"]
      }
    ]
  })
}

# AWS 공식 모듈 사용한 EKS Cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name = "health-record-eks"
  cluster_version = "1.32"

  # 퍼블릭 엔드포인트 유지는 GitHub Actions 러너 대역(api.github.com/meta)은 공개되어 있어 약 4,000개 이상
  # EKS 엔드포인트 CIDR 제한은 최대 40개로 대역 전체 등록 불가
  # 원천 차단은 VPC 내부 self-hosted 러너가 필요하나 상시 비용 발생, 해당 규모와 맞지 않음
  # IAM 인증과 컨트롤플레인 Audit 로그 API 호출 주체 추적
  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  # Control Plane 로그 활성화
  # Audit을 통해 어떤것이 클러스터 API 호출하는지 추적하여 민감정보 서비스 필수 판단
  # 모듈 기본값과 동일하나 기본값 의존 없이 코드 의도적 남김
  cluster_enabled_log_types = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 30 # 기본 90일로 비용 고려해 축소

  vpc_id = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_c.id]

  # GitHub Actions 배포 역할 클러스터 접근 권한 부여 (aws-auth ConfigMap 대신 Access Entry 방식)
  # Edit 정책을 health-record 네임스페이스로 한정 → 다른 네임스페이스와 클러스터 설정 수정 불가
  access_entries = {
    github_actions = {
      principal_arn = aws_iam_role.github_actions.arn
      policy_associations = {
        edit = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = {
            type = "namespace"
            namespaces = ["health-record"]
          }
        }
      }
    }
  }

  # 노드 역할은 앱 권한 붙이지 않음
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size = 2
      max_size = 3
      desired_size = 2
    }
  }
}

# 앱 Pod 전용 IAM 역할 (IRSA)
# ALB Controller와 같은 방식으로 통일, 서비스 어카운트 health-record/health-record-app만 역할
module "app_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "health-record-app"

  role_policy_arns = {
    s3_read = aws_iam_policy.app_s3_read.arn
  }

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["health-record:health-record-app"]
    }
  }
}
