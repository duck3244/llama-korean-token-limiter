#!/bin/bash
# 기존 Conda 환경에서 Korean Token Limiter 패키지 설치

set -e

echo "🐍 기존 Conda 환경에서 Korean Token Limiter 설치"
echo "============================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Conda 환경 확인 (더 유연한 방식)
check_conda_env() {
    echo -e "${BLUE}🔍 현재 환경 확인 중...${NC}"

    # Python 경로 확인
    PYTHON_PATH=$(which python)
    echo "Python 경로: $PYTHON_PATH"

    # Python 버전 확인
    PYTHON_VERSION=$(python --version 2>&1)
    echo "Python 버전: $PYTHON_VERSION"

    # Conda 환경인지 확인 (여러 방법으로)
    if [[ "$PYTHON_PATH" == *"miniconda"* ]] || [[ "$PYTHON_PATH" == *"anaconda"* ]] || [[ "$PYTHON_PATH" == *"conda"* ]]; then
        IS_CONDA=true
        echo -e "${GREEN}✅ Conda 환경 감지됨${NC}"

        # 환경 이름 추출
        if [[ ! -z "$CONDA_DEFAULT_ENV" ]]; then
            ENV_NAME="$CONDA_DEFAULT_ENV"
        elif [[ ! -z "$CONDA_PREFIX" ]]; then
            ENV_NAME=$(basename "$CONDA_PREFIX")
        else
            ENV_NAME="Unknown"
        fi
        echo "환경 이름: $ENV_NAME"

    elif [[ ! -z "$VIRTUAL_ENV" ]]; then
        IS_CONDA=false
        echo -e "${GREEN}✅ Python venv 환경 감지됨${NC}"
        echo "환경 경로: $VIRTUAL_ENV"

    else
        echo -e "${YELLOW}⚠️ 가상환경 타입을 확실히 알 수 없습니다${NC}"
        echo "현재 Python을 사용하여 계속 진행합니다."
        IS_CONDA=false
    fi

    # pip 확인
    if command -v pip &> /dev/null; then
        PIP_PATH=$(which pip)
        echo "pip 경로: $PIP_PATH"
        echo -e "${GREEN}✅ pip 사용 가능${NC}"
    else
        echo -e "${RED}❌ pip을 찾을 수 없습니다${NC}"
        exit 1
    fi
}

# GPU 확인
check_gpu() {
    echo -e "\n${BLUE}🎮 GPU 확인 중...${NC}"

    if command -v nvidia-smi &> /dev/null; then
        GPU_AVAILABLE=true
        echo -e "${GREEN}✅ NVIDIA GPU 감지됨${NC}"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1

        # CUDA 버전 확인
        if command -v nvcc &> /dev/null; then
            CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
            echo "CUDA 버전: $CUDA_VERSION"
        else
            echo "CUDA 컴파일러를 찾을 수 없습니다 (Runtime만 있을 수 있음)"
        fi
    else
        GPU_AVAILABLE=false
        echo -e "${YELLOW}⚠️ GPU를 찾을 수 없습니다. CPU 모드로 진행합니다.${NC}"
    fi
}

# 기본 도구 업그레이드
upgrade_basic_tools() {
    echo -e "\n${BLUE}📦 기본 도구 업그레이드${NC}"

    pip install --upgrade pip wheel setuptools

    echo -e "${GREEN}✅ 기본 도구 업그레이드 완료${NC}"
}

# PyTorch 설치
install_pytorch() {
    echo -e "\n${BLUE}🔥 PyTorch 설치${NC}"

    # 기존 PyTorch 확인
    if python -c "import torch" 2>/dev/null; then
        EXISTING_TORCH=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
        echo "기존 PyTorch 버전: $EXISTING_TORCH"

        read -p "기존 PyTorch를 유지하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "기존 PyTorch를 유지합니다."
            return 0
        fi
    fi

    if [ "$GPU_AVAILABLE" = true ]; then
        echo "CUDA 버전 PyTorch 설치 중..."
        pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu121
    else
        echo "CPU 버전 PyTorch 설치 중..."
        pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cpu
    fi

    # 설치 확인
    python -c "
import torch
print(f'✅ PyTorch {torch.__version__} 설치 완료')
if torch.cuda.is_available():
    print(f'🎮 CUDA 사용 가능: {torch.cuda.get_device_name()}')
    print(f'🎮 CUDA 버전: {torch.version.cuda}')
else:
    print('💻 CPU 모드로 실행됩니다')
"
}

# vLLM 및 GPU 패키지 설치
install_gpu_packages() {
    if [ "$GPU_AVAILABLE" = true ]; then
        echo -e "\n${BLUE}🚀 GPU 패키지 설치${NC}"

        # vLLM 설치
        echo "vLLM 설치 중..."
        pip install vllm==0.2.7

        # Flash Attention 설치 (선택사항)
        echo "Flash Attention 설치 시도 중..."
        pip install flash-attn==2.3.4 --no-build-isolation || {
            echo -e "${YELLOW}⚠️ Flash Attention 설치 실패 (선택사항이므로 계속 진행)${NC}"
        }

        # xformers 설치 (선택사항)
        echo "xformers 설치 시도 중..."
        pip install xformers==0.0.22.post7 || {
            echo -e "${YELLOW}⚠️ xformers 설치 실패 (선택사항이므로 계속 진행)${NC}"
        }

        echo -e "${GREEN}✅ GPU 패키지 설치 완료${NC}"
    else
        echo -e "\n${YELLOW}⚠️ GPU 패키지 설치 건너뛰기 (GPU 없음)${NC}"
    fi
}

# 애플리케이션 패키지 설치
install_app_packages() {
    echo -e "\n${BLUE}📚 애플리케이션 패키지 설치${NC}"

    # requirements.txt가 있는지 확인
    if [ ! -f "requirements.txt" ]; then
        echo -e "${RED}❌ requirements.txt 파일을 찾을 수 없습니다${NC}"
        echo "현재 디렉토리: $(pwd)"
        echo "파일 목록:"
        ls -la
        exit 1
    fi

    echo "requirements.txt에서 패키지 설치 중..."
    pip install -r requirements.txt

    echo -e "${GREEN}✅ 애플리케이션 패키지 설치 완료${NC}"
}

# 한국어 패키지 설치 (선택사항)
install_korean_packages() {
    echo -e "\n${BLUE}🇰🇷 한국어 처리 패키지 설치 (선택사항)${NC}"

    read -p "한국어 형태소 분석 패키지(KoNLPy)를 설치하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then

        # Java 확인
        if ! command -v java &> /dev/null; then
            echo -e "${YELLOW}⚠️ Java가 필요합니다.${NC}"
            echo "설치 방법:"
            echo "  Ubuntu: sudo apt install default-jdk"
            echo "  macOS: brew install openjdk"
            echo "  Conda: conda install openjdk"

            if [ "$IS_CONDA" = true ]; then
                read -p "Conda로 Java를 설치하시겠습니까? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    # Conda 명령어 찾기
                    if command -v conda &> /dev/null; then
                        conda install -y openjdk
                    elif [ -f "/home/duck/miniconda3/bin/conda" ]; then
                        /home/duck/miniconda3/bin/conda install -y openjdk
                    elif [ -f "/home/duck/miniconda3/condabin/conda" ]; then
                        /home/duck/miniconda3/condabin/conda install -y openjdk
                    else
                        echo -e "${YELLOW}⚠️ conda 명령어를 찾을 수 없습니다. 수동으로 Java를 설치하세요.${NC}"
                    fi
                fi
            fi
        fi

        # KoNLPy 설치
        pip install konlpy==0.6.0

        # MeCab 설치 시도
        echo "MeCab 설치 시도 중..."
        pip install mecab-python3==1.0.6 || {
            echo -e "${YELLOW}⚠️ MeCab 설치 실패${NC}"
            echo "MeCab 시스템 패키지가 필요합니다:"
            echo "  Ubuntu: sudo apt install mecab mecab-ko mecab-ko-dic"
            echo "  macOS: brew install mecab mecab-ko mecab-ko-dic"
        }

        echo -e "${GREEN}✅ 한국어 패키지 설치 시도 완료${NC}"
    fi
}

# 개발 도구 설치 (선택사항)
install_dev_tools() {
    echo -e "\n${BLUE}🛠️ 개발 도구 설치 (선택사항)${NC}"

    read -p "개발 도구(Jupyter, pytest 등)를 설치하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then

        # Jupyter 설치
        if [ "$IS_CONDA" = true ]; then
            echo "Conda를 통한 Jupyter 설치 시도 중..."
            # Conda 명령어 찾기 및 실행
            if command -v conda &> /dev/null; then
                conda install -y jupyter notebook ipykernel || pip install jupyter notebook ipykernel
            elif [ -f "/home/duck/miniconda3/bin/conda" ]; then
                /home/duck/miniconda3/bin/conda install -y jupyter notebook ipykernel || pip install jupyter notebook ipykernel
            else
                pip install jupyter notebook ipykernel
            fi
        else
            pip install jupyter notebook ipykernel
        fi

        # 추가 개발 도구
        pip install black flake8 pytest pytest-asyncio

        echo -e "${GREEN}✅ 개발 도구 설치 완료${NC}"
    fi
}

# 설치 검증
verify_installation() {
    echo -e "\n${BLUE}🧪 설치 검증${NC}"

    python -c "
import sys
print(f'🐍 Python: {sys.version}')
print(f'📍 Python 경로: {sys.executable}')

# 환경 정보
import os
if 'CONDA_DEFAULT_ENV' in os.environ:
    print(f'🌍 Conda 환경: {os.environ[\"CONDA_DEFAULT_ENV\"]}')
elif 'VIRTUAL_ENV' in os.environ:
    print(f'🌍 venv 환경: {os.environ[\"VIRTUAL_ENV\"]}')

# 필수 패키지 확인
packages = [
    ('torch', 'PyTorch'),
    ('transformers', 'Transformers'),
    ('fastapi', 'FastAPI'),
    ('streamlit', 'Streamlit'),
    ('redis', 'Redis'),
    ('pandas', 'Pandas'),
    ('numpy', 'NumPy'),
    ('yaml', 'PyYAML'),
    ('pydantic', 'Pydantic')
]

print('\n📦 패키지 확인:')
for pkg, name in packages:
    try:
        if pkg == 'yaml':
            import yaml as module
        else:
            module = __import__(pkg)
        version = getattr(module, '__version__', 'Unknown')
        print(f'✅ {name}: {version}')
    except ImportError:
        print(f'❌ {name}: Not installed')

# GPU 및 vLLM 확인
print('\n🎮 GPU 및 특수 패키지:')
try:
    import torch
    if torch.cuda.is_available():
        print(f'✅ CUDA: {torch.version.cuda}')
        print(f'✅ GPU: {torch.cuda.get_device_name()}')
        gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
        print(f'✅ GPU 메모리: {gpu_memory:.1f}GB')
    else:
        print('💻 CPU 모드')
except Exception as e:
    print(f'❌ GPU 확인 실패: {e}')

try:
    import vllm
    print(f'✅ vLLM: {vllm.__version__}')
except ImportError:
    print('❌ vLLM: Not installed (GPU 없음 또는 설치 실패)')

try:
    import flash_attn
    print(f'✅ Flash Attention: Available')
except ImportError:
    print('❌ Flash Attention: Not installed (선택사항)')
"
}

# 사용 안내
show_completion_info() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}🎉 패키지 설치 완료!${NC}"
    echo "=============================================="
    echo ""
    echo -e "${BLUE}📋 현재 환경 정보:${NC}"
    echo "Python: $(python --version)"
    echo "Python 경로: $(which python)"
    echo "pip 경로: $(which pip)"

    if [[ ! -z "$CONDA_DEFAULT_ENV" ]]; then
        echo "Conda 환경: $CONDA_DEFAULT_ENV"
    elif [[ ! -z "$VIRTUAL_ENV" ]]; then
        echo "venv 환경: $VIRTUAL_ENV"
    fi

    echo ""
    echo -e "${BLUE}🚀 다음 단계:${NC}"
    echo "1. 한국어 모델 다운로드:"
    echo "   python -c \"from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1', cache_dir='./tokenizer_cache')\""
    echo ""
    echo "2. Redis 시작:"
    echo "   docker run -d --name korean-redis -p 6379:6379 redis:alpine"
    echo ""
    echo "3. 설정 파일 확인:"
    echo "   ls config/korean_*.yaml"
    echo ""
    echo "4. 시스템 시작:"
    echo "   ./scripts/start_korean_system.sh"
    echo ""
    echo "5. 테스트 실행:"
    echo "   ./scripts/test_korean.sh"
    echo ""
    echo -e "${BLUE}💡 문제 해결:${NC}"
    echo "- 로그 확인: tail -f logs/token_limiter.log"
    echo "- GPU 상태: nvidia-smi"
    echo "- 패키지 확인: pip list | grep -E '(torch|vllm|transformers)'"
    echo ""

    # 설치된 패키지 목록 저장
    echo "설치된 패키지 목록 저장 중..."
    pip freeze > installed_packages_$(date +%Y%m%d_%H%M%S).txt
    echo -e "${GREEN}✅ 패키지 목록이 저장되었습니다${NC}"

    echo "설치 완료 시간: $(date)"
}

# 메인 실행 함수
main() {
    echo "시작 시간: $(date)"
    echo ""

    check_conda_env
    check_gpu
    upgrade_basic_tools
    install_pytorch
    install_gpu_packages
    install_app_packages
    install_korean_packages
    install_dev_tools
    verify_installation
    show_completion_info
}

# 도움말
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "기존 Conda 환경용 Korean Token Limiter 설치 스크립트"
    echo ""
    echo "사용법:"
    echo "  $0              # 현재 환경에 설치"
    echo "  $0 --help       # 이 도움말 표시"
    echo ""
    echo "주의사항:"
    echo "  - 이미 활성화된 Conda 또는 Python 환경에서 실행하세요"
    echo "  - GPU가 있는 경우 CUDA 12.1+ 권장"
    echo "  - requirements.txt 파일이 현재 디렉토리에 있어야 합니다"
    echo ""
    exit 0
fi

# 메인 실행
main "$@"