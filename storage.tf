# DB를 지정할 Subnet 그룹을 Private Subnet 2개 구성
resource "aws_db_subnet_group" "main" {
  name = "health-record-db-subnet"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_c.id]

  tags = { Name = "health-record-db-subnet" }
}

# RDS용 보안그룹
# VPC 전체(10.0.0.0/16) 허용 → EKS 노드 보안그룹에서 오는 3306만 허용
# VPC 전체 허용은 같은 VPC의 모든 자원이 DB로 접근 가능하며 최소 권한 원칙 어긋남
# 보안그룹 참조 방식은 IP가 변경되도 유효
resource "aws_security_group" "rds" {
  name = "health-record-rds-sg"
  description = "Allow MySQL from EKS nodes only"
  vpc_id  = aws_vpc.main.id

  ingress {
    description = "MySQL from EKS node security group"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  # RDS가 외부로 나가지 않으며 egress 전체 개방 제거
  # (egress 블록을 두지 않으면 모든 아웃바운드 차단)
  tags = { Name = "health-record-rds-sg" }
}

# RDS(MySQL) 건강·복약 기록 데이터베이스
resource "aws_db_instance" "main" {
  identifier = "health-record-db"
  engine = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  storage_encrypted = true # 의료 기록으로 저장 데이터 암호화
  db_name = "healthrecord"
  username  = "admin"
  password = var.db_password
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible = false # 외부에서 직접 접근 불가

  # 백업 정책
  # 7일 보관, 시점 복구(PITR) 확보
  # RTO: 스냅샷 복원 약 10~20분 / RPO: 트랜잭션 로그 주기 최대 5분
  backup_retention_period = 7
  backup_window = "17:00-18:00" # UTC는 한국시간 새벽 2~3시
  copy_tags_to_snapshot   = true

  # DB 감사와 성능 추적용 로그 CloudWatch 내보내기
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # multi_az = true  # 운영 전환 시 활성화 (비용 약 2배, 의도적 미적용)
  multi_az = false

  skip_final_snapshot = true  # 포트폴리오 환경: destroy 시 최종 스냅샷 생략
  deletion_protection = false # 포트폴리오 환경: destroy 허용

  tags = { Name = "health-record-db" }
}

# S3 Bucket 처방전과 검진 이미지 저장
resource "aws_s3_bucket" "files" {
  bucket = "health-record-files-20260609"
  tags = { Name = "health-record-files" }
}

# S3 퍼블릭 접근 완전 차단 비공개
resource "aws_s3_bucket_public_access_block" "files" {
  bucket = aws_s3_bucket.files.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# 버전 관리로 처방전과 검진 이미지가 실수로 삭제 또는 덮어쓰기가 되어도 이전 버전 복구 가능
resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 버전 관리를 켜면 이전 버전이 무한 누적되어 비용 증가
# 복구 여지는 30일로 충분, 그 이상 비용 발생
resource "aws_s3_bucket_lifecycle_configuration" "files" {
  bucket = aws_s3_bucket.files.id

  rule {
    id = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # 중단된 멀티파트 업로드 조각 정리 (보이지 않는 과금 원인)
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.files]
}

# 저장 데이터 암호화 명시
# 2023년 1월부터 SSE-S3가 기본 적용되지만 코드에 의도적 남김
resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  bucket = aws_s3_bucket.files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
