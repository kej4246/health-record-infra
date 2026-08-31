# 경보 알림 SNS Topic
resource "aws_sns_topic" "alerts" {
  name = "health-record-alerts"
}

# 알림 받을 이메일 구독
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol = "email"
  endpoint = var.alert_email
}

# 1) 노드 CPU 경보
# 서버 관점 지표로 HPA가 Pod 수준에서 50%로 우선 대응
# 노드 자체가 70%를 넘을 시 사람 개입 필요
# period 300초는 EC2 기본 모니터링 주기와 일치시킨 값 (불일치 시 INSUFFICIENT_DATA)
resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name = "health-record-node-cpu-high"
  alarm_description = "EKS node CPU over 70%"
  namespace = "AWS/EC2"
  metric_name = "CPUUtilization"
  statistic = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold = 70
  evaluation_periods  = 2
  period = 300

  dimensions = {
    AutoScalingGroupName = module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names[0]
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions = [aws_sns_topic.alerts.arn]
}

# 2) RDS 여유 스토리지 경보
# 할당 용량이 20GB뿐이라 실질적 위험 가능성으로 2GB 미만이면 통보
# 단위는 바이트 (2GB = 2,147,483,648)
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name = "health-record-rds-storage-low"
  alarm_description = "RDS free storage under 2GB"
  namespace = "AWS/RDS"
  metric_name = "FreeStorageSpace"
  statistic = "Average"
  comparison_operator = "LessThanThreshold"
  threshold = 2147483648
  evaluation_periods = 1
  period = 300

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions = [aws_sns_topic.alerts.arn]
}

# 3) RDS 연결 수 경보
# 커넥션 누수 조기 감지로 db.t3.micro는 최대 연결 수가 낮아 연결이 반납되지 않을 시 신규 연결 거부로 서비스 정지
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name = "health-record-rds-connections-high"
  alarm_description = "RDS connection count unusually high (possible leak)"
  namespace = "AWS/RDS"
  metric_name = "DatabaseConnections"
  statistic = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold = 40
  evaluation_periods = 2
  period = 300

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions = [aws_sns_topic.alerts.arn]
}

# 4) RDS CPU 경보
# 순간 피크 무시, 10분 연속 80% 초과일 경우 통보
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name = "health-record-rds-cpu-high"
  alarm_description = "RDS CPU over 80% for 10 minutes"
  namespace = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold = 80
  evaluation_periods = 2
  period = 300

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions = [aws_sns_topic.alerts.arn]
}

# 5) RDS 여유 메모리 경보
# db.t3.micro는 1GiB, 초기 임계값 100MB는 기준선 없이 잡은 값이며 구축 직후 계속 울림
# 3시간 관측 결과 평상시 여유 메모리 정상 범위 80~100MB(MySQL이 버퍼로 대부분 점유)
# 관측 정상범위 아래 50MB 조정 (단위 바이트)
resource "aws_cloudwatch_metric_alarm" "rds_memory_low" {
  alarm_name = "health-record-rds-memory-low"
  alarm_description = "RDS freeable memory under 50MB"
  namespace = "AWS/RDS"
  metric_name = "FreeableMemory"
  statistic = "Average"
  comparison_operator = "LessThanThreshold"
  threshold = 52428800
  evaluation_periods  = 2
  period = 300

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions = [aws_sns_topic.alerts.arn]
}

# 6) ALB 5xx 경보 (2회차 Apply)
# 사용자가 실제로 실패를 겪는 지표, 5분간 5xx가 10건 넘으면 통보
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = var.alb_created ? 1 : 0

  alarm_name = "health-record-alb-5xx"
  alarm_description = "ALB 5xx responses over 10 in 5 minutes"
  namespace = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"
  statistic = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold = 10
  evaluation_periods = 1
  period = 300
  treat_missing_data = "notBreaching" # 트래픽 없으면 정상 간주

  dimensions = {
    LoadBalancer = data.aws_lb.app[0].arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions = [aws_sns_topic.alerts.arn]
}
