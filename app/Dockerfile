# ECR 스캔 게이트가 slim 이미지의 OS 패키지에서 CRITICAL 4건 잡아 배포 중단
# 앱 의존성이 전부 순수 파이썬(Flask, PyMySQL, boto3, gunicorn), alpine으로 바꿔도 동작 차이 없어 패키지 수와 취약점 노출 적음
FROM python:3.12-alpine

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN adduser -D -u 1000 appuser
USER appuser

EXPOSE 8080

# readOnlyRootFilesystem과 사용하기 위해 워커 임시파일 경로 /tmp(emptyDir) 지정
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--graceful-timeout", "30", "--worker-tmp-dir", "/tmp", "--access-logfile", "-", "app:app"]
