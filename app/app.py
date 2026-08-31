# 배포 파이프라인 검증
import logging
import os

import boto3
import pymysql
from flask import Flask, jsonify

# 예외 상세를 서버 로그만 남겨 응답 내보내지 않음
logging.basicConfig(level=logging.INFO)

app = Flask(__name__)

# 환경변수 설정 읽기 (배포 시 주입)
DB_HOST = os.environ.get("DB_HOST", "")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
DB_NAME = os.environ.get("DB_NAME", "healthrecord")
S3_BUCKET = os.environ.get("S3_BUCKET", "")

@app.route("/")
def home():
    return jsonify(
        service="건강·복약 기록 서비스",
        status="running",
        message="인프라 위에서 정상 작동 중입니다."
    )

@app.route("/health")
def health():
    # Kubernetes readiness/liveness 프로브 대상
    return jsonify(status="ok")

@app.route("/check/db")
def check_db():
    # RDS(MySQL) 연결 확인
    try:
        conn = pymysql.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            connect_timeout=5,
        )
        conn.close()
        return jsonify(db="connected")
    except Exception:
        # 예외 문자열 호스트명과 사용자명, 내부 경로 포함될 수 있어 인터넷으로 노출되는 응답 본문 담지 않고 서버 로그만 보존
        logging.exception("db check failed")
        return jsonify(db="failed"), 500

@app.route("/check/s3")
def check_s3():
    # S3 버킷 접근 확인
    try:
        s3 = boto3.client("s3")
        s3.head_bucket(Bucket=S3_BUCKET)
        return jsonify(s3="connected")
    except Exception:
        logging.exception("s3 check failed")
        return jsonify(s3="failed"), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
