# 한국어 Llama Token Limiter Docker 이미지
FROM nvidia/cuda:12.1-devel-ubuntu22.04

# 환경 변수 설정
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONIOENCODING=utf-8
ENV LANG=ko_KR.UTF-8
ENV LC_ALL=ko_KR.UTF-8

# 작업 디렉토리 설정
WORKDIR /app

# 시스템 패키지 업데이트 및 필수 도구 설치
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    python3-pip \
    build-essential \
    curl \
    git \
    wget \
    locales \
    redis-tools \
    pkg-config \
    libffi-dev \
    software-properties-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 한국어 로케일 설정
RUN locale-gen ko_KR.UTF-8

# Python 심볼릭 링크 생성
RUN ln -s /usr/bin/python3.11 /usr/bin/python

# 필요한 디렉토리 생성
RUN mkdir -p /app/{src/{core,storage,proxy,utils},config,dashboard,logs,tests,pids,tokenizer_cache,backups}

# Python 요구사항 파일 복사 및 설치
COPY scripts/requirements.txt .

# pip 업그레이드 및 기본 패키지 설치
RUN pip install --no-cache-dir --upgrade pip wheel setuptools

# PyTorch 및 GPU 관련 패키지 설치
RUN pip install --no-cache-dir torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 \
    --index-url https://download.pytorch.org/whl/cu121

# vLLM 설치
RUN pip install --no-cache-dir vllm==0.2.7

# Flash Attention 설치 (선택사항)
RUN pip install --no-cache-dir flash-attn==2.3.4 --no-build-isolation || echo "Flash Attention 설치 실패 (선택사항)"

# xformers 설치
RUN pip install --no-cache-dir xformers==0.0.22.post7 || echo "xformers 설치 실패 (선택사항)"

# 나머지 요구사항 설치
RUN pip install --no-cache-dir -r requirements.txt

# 애플리케이션 파일 복사
COPY . .

# 스크립트 실행 권한 설정
RUN chmod +x scripts/*.sh

# 로그 디렉토리 권한 설정
RUN chmod 755 logs

# 한국어 모델 사전 다운로드 (선택사항 - 빌드 시간 단축을 위해 주석 처리 가능)
# RUN python -c "from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1', cache_dir='./tokenizer_cache', trust_remote_code=True)"

# 포트 노출
EXPOSE 8080 8000 8501

# 환경 변수 설정 파일 복사
COPY .env.docker .env

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 기본 명령어 (개발/테스트용)
CMD ["python", "main_korean.py"]

# 멀티 스테이지 빌드를 위한 라벨
LABEL maintainer="Korean Token Limiter Team"
LABEL version="1.0.0"
LABEL description="Korean optimized token usage limiter for Llama models"

# GPU 사용을 위한 런타임 설정 안내 주석
# docker run --gpus all -p 8080:8080 -p 8000:8000 korean-token-limiter