resource "aws_ecr_repository" "app" {
  name = "health-record-app"
  # 커밋 해시 태그는 한 번 푸시되면 변경 불가 (롤백 대상을 다른 이미지로 덮이기 방지)
  image_tag_mutability = "IMMUTABLE"
  force_delete = true # 포트폴리오 환경: destroy 시 이미지가 남아 있어도 삭제

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 커밋 해시 태그가 Push마다 누적되어 보관 개수 상한 코드 명시
# 최근 10개는 롤백 대상 남기고 그 이상 만료
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 10개 이미지만 보관 (롤백 여지 확보)"
      selection = {
        tagStatus = "any"
        countType = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
