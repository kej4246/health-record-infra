resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = { Name = "health-record-vpc" }
}

# 서울 리전 AZ 목록 가용영역 정보 가져오기
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnet 2개 설정 외부 연결 영역
# kubernetes.io/role/elb 태그는 ALB Controller가 Internet-facing ALB 생성 시 해당 태그로 Public Subnet 자동 탐색
resource "aws_subnet" "public_a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "health-record-public-a"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_c" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "health-record-public-c"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnet 2개 설정 내부 보안 영역
resource "aws_subnet" "private_a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "health-record-private-a"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "health-record-private-c"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Internet Gateway로 Public Subnet 외부 출입 역할
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "health-record-igw" }
}

# NAT용 고정 IP (EIP)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "health-record-nat-eip" }
}

# NAT Gateway (Private 나가는 통로, Public 위치)
# 단일 배치는 비용 우선하여 1개(약 월 $43) 또는 2개(약 월 $86)
# Private 라우팅 테이블 1개를 두 AZ가 공유하고 AZ-a 장애 시 private_c의 외부 통신까지 끊기는 구조적 SPOF 인지
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public_a.id
  tags = { Name = "health-record-nat" }

  depends_on = [aws_internet_gateway.main]
}

# Public Routing Table (외부로 나가는 길 → Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "health-record-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# Private Routing Table (나가는 길 → NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = { Name = "health-record-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id = aws_subnet.private_c.id
  route_table_id = aws_route_table.private.id
}

# S3 Gateway VPC Endpoint
# Pod → S3 트래픽이 NAT Gateway를 경유하지 않고 AWS 내부망 직행
# Gateway Endpoint는 무료로 NAT 데이터 처리 요금만큼 순수 절감
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private.id]

  tags = { Name = "health-record-s3-endpoint" }
}

# ALB 전용 보안그룹, CloudFront 경유 트래픽만 허용
# ALB가 인터넷 공개 상태면 CloudFront를 우회해 직접 접근이 가능
# AWS 관리형 프리픽스 리스트(CloudFront origin-facing IP 대역)에서 오는 80만 허용
# Ingress annotation alb.ingress.kubernetes.io/security-groups로 이 SG를 지정
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name = "health-record-alb-sg"
  description = "Allow HTTP only from CloudFront origin-facing IP ranges"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from CloudFront"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  # ALB → Pod 아웃바운드는 ALB Controller가 backend SG 규칙 관리
  # (manage-backend-security-group-rules: "true")
  egress {
    description = "To pods"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = { Name = "health-record-alb-sg" }
}
