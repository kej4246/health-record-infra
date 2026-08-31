# CloudFront는 ALB 앞단 HTTPS 진입점 (캐싱 미사용)
# ALB는 Ingress가 생성하며 alb_created = true인 2회차 Apply 생성
# 관리형 정책 ID (AWS 고정값)
# CachingDisabled: TTL 0, AllViewer: 헤더/쿠키/쿼리스트링 모두 origin 전달
locals {
  cf_cache_policy_caching_disabled = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  cf_origin_request_policy_all_view = "216adef6-5c7f-47e4-b989-5492eafa07d3"
}

resource "aws_cloudfront_distribution" "main" {
  count = var.alb_created ? 1 : 0

  enabled = true
  comment = "health-record-infra CDN"

  origin {
    domain_name = data.aws_lb.app[0].dns_name
    origin_id = "alb-origin"

    # CloudFront가 붙이는 검증 헤더로 ALB 리스너 규칙이 헤더 확인해 CloudFront 경유만 통과
    # (보안그룹의 프리픽스 리스트 제한과 2중 방어)
    custom_header {
      name = "X-Origin-Verify"
      value = var.cloudfront_origin_secret
    }

    # CF → ALB 구간은 HTTP, 도메인과 ACM 인증서 없어 ALB HTTPS 리스너를 둘 수 없는 한계
    # 운영 전환 시 도메인 확보 → ACM → origin_protocol_policy = "https-only"
    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id = "alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods = ["GET", "HEAD"]

    cache_policy_id = local.cf_cache_policy_caching_disabled
    origin_request_policy_id = local.cf_origin_request_policy_all_view
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
