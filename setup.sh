#!/bin/bash
# 한국어 Llama Token Limiter 설치 스크립트

set -e

echo "🇰🇷 한국어 Llama Token Limiter 설치 시작"
echo "=============================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 시스템 정보 감지
detect_system() {
    echo -e "${BLUE}🔍 시스템 정보 감지 중...${NC}"

    # OS 감지
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
            VERSION=$VERSION_ID
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        DISTRO="macos"
    else
        echo -e "${RED}❌ 지원하지 않는 운영체제입니다: $OSTYPE${NC}"
        exit 1
    fi

    echo "OS: $OS"
    echo "배포판: $DISTRO"

    # Python 버전 확인
    if command -v python3.11 &> /dev/null; then
        PYTHON_CMD="python3.11"
    elif command -v python3.10 &> /dev/null; then
        PYTHON_CMD="python3.10"
    elif command -v python3.9 &> /dev/null; then
        PYTHON_CMD="python3.9"
    elif command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    else
        echo -e "${RED}❌ Python 3.9+ 가 필요합니다${NC}"
        exit 1
    fi

    PYTHON_VERSION=$($PYTHON_CMD --version | cut -d' ' -f2)
    echo "Python: $PYTHON_VERSION"

    # GPU 확인
    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE=true
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1)
        echo "GPU: $GPU_INFO"
    else
        GPU_AVAILABLE=false
        echo -e "${YELLOW}⚠️ NVIDIA GPU를 찾을 수 없습니다${NC}"
    fi
}

# 시스템 의존성 설치
install_system_dependencies() {
    echo -e "\n${BLUE}📦 시스템 의존성 설치 중...${NC}"

    case $DISTRO in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y \
                python3-pip python3-venv python3-dev \
                build-essential curl git wget \
                software-properties-common \
                pkg-config libffi-dev \
                redis-tools

            # Docker 설치 (선택사항)
            if ! command -v docker &> /dev/null; then
                echo "Docker 설치 중..."
                curl -fsSL https://get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                sudo usermod -aG docker $USER
                rm get-docker.sh
                echo -e "${GREEN}✅ Docker 설치 완료${NC}"
            fi
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                sudo dnf install -y python3-pip python3-devel gcc curl git wget redis
            else
                sudo yum install -y python3-pip python3-devel gcc curl git wget redis
            fi
            ;;
        macos)
            if ! command -v brew &> /dev/null; then
                echo "Homebrew 설치 중..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install python redis git
            ;;
        *)
            echo -e "${YELLOW}⚠️ 알 수 없는 배포판입니다. 수동으로 의존성을 설치해주세요.${NC}"
            ;;
    esac

    echo -e "${GREEN}✅ 시스템 의존성 설치 완료${NC}"
}

# NVIDIA 드라이버 및 CUDA 설치 확인
check_nvidia_cuda() {
    if [ "$GPU_AVAILABLE" = true ]; then
        echo -e "\n${BLUE}🎮 NVIDIA/CUDA 환경 확인 중...${NC}"

        # NVIDIA 드라이버 확인
        nvidia_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        echo "NVIDIA 드라이버: $nvidia_version"

        # CUDA 확인
        if command -v nvcc &> /dev/null; then
            cuda_version=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
            echo "CUDA: $cuda_version"
        else
            echo -e "${YELLOW}⚠️ CUDA Toolkit이 설치되지 않았습니다${NC}"
            echo "vLLM 설치를 위해 CUDA 12.1+ 권장"

            read -p "CUDA Toolkit을 설치하시겠습니까? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_cuda
            fi
        fi
    fi
}

# CUDA 설치 함수
install_cuda() {
    echo -e "${BLUE}🔧 CUDA Toolkit 설치 중...${NC}"

    case $DISTRO in
        ubuntu)
            # Ubuntu 22.04 기준 CUDA 12.1 설치
            wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
            sudo dpkg -i cuda-keyring_1.0-1_all.deb
            sudo apt-get update
            sudo apt-get -y install cuda-toolkit-12-1
            rm cuda-keyring_1.0-1_all.deb

            # 환경변수 설정
            echo 'export PATH=/usr/local/cuda-12.1/bin:$PATH' >> ~/.bashrc
            echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.1/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
            ;;
        *)
            echo -e "${YELLOW}⚠️ 자동 CUDA 설치는 Ubuntu만 지원합니다${NC}"
            echo "수동으로 CUDA를 설치해주세요: https://developer.nvidia.com/cuda-downloads"
            ;;
    esac
}

# Python 가상환경 설정
setup_python_env() {
    echo -e "\n${BLUE}🐍 Python 가상환경 설정 중...${NC}"

    # 기존 가상환경 백업
    if [ -d "venv" ]; then
        echo "기존 가상환경 백업 중..."
        mv venv venv_backup_$(date +%Y%m%d_%H%M%S)
    fi

    # 새 가상환경 생성
    $PYTHON_CMD -m venv venv
    source venv/bin/activate

    # pip 업그레이드
    pip install --upgrade pip wheel setuptools

    echo -e "${GREEN}✅ Python 가상환경 설정 완료${NC}"
}

# Python 패키지 설치
install_python_packages() {
    echo -e "\n${BLUE}📚 Python 패키지 설치 중...${NC}"

    # 가상환경이 활성화되었는지 확인
    if [[ "$VIRTUAL_ENV" == "" ]]; then
        source venv/bin/activate
    fi

    # GPU 사용 가능 여부에 따른 PyTorch 설치
    if [ "$GPU_AVAILABLE" = true ]; then
        echo "GPU용 PyTorch 설치 중..."
        pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu121
    else
        echo "CPU용 PyTorch 설치 중..."
        pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cpu
    fi

    # vLLM 설치 (GPU가 있는 경우에만)
    if [ "$GPU_AVAILABLE" = true ]; then
        echo "vLLM 설치 중..."
        pip install vllm==0.2.7

        # Flash Attention 설치 (선택사항)
        echo "Flash Attention 설치 중..."
        pip install flash-attn==2.3.4 --no-build-isolation || echo "⚠️ Flash Attention 설치 실패 (선택사항)"

        # xformers 설치
        pip install xformers==0.0.22.post7 || echo "⚠️ xformers 설치 실패 (선택사항)"
    else
        echo -e "${YELLOW}⚠️ GPU가 없어 vLLM을 건너뜁니다${NC}"
    fi

    # 나머지 패키지 설치
    echo "기본 패키지 설치 중..."
    pip install -r requirements.txt

    echo -e "${GREEN}✅ Python 패키지 설치 완료${NC}"
}

# 한국어 언어 모델 다운로드
download_korean_model() {
    echo -e "\n${BLUE}🇰🇷 한국어 모델 다운로드 중...${NC}"

    if [[ "$VIRTUAL_ENV" == "" ]]; then
        source venv/bin/activate
    fi

    python3 -c "
try:
    from transformers import AutoTokenizer
    print('한국어 모델 다운로드 시작...')
    tokenizer = AutoTokenizer.from_pretrained(
        'torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1',
        cache_dir='./tokenizer_cache',
        trust_remote_code=True
    )
    print(f'✅ 토크나이저 다운로드 완료 (어휘 크기: {len(tokenizer):,})')

    # 토큰 테스트
    test_text = '안녕하세요! 한국어 토큰 테스트입니다.'
    tokens = tokenizer.encode(test_text)
    print(f'테스트 토큰 수: {len(tokens)}개')
    print('✅ 한국어 토큰화 테스트 성공')

except Exception as e:
    print(f'❌ 모델 다운로드 실패: {e}')
    exit(1)
"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 한국어 모델 다운로드 완료${NC}"
    else
        echo -e "${RED}❌ 한국어 모델 다운로드 실패${NC}"
        exit 1
    fi
}

# 프로젝트 구조 설정
setup_project_structure() {
    echo -e "\n${BLUE}📁 프로젝트 구조 설정 중...${NC}"

    # 필요한 디렉토리 생성
    mkdir -p {src/{core,storage,proxy,utils},config,dashboard,logs,tests,pids,tokenizer_cache,backups}

    # 로그 디렉토리 권한 설정
    chmod 755 logs

    # 설정 파일 검증
    if [ ! -f "config/korean_model.yaml" ]; then
        echo -e "${RED}❌ config/korean_model.yaml 파일이 없습니다${NC}"
        exit 1
    fi

    if [ ! -f "config/korean_users.yaml" ]; then
        echo -e "${RED}❌ config/korean_users.yaml 파일이 없습니다${NC}"
        exit 1
    fi

    # 스크립트 실행 권한 설정
    chmod +x scripts/*.sh 2>/dev/null || true

    # __init__.py 파일 생성
    touch src/__init__.py
    touch src/core/__init__.py
    touch src/storage/__init__.py

    echo -e "${GREEN}✅ 프로젝트 구조 설정 완료${NC}"
}

# 환경 설정 파일 생성
create_env_file() {
    echo -e "\n${BLUE}⚙️ 환경 설정 파일 생성 중...${NC}"

    if [ ! -f ".env" ]; then
        cat > .env << EOF
# 한국어 Llama Token Limiter 환경 설정

# 서버 설정
SERVER_HOST=0.0.0.0
SERVER_PORT=8080
DEBUG=false

# LLM 서버 설정
LLM_SERVER_URL=http://localhost:8000
MODEL_NAME=torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1

# 저장소 설정
STORAGE_TYPE=redis
REDIS_URL=redis://localhost:6379
SQLITE_PATH=korean_usage.db

# 기본 제한 설정 (한국어 모델 특화)
DEFAULT_RPM=30
DEFAULT_TPM=5000
DEFAULT_TPH=300000
DEFAULT_DAILY=500000
DEFAULT_COOLDOWN=3

# 토큰 설정
KOREAN_FACTOR=1.2
MAX_MODEL_LEN=2048
TOKENIZER_CACHE_DIR=./tokenizer_cache

# GPU 설정 (RTX 4060 8GB 최적화)
GPU_MEMORY_UTILIZATION=0.8
TENSOR_PARALLEL_SIZE=1
DTYPE=half
ENFORCE_EAGER=true

# 로깅 설정
LOG_LEVEL=INFO
LOG_FILE=logs/korean_token_limiter.log

# HuggingFace 설정 (선택사항)
# HUGGINGFACE_TOKEN=your_token_here

# 개발 모드 설정
DEVELOPMENT_MODE=true
ENABLE_CORS=true
EOF
        echo -e "${GREEN}✅ .env 파일 생성 완료${NC}"
    else
        echo -e "${YELLOW}⚠️ .env 파일이 이미 존재합니다${NC}"
    fi
}

# Redis 서비스 확인 및 시작
setup_redis() {
    echo -e "\n${BLUE}🔴 Redis 설정 중...${NC}"

    # Redis가 이미 실행 중인지 확인
    if redis-cli ping >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Redis가 이미 실행 중입니다${NC}"
        return 0
    fi

    # Docker로 Redis 실행
    if command -v docker &> /dev/null; then
        echo "Docker를 사용하여 Redis 시작..."

        # 기존 컨테이너 정리
        docker rm -f korean-redis 2>/dev/null || true

        # Redis 컨테이너 시작
        docker run -d \
            --name korean-redis \
            -p 6379:6379 \
            --restart unless-stopped \
            redis:alpine \
            redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru

        # 연결 확인
        echo "Redis 연결 대기 중..."
        for i in {1..30}; do
            if redis-cli ping >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Redis 연결 확인됨${NC}"
                return 0
            fi
            sleep 1
        done

        echo -e "${RED}❌ Redis 연결 실패${NC}"
        return 1
    else
        echo -e "${YELLOW}⚠️ Docker가 없어서 Redis를 시작할 수 없습니다${NC}"
        echo "수동으로 Redis를 설치하고 시작해주세요"
        return 1
    fi
}

# 테스트 실행
run_tests() {
    echo -e "\n${BLUE}🧪 기본 테스트 실행 중...${NC}"

    if [[ "$VIRTUAL_ENV" == "" ]]; then
        source venv/bin/activate
    fi

    # 기본 모듈 import 테스트
    python3 -c "
import sys
sys.path.append('.')

try:
    from src.core.korean_token_counter import KoreanTokenCounter
    from src.core.config import Config
    print('✅ 핵심 모듈 import 성공')

    # 토큰 카운터 테스트
    counter = KoreanTokenCounter()
    test_text = '안녕하세요! 한국어 토큰 테스트입니다.'
    token_count = counter.count_tokens(test_text)
    print(f'✅ 토큰 계산 테스트 성공: {token_count}개')

    # 설정 테스트
    config = Config()
    print(f'✅ 설정 로드 성공: {config.model_name}')

except Exception as e:
    print(f'❌ 테스트 실패: {e}')
    sys.exit(1)
"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 기본 테스트 통과${NC}"
    else
        echo -e "${RED}❌ 기본 테스트 실패${NC}"
        exit 1
    fi
}

# 설치 완료 안내
show_completion_info() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}🎉 한국어 Llama Token Limiter 설치 완료!${NC}"
    echo "=============================================="
    echo ""
    echo "📋 다음 단계:"
    echo ""
    echo -e "${BLUE}1. 환경 변수 로드:${NC}"
    echo "   source venv/bin/activate"
    echo "   source .env"
    echo ""
    echo -e "${BLUE}2. 시스템 시작:${NC}"
    echo "   ./scripts/start_korean_system.sh"
    echo ""
    echo -e "${BLUE}3. 테스트 실행:${NC}"
    echo "   ./scripts/test_korean.sh"
    echo ""
    echo -e "${BLUE}4. 웹 인터페이스 접속:${NC}"
    echo "   🔗 Token Limiter: http://localhost:8080/health"
    echo "   🔗 vLLM API: http://localhost:8000/v1/models"
    echo ""
    echo -e "${BLUE}5. 예제 요청:${NC}"
    echo "   curl -X POST http://localhost:8080/v1/chat/completions \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -H 'Authorization: Bearer sk-user1-korean-key-def' \\"
    echo "     -d '{"
    echo "       \"model\": \"korean-llama\","
    echo "       \"messages\": [{"
    echo "         \"role\": \"user\","
    echo "         \"content\": \"안녕하세요! 한국어로 간단한 인사를 해주세요.\""
    echo "       }],"
    echo "       \"max_tokens\": 100"
    echo "     }'"
    echo ""
    echo -e "${BLUE}📚 도움말:${NC}"
    echo "   ./scripts/start_korean_system.sh --help"
    echo "   ./scripts/stop_korean_system.sh --help"
    echo ""
    echo -e "${BLUE}🔧 문제 해결:${NC}"
    echo "   - 로그 확인: tail -f logs/token_limiter.log"
    echo "   - GPU 상태: nvidia-smi"
    echo "   - Redis 상태: redis-cli ping"
    echo ""

    if [ "$GPU_AVAILABLE" = true ]; then
        echo -e "${GREEN}🎮 GPU 환경이 감지되었습니다!${NC}"
        echo "   vLLM으로 고성능 추론이 가능합니다."
    else
        echo -e "${YELLOW}⚠️ GPU가 감지되지 않았습니다.${NC}"
        echo "   CPU 모드로 실행되며 성능이 제한될 수 있습니다."
    fi

    echo ""
    echo "설치 완료 시간: $(date)"
}

# 메인 설치 함수
main_install() {
    echo "설치 시작 시간: $(date)"
    echo ""

    # 단계별 설치 실행
    detect_system
    install_system_dependencies

    if [ "$GPU_AVAILABLE" = true ]; then
        check_nvidia_cuda
    fi

    setup_python_env
    install_python_packages
    download_korean_model
    setup_project_structure
    create_env_file
    setup_redis
    run_tests
    show_completion_info
}

# 도움말 표시
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "한국어 Llama Token Limiter 설치 스크립트"
    echo ""
    echo "사용법:"
    echo "  $0              # 전체 설치"
    echo "  $0 --gpu-only   # GPU 관련 구성요소만 설치"
    echo "  $0 --cpu-only   # CPU 전용 설치"
    echo "  $0 --help       # 이 도움말 표시"
    echo ""
    echo "옵션:"
    echo "  --gpu-only      GPU 및 vLLM 관련 패키지만 설치"
    echo "  --cpu-only      CPU 전용으로 설치 (vLLM 제외)"
    echo "  --skip-model    모델 다운로드 건너뛰기"
    echo "  --help, -h      이 도움말 표시"
    echo ""
    echo "요구사항:"
    echo "  - Python 3.9+"
    echo "  - NVIDIA GPU (선택사항, 고성능을 위해 권장)"
    echo "  - CUDA 12.1+ (GPU 사용 시)"
    echo "  - Docker (Redis용, 선택사항)"
    echo "  - 8GB+ RAM (16GB 권장)"
    echo "  - 10GB+ 디스크 공간"
    echo ""
    exit 0
fi

# CPU 전용 설치 옵션
if [ "$1" = "--cpu-only" ]; then
    echo -e "${YELLOW}⚠️ CPU 전용 설치 모드${NC}"
    GPU_AVAILABLE=false
fi

# GPU 전용 설치 옵션
if [ "$1" = "--gpu-only" ]; then
    echo -e "${BLUE}🎮 GPU 전용 설치 모드${NC}"
    # GPU 관련 패키지만 설치하는 별도 로직 필요
fi

# 모델 다운로드 건너뛰기 옵션
if [ "$2" = "--skip-model" ] || [ "$1" = "--skip-model" ]; then
    SKIP_MODEL_DOWNLOAD=true
fi

# 루트 권한 확인
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ 루트 권한으로 실행하지 마세요${NC}"
    echo "일반 사용자 계정으로 실행해주세요"
    exit 1
fi

# 종료 시그널 처리
cleanup_on_exit() {
    echo -e "\n${YELLOW}🛑 설치 중단됨${NC}"
    exit 1
}

# 시그널 핸들러 등록
trap cleanup_on_exit SIGINT SIGTERM

# 메인 실행
main_install