# GitHub Actions → AWS 인증을 장기 액세스 키에서 OIDC 역할 방식 전환
# 저장소와 브랜치가 일치하는 워크플로만 짧은 수명의 토큰으로 역할을 넘겨받으며 저장할 키 없음
module "github_oidc_provider" {
  source = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version = "~> 5.0"
}

# 신뢰 정책은 AWS 문서의 표준 형태로 직접 정의
# aud 정확히 일치, sub는 이 저장소의 main 브랜치만 허용
resource "aws_iam_role" "github_actions" {
  name = "health-record-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.github_oidc_provider.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_deploy" {
  role = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}

# 기존 모듈로 만든 역할을 새 리소스 주소 이관 (재생성 없이 신뢰 정책만 갱신)
moved {
  from = module.github_actions_role.aws_iam_role.this[0]
  to = aws_iam_role.github_actions
}

moved {
  from = module.github_actions_role.aws_iam_role_policy_attachment.this["deploy"]
  to = aws_iam_role_policy_attachment.github_actions_deploy
}

# 배포에 필요한 최소 권한의 ECR 푸시(해당 리포지토리만) + 스캔 결과 조회 + EKS 클러스터 정보 조회
# kubectl 권한은 IAM이 아닌 EKS Access Entry(eks.tf) 네임스페이스 단위 부여
resource "aws_iam_policy" "github_actions_deploy" {
  name = "health-record-github-actions-deploy"
  description = "ECR push + scan findings + EKS describe for CI/CD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Effect = "Allow"
        Action = ["eks:DescribeCluster"]
        Resource = module.eks.cluster_arn
      }
    ]
  })
}
