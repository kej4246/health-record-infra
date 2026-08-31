# 트러블슈팅과 의사결정

---

# 1. 트러블슈팅

## 1) HPA 무반응 상태

- 증상: `kubectl get hpa`에서 TARGETS가 `<unknown>/50%`로 고정, 부하를 걸어도 Pod 2개 그대로 표시
- 원인: EKS는 metrics-server를 기본 포함하지 않음, HPA는 Metrics API로 Pod CPU를 읽는데 이 부분이 없어 에러 없이 대기
- 조치: metrics-server 배포 → `1%/50%`로 바뀌고 이후 증설 정상

> 배운 점: 관리형 서비스는 표준 배포판과 기본 구성이 다르다. 무반응일 경우 `kubectl top`으로 메트릭 파이프라인부터 확인한다.

## 2) CloudWatch 경보가 발화하지 않음

- 증상: HPA는 동작(CPU 114%, Pod 2 → 5개)하고 있으나 노드 CPU 경보는 계속 정상
- 진단
  1) `kubectl top nodes` → '노드 CPU 30% 14%'로 Pod CPU와 노드 CPU는 다른 지표로 HPA는 Pod를, 경보는 EC2 노드로 향함
  2) 부하 생성기를 1 → 7개로 늘려도 42% / 36% 구간에서 정체
  3) 경보 조건(> 70)과 실측(36%)을 대조하였으나 기다려도 넘지 않았음
  4) wget 부하는 응답 대기가 대부분이라 CPU를 거의 사용하지 않음
- 조치: 연산형 부하(`while true; do :; done`) 교체 → 노드 CPU 84% / 99%, 경보 발화, SNS 메일 수신

> 배운 점: 같은 'CPU 사용률'이라도 어떤 계층을 보느냐에 따라 값이 다르고 발화가 늦으면 기다리는 것이 아닌 임계값과 실측치부터 비교한다.

## 3) CloudFront origin 끊김 현상

- 증상: 같은 코드로 재확인했지만 CloudFront가 옛 ALB 주소를 나타냄
- 원인: `cloudfront.tf`에 ALB 주소를 문자열로 하드코딩, ALB는 Ingress가 만들기 때문에 재구축할 때마다 주소가 변경됨
- 조치: `data "aws_lb"`로 ALB Controller가 붙이는 `ingress.k8s.aws/stack` 태그를 조회해 주소를 자동으로 따라가도록 변경하고 ALB가 먼저 존재해야 하므로 `alb_created` 변수로 apply를 두 단계 분리

> 배운 점: 생성 주체가 다른 자원(Kubernetes가 만든 ALB, Terraform이 만든 CloudFront)은 의존 관계를 코드로 풀어둬야 재현된다.

## 4) 코드에 적은 설정이 실제로 적용되지 않음

- 증상: Ingress에 등록 해제 대기 30초를 적어뒀으나 실제 타깃 그룹은 기본값 300초
- 원인: 어노테이션 접두사가 `alb.`가 아니어서 컨트롤러가 인식하지 못했고 컨트롤러는 모르는 어노테이션을 에러 없이 무시
- 조치: 접두사 수정 후 `aws elbv2 describe-target-group-attributes`로 30초 반영 확인

> 배운 점: 코드를 작성하는 것과 시스템이 읽는 것은 차이가 있어 조용히 무시되는 설정은 실측으로 확인이 필요하다.

## 5) GitHub Actions OIDC 인증 거부

- 증상: 신뢰 정책의 저장소와 브랜치 조건이 일치하지만 `Not authorized to perform sts:AssumeRoleWithWebIdentity`
- 진단: 워크플로에서 토큰의 `sub` 클레임을 직접 출력해 실제 값 확인
- 조치: 신뢰 정책의 `sub` 조건을 실측값으로 맞춰 수정 후 인증 성공

> 배운 점: AWS 공식 문서를 통해 실행했으나 안 되었을 경우 실제 토큰 값을 찍어본다.

## 6) 스캔 게이트가 첫 배포를 막음

- 증상: 파이프라인이 `CRITICAL findings: 4`로 중단
- 원인: `python:3.12-slim`의 OS 패키지에 CRITICAL 취약점 4건 도출, 게이트는 정확히 동작됨을 확인
- 조치: 앱 의존성이 모두 순수 파이썬으로 `python:3.12-alpine`으로 전환 → 0건

> 배운 점: 스캔을 켜두는 것만으로는 부족하며 결과로 배포를 막아야 취약 이미지가 걸러진다.

## 7) 배포 후 Pod가 한쪽 AZ로 몰림

- 증상: `topologySpreadConstraints`를 걸었는데 CI 배포 후 Pod 2개가 같은 노드에 배치됨
- 원인: 롤링 업데이트 중 종료되는 이전 버전 Pod도 같은 라벨이라 분산 계산에 포함, 이전 Pod가 a/b에 있는 상태에서 새 Pod가 a에 뜨고, 이전 a가 내려가며 두 번째 새 Pod가 다시 a에 떠도 규칙 위반이 아님
- 조치: `matchLabelKeys: [pod-template-hash]`로 같은 ReplicaSet끼리 계산 → 재배포 후 서로 다른 노드와 AZ 확인

> 배운 점: 처음 배포 당시 분산되면 끝이 아니며 배포가 반복되어도 유지되는지 봐야 한다.

## 8) RDS 메모리 경보가 계속 발화함

- 증상: 구축 직후부터 `FreeableMemory < 100MB` 경보 상태 유지
- 원인: t3.micro(1GiB)는 MySQL이 버퍼로 대부분을 잡아 평상시 여유는 80~100MB, 기준선 없이 잡은 100MB가 정상 범위 안이었음
- 조치: 3시간 관측 후 50MB로 조정하여 정상 전환

> 배운 점: 당시 운영 상황과 같았으며 경보가 울린다고 모든 문제가 아닌 무엇이 정상인지 알아야 임계값을 정할 수 있다.

---

# 2. 구축 후 점검에서 고친 것

에러 메시지는 없었으나 잘못되어 있던 것들입니다. 문서와 코드를 대조하여 탐색했습니다.

| 발견 | 문제 | 조치 |
|---|---|---|
| `replicas: 2`가 AZ 분산을 보장하지 않음 | 같은 노드에 2개가 생기면 노드 1대 장애로 전면 중단 | `topologySpreadConstraints` 추가 |
| RDS 백업 정책이 코드에 없음 | AWS 기본값 의존 | 보존 7일, 백업 창, 로그 내보내기 명시 |
| 서브넷에 ALB 탐색 태그 없음 | 재구축 시 ALB 생성 실패 가능 | `kubernetes.io/role/elb` 태그 추가 |
| 배포 실패가 파이프라인 성공으로 끝남 | `ImagePullBackOff`여도 초록불 | `rollout status` 검증과 자동 롤백 |
| 앱이 예외 메시지를 그대로 반환 | 호스트명과 사용자명 노출 | 상세는 로그, 응답은 결과 |
| 컨테이너 root 실행 | 침해 시 권한 상승 경로 | 비root(uid 1000), 읽기 전용 루트, capabilities 제거 |
| 노드 역할의 S3 권한이 계정 전체 범위 | 그 노드의 모든 Pod가 모든 버킷을 읽음 | 버킷 하나로 축소 → 이후 IRSA로 서비스 어카운트에만 부여 |
| 의존성 버전 미고정 | 빌드마다 다른 버전 | `==`로 정확히 고정 |
| 배포 중 502 발생 가능 | Pod 종료가 ALB 등록 해제(300초)보다 빠름 | `preStop` 20초, 등록 해제 30초, `maxUnavailable: 0` |
| 노드 CPU 경보가 ASG 평균 기준 | A 92% / B 10%면 51%라 놓침 | 통계를 `Maximum`으로 변경 |
| gunicorn 종료 처리 없음 | preStop과 겹치면 시간 부족 | `--graceful-timeout 30` 지정 |
| 장기 액세스 키를 GitHub Secrets에 보관 | 유출 시 폐기 전까지 유효 | OIDC 역할로 전환, 키 삭제 |
| ALB가 인터넷에 열려 CloudFront 우회 가능 | HTTPS 없이 직접 접근 | 보안그룹 프리픽스 리스트 + 검증 헤더 |
| ECR 스캔만 켜둠 | 취약 이미지가 그대로 배포 | CRITICAL 검출 시 배포 중단 |
| 경보가 3종만 있음 | 데이터 계층 CPU와 메모리, 사용자 계층 미커버 | RDS CPU와 메모리, ALB 5xx 추가 |

배포 중 502 건은 설정이 세 계층에 걸쳐 있습니다. ALB 등록 해제 → Pod preStop과 grace period → gunicorn graceful timeout으로 한 곳만 맞추면 나머지가 해당 값을 무시합니다.

---

# 3. 의사결정

## EKS
- 해당 프로젝트 규모는 ECS Fargate가 적합하지만 실무 수요는 Kubernetes 집중

> 컨트롤플레인 월 약 $72와 노드/애드온 직접 관리를 감수합니다.


## HTTPS는 CloudFront 기본 인증서
- 개인 도메인 없이 바로 HTTPS 확보, 엣지에서 종단하고 진입점을 하나로 통일
- 캐싱 미사용, 동적 API만 다루므로 TTL 0값

> 커스텀 도메인은 사용 불가로 CloudFront와 ALB 구간 사이는 HTTP로 남습니다.

## ALB는 CloudFront 전용
- 보안그룹에서 CloudFront 관리형 프리픽스 리스트만 통과시키고, ALB 리스너 규칙에서 `X-Origin-Verify` 헤더까지 맞아야 앱 도달
- 헤더 값은 tfvars만 두고 매니페스트는 플레이스홀더로 커밋

## 권한
- 앱 S3 읽기는 IRSA로 서비스 어카운트에만 부여, 노드 역할로 붙이면 해당 노드의 모든 Pod가 가짐
- GitHub Actions는 OIDC, 저장소와 브랜치가 일치하는 워크플로만 짧은 수명의 토큰으로 역할을 받음
- EKS 권한은 Access Entry로 `health-record` 네임스페이스 Edit만 부여

## HPA CPU 50%, Pod 2~6개
- 낮으면 과잉 증설, 높으면 대응이 늦어 50%는 보수적으로 미리 늘리는 값
- 최소 2개는 다중 AZ 유지, 최대 6개는 비용 상한
- t3.medium 2대면 vCPU 4개(4000m), 시스템 예약분을 빼도 6개 × 100m = 600m은 여유라 노드 증설이 필요 없어 Cluster Autoscaler 미적용
- 지표는 CPU, 이 앱은 요청 처리가 CPU에 바로 반영되고 Python 앱 메모리는 부하와 무관하게 유지되는 편

## RDS 단일 AZ + 백업 7일
- Multi-AZ는 비용 두 배로 제외, 데이터 계층은 단일 장애점으로 남기고 백업을 통한 복구 경로 확보
- RTO 스냅샷 복원 약 10~20분, RPO 최대 5분

## S3 Gateway Endpoint
- 무료이며 NAT 데이터 처리 요금만큼 절감, ECR용 Interface Endpoint는 시간당 요금이 있어 미적용

## Secrets Manager 대신 Kubernetes Secret
- 시크릿당 요금과 External Secrets Operator 설치를 할 경우 해당 규모에서는 과잉

> 자동 순환과 감사가 없고 Secret 생성은 IaC 밖에 남습니다. RDS 마스터 비밀번호가 Terraform state에 평문으로 남아 운영 전환 시 `manage_master_user_password`로 옮길 예정입니다.

## Ingress 경로 분기
- `/health`는 ALB 헬스체크용으로 외부 요청은 403, 헬스체크는 리스너 규칙을 거치지 않아 영향 없음
- 헬스체크 15초 × 2회 = 30초 안에 비정상 격리, 기본값(60초)의 절반

## EKS API 엔드포인트 퍼블릭
- GitHub Actions 러너 대역이 4,000개 이상으로 EKS CIDR 제한은 40개, self-hosted 러너는 상시 비용
- IAM 인증과 Audit 로그로 추적, 닫을 수 없는 것과 닫지 않은 것은 다름

## apply 두 단계
- ALB는 Kubernetes, CloudFront는 Terraform이 생성, `alb_created` 변수로 1회차(기반) / 2회차(CloudFront, ALB 5xx 경보) 분리
- destroy는 역순으로 Ingress 삭제 → `alb_created = false` → destroy

## 베이스 이미지 alpine
- slim에서 CRITICAL 4건, 의존성이 순수 파이썬이며 alpine으로 변경하여도 동작 차이 없음
