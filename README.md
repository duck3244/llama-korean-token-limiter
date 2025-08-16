# 🇰🇷 Korean Llama Token Limiter

**한국어 Llama 모델용 토큰 사용량 제한 시스템**

RTX 4060 8GB GPU에 최적화된 한국어 Llama-3.2-Korean 모델을 위한 토큰 사용량 관리 및 속도 제한 시스템입니다.

## ✨ 주요 기능

- 🇰🇷 **한국어 특화**: 한글 토큰 특성을 반영한 정확한 토큰 계산
- ⚡ **실시간 제한**: 분/시간/일별 토큰 및 요청 수 제한
- 🎯 **RTX 4060 최적화**: 8GB VRAM 환경에 맞춘 메모리 효율적 운영
- 📊 **실시간 모니터링**: Streamlit 기반 한국어 대시보드
- 🔄 **자동 복구**: 쿨다운 및 사용량 자동 초기화
- 💾 **유연한 저장소**: Redis 또는 SQLite 지원
- 🔒 **사용자 관리**: API 키 기반 한국어 사용자 인증

## 🏗️ 시스템 구조

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client App    │    │  Token Limiter  │    │   vLLM Server   │
│                 │────│   (Port 8080)   │────│   (Port 8000)   │
│   API 요청      │    │  한국어 토큰    │    │ Korean Llama    │
│                 │    │   사용량 제한   │    │     모델        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                       ┌─────────────────┐
                       │   Redis/SQLite  │
                       │   사용량 저장   │
                       └─────────────────┘
```

## 🚀 빠른 시작

### 1. 시스템 요구사항

- **OS**: Ubuntu 22.04 (권장)
- **GPU**: NVIDIA RTX 4060 8GB 이상
- **CUDA**: 12.1+
- **Python**: 3.9+
- **RAM**: 16GB 권장
- **디스크**: 10GB 이상

### 2. 자동 설치

```bash
# 저장소 클론
git clone https://github.com/your-repo/korean-llama-token-limiter.git
cd korean-llama-token-limiter

# 자동 설치 실행
chmod +x setup.sh
./setup.sh

# 시스템 시작
./scripts/start_korean_system.sh
```

### 3. 수동 설치

<details>
<summary>수동 설치 단계 보기</summary>

```bash
# 1. 의존성 설치
sudo apt update
sudo apt install python3.11 python3.11-venv python3-pip build-essential curl git

# 2. Python 환경 설정
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip

# 3. PyTorch 설치 (CUDA 12.1)
pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu121

# 4. vLLM 설치
pip install vllm==0.2.7

# 5. 추가 패키지 설치
pip install -r requirements.txt

# 6. Redis 시작 (Docker)
docker run -d --name korean-redis -p 6379:6379 redis:alpine

# 7. 시스템 시작
python main_korean.py
```

</details>

## 🔧 설정

### 기본 설정 파일

#### `config/korean_model.yaml`
```yaml
server:
  host: "0.0.0.0"
  port: 8080

llm_server:
  url: "http://localhost:8000"
  model_name: "torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1"

default_limits:
  rpm: 30      # 분당 요청 수
  tpm: 5000    # 분당 토큰 수
  tph: 300000  # 시간당 토큰 수
  daily: 500000 # 일일 토큰 수
```

#### `config/korean_users.yaml`
```yaml
users:
  사용자1:
    rpm: 20
    tpm: 3000
    daily: 500000
    description: "일반 사용자 1"

api_keys:
  "sk-user1-korean-key-def": "사용자1"
```

## 📡 API 사용법

### 채팅 완성 요청

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-user1-korean-key-def" \
  -d '{
    "model": "korean-llama",
    "messages": [
      {
        "role": "system", 
        "content": "당신은 친근한 한국어 AI 어시스턴트입니다."
      },
      {
        "role": "user", 
        "content": "안녕하세요! 한국어로 간단한 인사를 해주세요."
      }
    ],
    "max_tokens": 150,
    "temperature": 0.7
  }'
```

### 사용량 조회

```bash
# 사용자 통계 조회
curl http://localhost:8080/stats/사용자1

# 시스템 전체 통계
curl http://localhost:8080/admin/statistics

# 상위 사용자 조회
curl http://localhost:8080/admin/top-users?limit=10&period=today
```

### 토큰 계산

```bash
curl "http://localhost:8080/token-info?text=안녕하세요! 한국어 토큰 계산 테스트입니다."
```

## 📊 대시보드

Streamlit 기반 실시간 모니터링 대시보드:

```bash
# 대시보드 시작
streamlit run dashboard/app.py --server.port 8501

# 브라우저에서 접속
open http://localhost:8501
```

### 대시보드 기능

- 📈 **실시간 모니터링**: 사용량, 상위 사용자, 시스템 상태
- 👥 **사용자 관리**: 개별 사용자 통계 및 제한 관리
- 📊 **통계 분석**: 기간별 사용량 분석 및 트렌드
- 🔧 **시스템 관리**: 설정 로드, 토큰 계산 테스트

## 🐳 Docker 실행

### Docker Compose (권장)

```bash
# 모든 서비스 시작
docker-compose up -d

# 모니터링 포함 시작
docker-compose --profile monitoring up -d

# 로그 확인
docker-compose logs -f token-limiter
```

### 개별 Docker 실행

```bash
# 이미지 빌드
docker build -t korean-token-limiter .

# 컨테이너 실행 (GPU 포함)
docker run --gpus all \
  -p 8080:8080 \
  -v $(pwd)/config:/app/config \
  -v $(pwd)/logs:/app/logs \
  korean-token-limiter
```

## 🧪 테스트

### 자동 테스트 실행

```bash
# 전체 시스템 테스트
./scripts/test_korean.sh

# 개별 API 테스트
pytest tests/ -v
```

### 수동 테스트

```bash
# 시스템 상태 확인
curl http://localhost:8080/health

# 간단한 채팅 테스트
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-test-korean-key-stu" \
  -d '{"model": "korean-llama", "messages": [{"role": "user", "content": "안녕하세요"}], "max_tokens": 50}'
```

## 📝 사용자 관리

### 새 사용자 추가

1. `config/korean_users.yaml` 편집:
```yaml
users:
  신규사용자:
    rpm: 15
    tpm: 2000
    tph: 120000
    daily: 300000
    cooldown_minutes: 5
    description: "신규 사용자"

api_keys:
  "sk-new-user-key-123": "신규사용자"
```

2. 설정 다시 로드:
```bash
curl -X POST http://localhost:8080/admin/reload-config
```

### 사용량 초기화

```bash
# 특정 사용자 사용량 초기화
curl -X DELETE http://localhost:8080/admin/reset-usage/사용자1
```

## 🔧 문제 해결

### 일반적인 문제들

#### 1. GPU 메모리 부족
```bash
# GPU 메모리 확인
nvidia-smi

# 메모리 정리
sudo fuser -v /dev/nvidia*
sudo kill -9 <PID>

# 설정에서 메모리 사용률 조정 (config/korean_model.yaml)
gpu_memory_utilization: 0.7  # 0.8에서 0.7로 낮춤
```

#### 2. 모델 다운로드 실패
```bash
# 캐시 정리
rm -rf ~/.cache/huggingface/

# 수동 다운로드
python -c "
from transformers import AutoTokenizer
tokenizer = AutoTokenizer.from_pretrained(
    'torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1',
    cache_dir='./tokenizer_cache'
)
print('다운로드 완료')
"
```

#### 3. Redis 연결 실패
```bash
# Redis 상태 확인
redis-cli ping

# Docker Redis 재시작
docker restart korean-redis

# 또는 로컬 Redis 설치
sudo apt install redis-server
sudo systemctl start redis
```

#### 4. 포트 충돌
```bash
# 포트 사용 확인
sudo lsof -i :8080
sudo lsof -i :8000

# 프로세스 종료
sudo kill -9 <PID>
```

### 로그 확인

```bash
# Token Limiter 로그
tail -f logs/token_limiter.log

# vLLM 서버 로그
tail -f logs/vllm_korean_server.log

# 시스템 전체 로그
journalctl -f
```

## 📈 성능 최적화

### RTX 4060 8GB 최적화 팁

1. **메모리 설정 조정**:
```yaml
# config/korean_model.yaml
vllm_args:
  gpu_memory_utilization: 0.8  # 필요시 0.7로 낮춤
  max_model_len: 2048          # 길이 줄여서 메모리 절약
  dtype: "half"                # FP16 사용
```

2. **동시 요청 수 제한**:
```yaml
default_limits:
  rpm: 20  # 30에서 20으로 낮춤
  tpm: 3000  # 5000에서 3000으로 낮춤
```

3. **시스템 환경 변수**:
```bash
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export CUDA_LAUNCH_BLOCKING=1
```

## 🔗 유용한 링크

- 📚 [vLLM 문서](https://docs.vllm.ai/)
- 🤖 [Transformers 라이브러리](https://huggingface.co/docs/transformers/)
- 🇰🇷 [한국어 Llama 모델](https://huggingface.co/torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1)
- 📊 [Streamlit 문서](https://docs.streamlit.io/)

## 🛠️ 개발 가이드

### 개발 환경 설정

```bash
# 개발 모드 설치
pip install -e .

# 개발 도구 설치
pip install black flake8 pytest

# 코드 포맷팅
black src/ tests/

# 린팅
flake8 src/ tests/

# 테스트 실행
pytest tests/ -v --cov=src/
```
