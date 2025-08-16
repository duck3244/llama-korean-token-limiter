# 🇰🇷 Korean Llama Token Limiter

한국어 특화 LLM 토큰 사용량 제한 시스템

[![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.104+-green.svg)](https://fastapi.tiangolo.com)
[![vLLM](https://img.shields.io/badge/vLLM-0.2.7+-red.svg)](https://github.com/vllm-project/vllm)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 📋 개요

Korean Llama Token Limiter는 한국어 LLM(Large Language Model) 서비스의 토큰 사용량을 효율적으로 관리하고 제한하는 시스템입니다. RTX 4060 8GB GPU 환경에 최적화되어 있으며, 다음과 같은 기능을 제공합니다:

- 🔢 **한국어 특화 토큰 계산**: 한글 1글자 ≈ 1.2토큰으로 정확한 계산
- ⚡ **실시간 속도 제한**: 분당/시간당/일일 토큰 사용량 제한
- 👥 **다중 사용자 관리**: API 키 기반 사용자별 개별 제한
- 🔄 **OpenAI 호환 API**: 표준 ChatGPT API와 완전 호환
- 📊 **실시간 모니터링**: 사용량 통계 및 대시보드
- 🚀 **고성능**: vLLM 기반 GPU 가속 추론

## 🏗️ 시스템 아키텍처

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Client App    │───▶│  Token Limiter   │───▶│   vLLM Server   │
│                 │    │   (Port 8080)    │    │   (Port 8000)   │
│ - Web App       │    │                  │    │                 │
│ - Mobile App    │    │ - Rate Limiting  │    │ - GPU Inference │
│ - API Client    │    │ - User Management│    │ - Model Serving │
└─────────────────┘    │ - Token Counting │    └─────────────────┘
                       │ - Statistics     │              │
                       └──────────────────┘              │
                                │                        │
                       ┌──────────────────┐              │
                       │   Redis/SQLite   │              │
                       │                  │              │
                       │ - Usage Data     │    ┌─────────────────┐
                       │ - User Stats     │    │ Korean LLM Model│
                       │ - Rate Limits    │    │                 │
                       └──────────────────┘    │ - distilgpt2    │
                                              │ - beomi/llama   │
                                              └─────────────────┘
```

## 🚀 빠른 시작

### 사전 요구사항

- **Python**: 3.11 이상
- **GPU**: NVIDIA GPU (RTX 4060 권장) + CUDA 12.1+
- **메모리**: 8GB RAM 이상
- **저장공간**: 10GB 이상

### 1. 저장소 클론

```bash
git clone https://github.com/your-username/llama-korean-token-limiter.git
cd llama-korean-token-limiter
```

### 2. 환경 설정

#### Conda 환경 (권장)

```bash
# Conda 환경 생성
conda create -n korean_llm python=3.11
conda activate korean_llm

# 패키지 설치
bash scripts/install_conda_packages.sh
```

#### Python venv 환경

```bash
# 가상환경 생성
python -m venv venv
source venv/bin/activate  # Linux/Mac
# 또는
venv\Scripts\activate  # Windows

# 패키지 설치
bash scripts/install_packages.sh
```

### 3. Redis 설정

#### Docker 사용 (권장)

```bash
docker run -d --name korean-redis -p 6379:6379 redis:alpine
```

#### 로컬 Redis 설치

```bash
# Ubuntu/Debian
sudo apt install redis-server

# macOS
brew install redis
```

### 4. 시스템 시작

```bash
# 전체 시스템 시작 (vLLM + Token Limiter)
bash scripts/start_korean_system.sh
```

### 5. 테스트

```bash
# 헬스체크
curl http://localhost:8080/health

# 채팅 완성 테스트
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-user1-korean-key-def" \
  -d '{
    "model": "korean-llama",
    "messages": [{"role": "user", "content": "안녕하세요!"}],
    "max_tokens": 50
  }'
```

## 📚 API 사용법

### 인증

모든 API 요청에는 Authorization 헤더가 필요합니다:

```bash
Authorization: Bearer <API_KEY>
```

### 기본 사용자 API 키

| 사용자 | API 키 | 제한 (RPM/TPM/일일) |
|--------|--------|-------------------|
| 사용자1 | `sk-user1-korean-key-def` | 20/3000/500K |
| 개발자1 | `sk-dev1-korean-key-789` | 50/8000/1.5M |
| 테스트 | `sk-test-korean-key-stu` | 10/1000/100K |

### 채팅 완성 API

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-user1-korean-key-def" \
  -d '{
    "model": "korean-llama",
    "messages": [
      {"role": "system", "content": "당신은 친근한 한국어 AI 어시스턴트입니다."},
      {"role": "user", "content": "파이썬으로 Hello World를 출력하는 방법을 알려주세요."}
    ],
    "max_tokens": 200,
    "temperature": 0.7
  }'
```

### 텍스트 완성 API

```bash
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-user1-korean-key-def" \
  -d '{
    "model": "korean-llama",
    "prompt": "한국의 수도는",
    "max_tokens": 50,
    "temperature": 0.5
  }'
```

### 토큰 계산

```bash
curl 'http://localhost:8080/token-info?text=안녕하세요! 한국어 토큰 계산 테스트입니다.'
```

### 사용량 통계

```bash
# 사용자별 통계
curl http://localhost:8080/stats/user1

# 전체 사용자 목록
curl http://localhost:8080/admin/users
```

## ⚙️ 설정

### 모델 설정 (`config/korean_model.yaml`)

```yaml
server:
  host: "0.0.0.0"
  port: 8080

llm_server:
  url: "http://localhost:8000"
  model_name: "distilgpt2"  # 또는 다른 모델
  
  vllm_args:
    gpu_memory_utilization: 0.8
    max_model_len: 2048
    dtype: "half"
    enforce_eager: true

storage:
  type: "redis"  # 또는 "sqlite"
  redis_url: "redis://localhost:6379"

default_limits:
  rpm: 30      # 분당 요청 수
  tpm: 5000    # 분당 토큰 수
  tph: 300000  # 시간당 토큰 수
  daily: 500000 # 일일 토큰 수
```

### 사용자 설정 (`config/korean_users.yaml`)

```yaml
users:
  사용자1:
    rpm: 20
    tpm: 3000
    daily: 500000
    description: "일반 사용자"
    
  개발자1:
    rpm: 50
    tpm: 8000
    daily: 1500000
    description: "개발자 계정"

api_keys:
  "sk-user1-korean-key-def": "사용자1"
  "sk-dev1-korean-key-789": "개발자1"
```

## 🖥️ 대시보드

Streamlit 기반 웹 대시보드로 실시간 모니터링:

<img src="demo.png" width="500" height="300">

```bash
# 대시보드 시작
streamlit run dashboard/app.py --server.port 8501

# 접속: http://localhost:8501
```

대시보드 기능:
- 📈 실시간 사용량 그래프
- 👥 사용자별 통계
- 🚨 속도 제한 알림
- 📊 시스템 성능 모니터링

## 🔧 문제 해결

### 일반적인 문제들

#### 1. vLLM 서버 시작 실패

```bash
# GPU 메모리 확인
nvidia-smi

# 더 작은 모델 사용
python -m vllm.entrypoints.openai.api_server \
  --model distilgpt2 \
  --gpu-memory-utilization 0.4 \
  --max-model-len 256
```

#### 2. 패키지 충돌

```bash
# vLLM 호환성 문제 해결
bash scripts/fix_vllm_compatibility.sh
```

#### 3. Redis 연결 실패

```bash
# SQLite 모드로 전환
sed -i 's/type: "redis"/type: "sqlite"/' config/korean_model.yaml
```

#### 4. 한국어 인코딩 문제

시스템에서 자동으로 ASCII 안전 인코딩을 사용합니다. 한국어 사용자명은 내부적으로 영어로 변환됩니다.

### 로그 확인

```bash
# Token Limiter 로그
tail -f logs/token_limiter.log

# vLLM 서버 로그  
tail -f logs/vllm.log

# 전체 시스템 상태
curl http://localhost:8080/health
```

### 성능 최적화

#### RTX 4060 8GB 최적화

```bash
# GPU 메모리 사용률 40%로 제한
--gpu-memory-utilization 0.4

# 컨텍스트 길이 단축
--max-model-len 256

# FP16 사용
--dtype half
```

## 🧪 테스트

### 전체 시스템 테스트

```bash
bash scripts/test_korean.sh
```

### 개별 컴포넌트 테스트

```bash
# vLLM 진단
python test_vllm_simple.py

# 토큰 카운터 테스트
curl 'http://localhost:8080/token-info?text=테스트'

# 속도 제한 테스트
for i in {1..10}; do
  curl -X POST http://localhost:8080/v1/chat/completions \
    -H "Authorization: Bearer sk-test-korean-key-stu" \
    -d '{"model":"korean-llama","messages":[{"role":"user","content":"Test '$i'"}],"max_tokens":10}'
done
```

## 📊 성능 벤치마크

### RTX 4060 Laptop GPU 기준

| 모델 | 토큰/초 | 메모리 사용량 | 동시 사용자 |
|------|---------|--------------|------------|
| distilgpt2 | ~150 | 2.5GB | 4-6명 |
| gpt2 | ~120 | 3.2GB | 3-4명 |
| beomi/llama-2-ko-7b | ~45 | 7.5GB | 1-2명 |

### 토큰 계산 성능

- 한국어 텍스트: ~5000 글자/초
- 영어 텍스트: ~8000 글자/초
- 혼합 텍스트: ~6000 글자/초

## 🔒 보안

### API 키 관리

- API 키는 환경변수나 안전한 설정 파일에 저장
- 프로덕션에서는 JWT 토큰이나 OAuth 사용 권장
- HTTPS 사용 필수

### 속도 제한

- 기본적으로 IP별 제한은 비활성화
- 필요시 `rate_limit_by_ip: true` 설정
- DDoS 방어를 위한 웹 서버(Nginx) 사용 권장

## 🚢 배포

### Docker 배포

```bash
# Docker 이미지 빌드
docker build -t korean-token-limiter .

# 컨테이너 실행
docker run -d \
  --name korean-limiter \
  --gpus all \
  -p 8080:8080 \
  -v $(pwd)/config:/app/config \
  korean-token-limiter
```

### 프로덕션 배포

```bash
# Gunicorn 사용
gunicorn main:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8080 \
  --access-logfile logs/access.log
```

