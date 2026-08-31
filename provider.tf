terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # 모든 리소스 공통 태그 자동 부여 (리소스마다 반복 기재 제거, 태그 누락 방지)
  default_tags {
    tags = {
      Project = "health-record-infra"
      ManagedBy = "terraform"
    }
  }
}
