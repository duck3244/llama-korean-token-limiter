#!/bin/bash
# 한국어 Llama Token Limiter 전체 시스템 시작 스크립트

set -e

echo "🇰🇷 한국어 Llama Token Limiter 시스템 시작"
echo "=============================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 디렉토리 생성
mkdir -p logs

# PID 파일 저장 경로
PID_DIR="./pids"
mkdir -p $PID_DIR

# 기존 프로세스 정리 함수
cleanup_processes() {
    echo -e "${YELLOW}🧹 기존 프로세스 정리 중...${NC}"

    # vLLM 프로세스 종료
    pkill -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true

    # Token Limiter 프로세스 종료
    pkill -f "main_korean.py" 2>/dev/null || true
    pkill -f "main.py" 2>/dev/null || true

    # PID 파일 정리
    rm -f $PID_DIR/*.pid

    sleep 2
    echo -e "${GREEN}✅ 프로세스 정리 완료${NC}"
}

# GPU 상태 확인 함수
check_gpu() {
    echo -e "${BLUE}🔍 GPU 상태 확인...${NC}"

    # nvidia-smi 경로 확인 (여러 방법으로)
    NVIDIA_SMI=""
    if command -v nvidia-smi >/dev/null 2>&1; then
        NVIDIA_SMI="nvidia-smi"
    elif [ -x "/usr/bin/nvidia-smi" ]; then
        NVIDIA_SMI="/usr/bin/nvidia-smi"
    elif [ -x "/usr/local/cuda/bin/nvidia-smi" ]; then
        NVIDIA_SMI="/usr/local/cuda/bin/nvidia-smi"
    elif which nvidia-smi >/dev/null 2>&1; then
        NVIDIA_SMI=$(which nvidia-smi)
    else
        echo -e "${RED}❌ nvidia-smi를 찾을 수 없습니다.${NC}"
        echo "다음 경로를 확인하세요:"
        echo "  /usr/bin/nvidia-smi"
        echo "  /usr/local/cuda/bin/nvidia-smi"
        echo "PATH 확인: $PATH"

        # GPU 없이 계속 진행할지 묻기
        echo "GPU 없이 CPU 모드로 계속 진행하시겠습니까? (y/N):"
        read REPLY
        if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
            echo -e "${YELLOW}⚠️ CPU 모드로 진행합니다. vLLM은 건너뜁니다.${NC}"
            GPU_AVAILABLE=false
            return 0
        else
            exit 1
        fi
    fi

    echo "nvidia-smi 경로: $NVIDIA_SMI"
    GPU_AVAILABLE=true

    echo "GPU 정보:"
    $NVIDIA_SMI --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu --format=csv,noheader,nounits || {
        echo -e "${YELLOW}⚠️ GPU 정보 조회 실패, 기본 정보만 표시${NC}"
        $NVIDIA_SMI
    }

    # GPU 메모리 사용량 확인
    memory_used=$($NVIDIA_SMI --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null || echo "0")
    memory_total=$($NVIDIA_SMI --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || echo "8192")

    if [ "$memory_used" != "0" ] && [ "$memory_total" != "0" ]; then
        memory_percent=$((memory_used * 100 / memory_total))
        echo "GPU 메모리 사용률: ${memory_percent}%"

        if [ $memory_percent -gt 80 ]; then
            echo -e "${YELLOW}⚠️ GPU 메모리 사용률이 높습니다 (${memory_percent}%). 정리를 권장합니다.${NC}"
            echo "계속 진행하시겠습니까? (y/N):"
            read REPLY
            if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
                exit 1
            fi
        fi
    fi
}

# Python 환경 확인 함수
check_python_env() {
    echo -e "${BLUE}🐍 Python 환경 확인...${NC}"

    # 가상환경 확인
    if [ -z "$VIRTUAL_ENV" ] && [ -z "$CONDA_DEFAULT_ENV" ]; then
        echo -e "${YELLOW}⚠️ 가상환경이 활성화되지 않은 것 같습니다${NC}"
        echo "현재 Python: $(which python)"
        echo "계속 진행하시겠습니까? (y/N):"
        read REPLY
        if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
            echo "가상환경을 활성화하고 다시 실행하세요:"
            echo "  conda activate your_env_name"
            echo "  # 또는"
            echo "  source venv/bin/activate"
            exit 1
        fi
    fi

    # 필수 패키지 확인
    echo "필수 패키지 확인 중..."
    python -c "
import sys
required_packages = ['vllm', 'fastapi', 'transformers', 'redis', 'yaml']
missing = []

for pkg in required_packages:
    try:
        if pkg == 'yaml':
            import yaml
        else:
            __import__(pkg)
        print(f'✅ {pkg}')
    except ImportError:
        print(f'❌ {pkg}')
        missing.append(pkg)

if missing:
    print(f'누락된 패키지: {missing}')
    print('pip install -r requirements.txt 를 실행하세요.')
    sys.exit(1)
else:
    print('✅ 모든 필수 패키지가 설치되어 있습니다.')
"

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Python 환경 확인 실패${NC}"
        exit 1
    fi
}

# Redis 시작 함수
start_redis() {
    echo -e "${BLUE}🔴 Redis 시작 중...${NC}"

    # Redis 연결 확인 (이미 실행 중인지)
    if redis-cli -h localhost -p 6379 ping >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Redis가 이미 실행 중입니다${NC}"
        return 0
    fi

    # Docker 사용 가능 여부 확인
    if command -v docker >/dev/null 2>&1; then
        echo "Docker로 Redis 시작 중..."

        # 기존 Redis 컨테이너 확인
        if docker ps | grep -q korean-redis; then
            echo "기존 Redis 컨테이너가 실행 중입니다."
        else
            # 중지된 컨테이너 제거
            docker rm korean-redis 2>/dev/null || true

            # 새 Redis 컨테이너 시작
            docker run -d \
                --name korean-redis \
                -p 6379:6379 \
                --restart unless-stopped \
                redis:alpine \
                redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Redis 컨테이너 시작됨${NC}"
            else
                echo -e "${RED}❌ Docker Redis 시작 실패${NC}"
                echo "로컬 Redis 설치를 시도합니다..."
                install_local_redis
            fi
        fi
    else
        echo -e "${YELLOW}⚠️ Docker를 찾을 수 없습니다${NC}"
        echo "로컬 Redis 설치를 시도합니다..."
        install_local_redis
    fi

    # Redis 연결 확인
    echo "Redis 연결 확인 중..."
    for i in $(seq 1 30); do
        if redis-cli -h localhost -p 6379 ping >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Redis 연결 확인됨${NC}"
            return 0
        else
            echo "대기 중... ($i/30)"
            sleep 1
        fi
    done

    echo -e "${RED}❌ Redis 연결 실패${NC}"
    echo ""
    echo "Redis 설치 옵션:"
    echo "1. Docker 설치 후 재실행:"
    echo "   curl -fsSL https://get.docker.com -o get-docker.sh"
    echo "   sudo sh get-docker.sh"
    echo ""
    echo "2. 로컬 Redis 설치:"
    echo "   Ubuntu: sudo apt install redis-server"
    echo "   macOS: brew install redis"
    echo ""
    echo "3. SQLite 모드로 실행 (Redis 없이):"
    echo "   config/korean_model.yaml에서 storage.type을 'sqlite'로 변경"

    echo ""
    echo "SQLite 모드로 계속 진행하시겠습니까? (y/N):"
    read REPLY
    if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
        echo -e "${BLUE}📁 SQLite 모드로 전환합니다${NC}"
        switch_to_sqlite_mode
        return 0
    else
        exit 1
    fi
}

# 로컬 Redis 설치 시도
install_local_redis() {
    echo -e "${BLUE}🔧 로컬 Redis 설치 시도 중...${NC}"

    # 운영체제 감지
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS=$(uname -s)
    fi

    case $OS in
        ubuntu|debian)
            echo "Ubuntu/Debian에서 Redis 설치 중..."
            sudo apt update
            sudo apt install -y redis-server
            sudo systemctl start redis-server
            sudo systemctl enable redis-server
            ;;
        centos|rhel|fedora)
            echo "CentOS/RHEL/Fedora에서 Redis 설치 중..."
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y redis
            else
                sudo yum install -y redis
            fi
            sudo systemctl start redis
            sudo systemctl enable redis
            ;;
        Darwin|macos)
            echo "macOS에서 Redis 설치 중..."
            if command -v brew >/dev/null 2>&1; then
                brew install redis
                brew services start redis
            else
                echo -e "${RED}❌ Homebrew가 설치되지 않았습니다${NC}"
                echo "Homebrew 설치: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            ;;
        *)
            echo -e "${YELLOW}⚠️ 지원하지 않는 OS입니다: $OS${NC}"
            echo "수동으로 Redis를 설치해주세요."
            return 1
            ;;
    esac

    echo -e "${GREEN}✅ 로컬 Redis 설치 시도 완료${NC}"
}

# SQLite 모드로 전환
switch_to_sqlite_mode() {
    echo -e "${BLUE}🔄 SQLite 모드로 설정 변경 중...${NC}"

    # 설정 파일 백업
    cp config/korean_model.yaml config/korean_model.yaml.backup

    # SQLite 모드로 변경
    if command -v sed >/dev/null 2>&1; then
        sed -i.bak 's/type: "redis"/type: "sqlite"/' config/korean_model.yaml
        sed -i.bak 's/type: redis/type: sqlite/' config/korean_model.yaml
        echo -e "${GREEN}✅ SQLite 모드로 설정 변경됨${NC}"
        echo "데이터베이스 파일: korean_usage.db"
    else
        echo -e "${YELLOW}⚠️ 설정 파일을 수동으로 변경하세요:${NC}"
        echo "config/korean_model.yaml에서 storage.type을 'sqlite'로 변경"
    fi
}

# vLLM 서버 시작 함수
start_vllm() {
    # GPU가 없으면 vLLM 건너뛰기
    if [ "$GPU_AVAILABLE" = false ]; then
        echo -e "${YELLOW}⚠️ GPU가 없어서 vLLM 서버를 건너뜁니다${NC}"
        echo -e "${BLUE}💡 CPU 전용 모드로 Token Limiter만 실행됩니다${NC}"
        return 0
    fi

    echo -e "${BLUE}🚀 vLLM 서버 시작 중...${NC}"

    # vLLM 시작 스크립트 확인 및 생성
    if [ ! -f "scripts/start_vllm_korean.sh" ]; then
        echo "⚠️ scripts/start_vllm_korean.sh 파일이 없습니다. 직접 vLLM을 시작합니다..."
        start_vllm_directly
        return $?
    fi

    # 실행 권한 확인
    if [ ! -x "scripts/start_vllm_korean.sh" ]; then
        chmod +x scripts/start_vllm_korean.sh
    fi

    # vLLM 서버 백그라운드 시작
    nohup ./scripts/start_vllm_korean.sh > logs/vllm_startup.log 2>&1 &
    VLLM_PID=$!
    echo $VLLM_PID > $PID_DIR/vllm.pid

    echo "vLLM 서버 PID: $VLLM_PID"
    echo "로그: tail -f logs/vllm_startup.log"

    # vLLM 서버 준비 대기
    wait_for_vllm_ready
}

# vLLM 직접 시작 함수
start_vllm_directly() {
    echo -e "${BLUE}🔧 vLLM 직접 시작 중...${NC}"

    # 환경 변수 설정
    export CUDA_VISIBLE_DEVICES=0
    export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

    echo -e "${YELLOW}⚠️ Llama 3.2 모델이 현재 vLLM 0.2.7과 호환되지 않습니다${NC}"
    echo "호환되는 한국어 모델로 전환합니다..."

    # 사용 가능한 한국어 모델들 (vLLM 0.2.7 호환)
    KOREAN_MODELS=(
        "beomi/llama-2-ko-7b"
        "beomi/KoAlpaca-Polyglot-5.8B"
        "nlpai-lab/kullm-polyglot-5.8b-v2"
        "meta-llama/Llama-2-7b-hf"
    )

    SELECTED_MODEL=""

    # 사용할 모델 선택
    for model in "${KOREAN_MODELS[@]}"; do
        echo "🔍 $model 호환성 확인 중..."

        # 간단한 config 체크
        python -c "
from transformers import AutoConfig
try:
    config = AutoConfig.from_pretrained('$model', trust_remote_code=True)
    print('✅ $model 호환됨')
    exit(0)
except Exception as e:
    print('❌ $model 실패: ', str(e)[:100])
    exit(1)
" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            SELECTED_MODEL="$model"
            echo -e "${GREEN}✅ $model 선택됨${NC}"
            break
        fi
    done

    if [ -z "$SELECTED_MODEL" ]; then
        echo -e "${RED}❌ 호환되는 한국어 모델을 찾을 수 없습니다${NC}"
        echo ""
        echo "대안:"
        echo "1. vLLM 업그레이드: pip install vllm>=0.3.0"
        echo "2. CPU 모드로 실행: python main_korean.py"
        return 1
    fi

    # 기존 HuggingFace 캐시 확인
    if [ -d ~/.cache/huggingface ]; then
        echo "✅ 기존 HuggingFace 캐시 디렉토리 발견"
        echo "   캐시 경로: ~/.cache/huggingface"
    fi

    # vLLM 서버 시작 (백그라운드)
    echo "🚀 vLLM 서버 시작 중..."
    echo "📋 사용 모델: $SELECTED_MODEL"
    echo "⏳ 모델 로딩 중..."

    # vLLM 서버 실행
    nohup python -m vllm.entrypoints.openai.api_server \
        --model "$SELECTED_MODEL" \
        --port 8000 \
        --host 0.0.0.0 \
        --gpu-memory-utilization 0.75 \
        --max-model-len 2048 \
        --dtype half \
        --tensor-parallel-size 1 \
        --enforce-eager \
        --trust-remote-code \
        --disable-log-requests \
        --served-model-name korean-llama \
        --tokenizer-mode auto \
        --download-dir ./model_cache \
        > logs/vllm_direct.log 2>&1 &

    VLLM_PID=$!
    echo $VLLM_PID > $PID_DIR/vllm.pid
    echo "vLLM 서버 PID: $VLLM_PID"
    echo "로그: tail -f logs/vllm_direct.log"

    # 조금 더 기다린 후 로그 확인
    sleep 5
    if [ -f "logs/vllm_direct.log" ]; then
        echo "초기 로그:"
        tail -10 logs/vllm_direct.log | sed 's/^/  /'
    fi

    # 설정 파일도 업데이트
    echo "📝 설정 파일 업데이트 중..."
    if [ -f "config/korean_model.yaml" ]; then
        cp config/korean_model.yaml config/korean_model.yaml.backup
        sed -i "s|model_name:.*|model_name: \"$SELECTED_MODEL\"|" config/korean_model.yaml
        echo "✅ 설정 파일 업데이트됨: $SELECTED_MODEL"
    fi

    # 준비 대기 (시간 연장)
    wait_for_vllm_ready_extended
}

# vLLM 준비 대기 함수 (확장 버전)
wait_for_vllm_ready_extended() {
    echo "vLLM 서버 준비 대기 중... (모델 다운로드 포함, 최대 10분)"
    for i in $(seq 1 600); do  # 최대 10분 대기
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ vLLM 서버 준비 완료 (${i}초)${NC}"
            break
        elif [ $((i % 30)) -eq 0 ]; then
            echo "⏳ vLLM 서버 시작 중... (${i}초 경과)"
            echo "   로그 확인: tail -f logs/vllm_direct.log"

            # 로그 일부 표시
            if [ -f "logs/vllm_direct.log" ]; then
                echo "   최근 로그:"
                tail -3 logs/vllm_direct.log | sed 's/^/     /'
            fi
        fi

        # 프로세스가 죽었는지 확인
        if [ -f "$PID_DIR/vllm.pid" ]; then
            VLLM_PID=$(cat $PID_DIR/vllm.pid)
            if ! kill -0 $VLLM_PID 2>/dev/null; then
                echo -e "${RED}❌ vLLM 서버 프로세스가 종료되었습니다${NC}"
                echo "로그 확인:"
                tail -30 logs/vllm_direct.log
                return 1
            fi
        fi

        sleep 1
    done

    if [ $i -eq 600 ]; then
        echo -e "${RED}❌ vLLM 서버 시작 시간 초과 (10분)${NC}"
        echo "로그 확인:"
        tail -50 logs/vllm_direct.log

        # 대안 제시
        echo ""
        echo "=== 대안 ===:"
        echo "1. 더 작은 모델 사용:"
        echo "   --model microsoft/DialoGPT-medium"
        echo ""
        echo "2. CPU 모드로 실행:"
        echo "   python main_korean.py (vLLM 없이)"
        echo ""
        echo "3. 로그 확인 후 문제 해결:"
        echo "   tail -f logs/vllm_direct.log"

        return 1
    fi

    # 모델 정보 확인
    echo "모델 정보 확인:"
    curl -s http://localhost:8000/v1/models | jq . 2>/dev/null || echo "모델 정보 조회 실패"
    return 0
}

# vLLM 준비 대기 함수
wait_for_vllm_ready() {
    echo "vLLM 서버 준비 대기 중..."
    for i in $(seq 1 120); do  # 최대 2분 대기
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ vLLM 서버 준비 완료 (${i}초)${NC}"
            break
        elif [ $i -eq 60 ]; then
            echo "⏳ vLLM 서버 시작에 시간이 걸리고 있습니다..."
            echo "   로그 확인: tail -f logs/vllm_*.log"
        fi

        # 프로세스가 죽었는지 확인
        if [ -f "$PID_DIR/vllm.pid" ]; then
            VLLM_PID=$(cat $PID_DIR/vllm.pid)
            if ! kill -0 $VLLM_PID 2>/dev/null; then
                echo -e "${RED}❌ vLLM 서버 프로세스가 종료되었습니다${NC}"
                echo "로그 확인:"
                tail -20 logs/vllm_*.log
                return 1
            fi
        fi

        sleep 1
    done

    if [ $i -eq 120 ]; then
        echo -e "${RED}❌ vLLM 서버 시작 시간 초과${NC}"
        echo "로그 확인:"
        tail -20 logs/vllm_*.log
        return 1
    fi

    # 모델 정보 확인
    echo "모델 정보 확인:"
    curl -s http://localhost:8000/v1/models | jq . 2>/dev/null || echo "모델 정보 조회 실패"
    return 0
}

# Token Limiter 시작 함수
start_token_limiter() {
    echo -e "${BLUE}🛡️ Token Limiter 시작 중...${NC}"

    # 설정 파일 확인
    if [ ! -f "config/korean_model.yaml" ]; then
        echo -e "${RED}❌ config/korean_model.yaml 파일이 없습니다${NC}"
        exit 1
    fi

    if [ ! -f "config/korean_users.yaml" ]; then
        echo -e "${RED}❌ config/korean_users.yaml 파일이 없습니다${NC}"
        exit 1
    fi

    # 메인 스크립트 확인
    if [ -f "main_korean.py" ]; then
        MAIN_SCRIPT="main_korean.py"
    elif [ -f "main.py" ]; then
        MAIN_SCRIPT="main.py"
    else
        echo -e "${RED}❌ main_korean.py 또는 main.py 파일이 없습니다${NC}"
        exit 1
    fi

    # Token Limiter 백그라운드 시작
    nohup python $MAIN_SCRIPT > logs/token_limiter.log 2>&1 &
    LIMITER_PID=$!
    echo $LIMITER_PID > $PID_DIR/token_limiter.pid

    echo "Token Limiter PID: $LIMITER_PID"
    echo "로그: tail -f logs/token_limiter.log"

    # Token Limiter 준비 대기
    echo "Token Limiter 준비 대기 중..."
    for i in $(seq 1 60); do
        if curl -s http://localhost:8080/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Token Limiter 준비 완료 (${i}초)${NC}"
            break
        fi

        # 프로세스가 죽었는지 확인
        if ! kill -0 $LIMITER_PID 2>/dev/null; then
            echo -e "${RED}❌ Token Limiter 프로세스가 종료되었습니다${NC}"
            echo "로그 확인:"
            tail -20 logs/token_limiter.log
            exit 1
        fi

        sleep 1
    done

    if [ $i -eq 60 ]; then
        echo -e "${RED}❌ Token Limiter 시작 시간 초과${NC}"
        echo "로그 확인:"
        tail -20 logs/token_limiter.log
        exit 1
    fi
}

# 시스템 상태 확인 함수
check_system_status() {
    echo -e "${BLUE}🔍 시스템 상태 확인...${NC}"

    echo "=== 서비스 상태 ==="

    # vLLM 서버 상태
    if curl -s http://localhost:8000/health >/dev/null; then
        echo -e "vLLM 서버: ${GREEN}✅ 정상${NC}"
    else
        echo -e "vLLM 서버: ${RED}❌ 오류${NC}"
    fi

    # Token Limiter 상태
    if curl -s http://localhost:8080/health >/dev/null; then
        echo -e "Token Limiter: ${GREEN}✅ 정상${NC}"
    else
        echo -e "Token Limiter: ${RED}❌ 오류${NC}"
    fi

    # Redis 상태
    if redis-cli -h localhost -p 6379 ping >/dev/null 2>&1; then
        echo -e "Redis: ${GREEN}✅ 정상${NC}"
    else
        echo -e "Redis: ${RED}❌ 오류${NC}"
    fi

    echo ""
    echo "=== 접속 정보 ==="
    echo "🔗 vLLM 서버: http://localhost:8000"
    echo "🔗 Token Limiter: http://localhost:8080"
    echo "🔗 대시보드: streamlit run dashboard/app.py --server.port 8501"
    echo "🔗 Redis: localhost:6379"

    echo ""
    echo "=== 테스트 명령어 ==="
    echo "curl -X POST http://localhost:8080/v1/chat/completions \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'Authorization: Bearer sk-user1-korean-key-def' \\"
    echo "  -d '{"
    echo "    \"model\": \"korean-llama\","
    echo "    \"messages\": [{"
    echo "      \"role\": \"user\","
    echo "      \"content\": \"안녕하세요! 간단한 인사를 해주세요.\""
    echo "    }],"
    echo "    \"max_tokens\": 100"
    echo "  }'"
}

# 종료 시그널 처리 (호환성 개선)
cleanup_on_exit() {
    echo ""
    echo -e "${YELLOW}🛑 시스템 종료 중...${NC}"

    # PID 파일에서 프로세스 종료
    if [ -f "$PID_DIR/token_limiter.pid" ]; then
        LIMITER_PID=$(cat $PID_DIR/token_limiter.pid)
        kill $LIMITER_PID 2>/dev/null || true
        rm -f $PID_DIR/token_limiter.pid
    fi

    if [ -f "$PID_DIR/vllm.pid" ]; then
        VLLM_PID=$(cat $PID_DIR/vllm.pid)
        kill $VLLM_PID 2>/dev/null || true
        rm -f $PID_DIR/vllm.pid
    fi

    cleanup_processes
    echo -e "${GREEN}✅ 시스템 종료 완료${NC}"
    exit 0
}

# 시그널 핸들러 등록 (POSIX 호환)
trap 'cleanup_on_exit' INT TERM

# 메인 실행 부분
main() {
    echo "시작 시간: $(date)"

    # 1. 기존 프로세스 정리
    cleanup_processes

    # 2. 시스템 환경 확인
    check_gpu
    check_python_env

    # 3. Redis 시작
    start_redis

    # 4. vLLM 서버 시작
    start_vllm

    # 5. Token Limiter 시작
    start_token_limiter

    # 6. 시스템 상태 확인
    check_system_status

    echo ""
    echo -e "${GREEN}🎉 한국어 Llama Token Limiter 시스템 시작 완료!${NC}"
    echo "=============================================="
    echo ""
    echo "📋 관리 명령어:"
    echo "  - 로그 확인: tail -f logs/token_limiter.log"
    echo "  - 시스템 종료: ./scripts/stop_korean_system.sh"
    echo "  - 상태 확인: curl http://localhost:8080/health"
    echo "  - 통계 조회: curl http://localhost:8080/stats/사용자1"
    echo ""
    echo "종료하려면 Ctrl+C를 누르세요."
    
    # 프로세스 모니터링
    while true; do
        sleep 30
        
        # 프로세스가 살아있는지 확인
        if [ -f "$PID_DIR/vllm.pid" ] && ! kill -0 $(cat $PID_DIR/vllm.pid) 2>/dev/null; then
            echo -e "${RED}❌ vLLM 서버가 종료되었습니다${NC}"
            break
        fi
        
        if [ -f "$PID_DIR/token_limiter.pid" ] && ! kill -0 $(cat $PID_DIR/token_limiter.pid) 2>/dev/null; then
            echo -e "${RED}❌ Token Limiter가 종료되었습니다${NC}"
            break
        fi
    done
}

# 스크립트 실행
main "$@"