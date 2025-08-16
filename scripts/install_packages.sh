#!/bin/bash
# 한국어 Token Limiter 패키지 설치 스크립트

set -e

echo "🐍 Python 패키지 단계별 설치 시작"
echo "================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 가상환경 확인
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo -e "${RED}❌ 가상환경이 활성화되지 않았습니다${NC}"
    echo "다음 명령어로 가상환경을 활성화하세요:"
    echo "source venv/bin/activate"
    exit 1
fi

echo -e "${GREEN}✅ 가상환경 활성화됨: $VIRTUAL_ENV${NC}"

# GPU 사용 가능 여부 확인
if command -v nvidia-smi &> /dev/null; then
    GPU_AVAILABLE=true
    echo -e "${GREEN}🎮 GPU 감지됨${NC}"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | head -1
else
    GPU_AVAILABLE=false
    echo -e "${YELLOW}⚠️ GPU를 찾을 수 없습니다. CPU 모드로 설치합니다.${NC}"
fi

# 1단계: 기본 도구 업그레이드
echo -e "\n${BLUE}📦 1단계: 기본 도구 업그레이드${NC}"
pip install --upgrade pip wheel setuptools
echo -e "${GREEN}✅ 기본 도구 업그레이드 완료${NC}"

# 2단계: PyTorch 설치
echo -e "\n${BLUE}🔥 2단계: PyTorch 설치${NC}"
if [ "$GPU_AVAILABLE" = true ]; then
    echo "CUDA 버전용 PyTorch 설치 중..."
    pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cu121
else
    echo "CPU 버전 PyTorch 설치 중..."
    pip install torch==2.1.0 torchvision==0.16.0 torchaudio==2.1.0 --index-url https://download.pytorch.org/whl/cpu
fi

# PyTorch 설치 확인
python -c "import torch; print(f'✅ PyTorch {torch.__version__} 설치 완료')"
if [ "$GPU_AVAILABLE" = true ]; then
    python -c "import torch; print(f'🎮 CUDA 사용 가능: {torch.cuda.is_available()}')"
fi

# 3단계: vLLM 설치 (GPU가 있는 경우만)
if [ "$GPU_AVAILABLE" = true ]; then
    echo -e "\n${BLUE}🚀 3단계: vLLM 설치${NC}"
    pip install vllm==0.2.7
    echo -e "${GREEN}✅ vLLM 설치 완료${NC}"
else
    echo -e "\n${YELLOW}⚠️ 3단계: vLLM 건너뛰기 (GPU 없음)${NC}"
fi

# 4단계: Flash Attention 설치 (선택사항, GPU가 있는 경우만)
if [ "$GPU_AVAILABLE" = true ]; then
    echo -e "\n${BLUE}⚡ 4단계: Flash Attention 설치 (선택사항)${NC}"
    pip install flash-attn==2.3.4 --no-build-isolation || {
        echo -e "${YELLOW}⚠️ Flash Attention 설치 실패 (선택사항이므로 계속 진행)${NC}"
    }
    
    echo -e "\n${BLUE}🔧 xformers 설치 (선택사항)${NC}"
    pip install xformers==0.0.22.post7 || {
        echo -e "${YELLOW}⚠️ xformers 설치 실패 (선택사항이므로 계속 진행)${NC}"
    }
else
    echo -e "\n${YELLOW}⚠️ 4단계: Flash Attention 건너뛰기 (GPU 없음)${NC}"
fi

# 5단계: 기본 패키지 설치
echo -e "\n${BLUE}📚 5단계: 기본 패키지 설치${NC}"
pip install -r requirements.txt
echo -e "${GREEN}✅ 기본 패키지 설치 완료${NC}"

# 6단계: 한국어 처리 패키지 설치 (선택사항)
echo -e "\n${BLUE}🇰🇷 6단계: 한국어 처리 패키지 설치 (선택사항)${NC}"
read -p "한국어 형태소 분석 패키지(KoNLPy, MeCab)를 설치하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # MeCab 시스템 패키지 설치 확인
    if command -v mecab &> /dev/null; then
        pip install konlpy==0.6.0 mecab-python3==1.0.6
        echo -e "${GREEN}✅ 한국어 처리 패키지 설치 완료${NC}"
    else
        echo -e "${YELLOW}⚠️ MeCab이 시스템에 설치되지 않았습니다${NC}"
        echo "다음 명령어로 설치할 수 있습니다:"
        echo "sudo apt install mecab mecab-ko mecab-ko-dic"
        pip install konlpy==0.6.0 || echo "KoNLPy만 설치했습니다"
    fi
else
    echo "한국어 처리 패키지 설치를 건너뜁니다."
fi

# 7단계: 개발 도구 설치 (선택사항)
echo -e "\n${BLUE}🛠️ 7단계: 개발 도구 설치 (선택사항)${NC}"
read -p "개발 도구(Jupyter, pytest 등)를 설치하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    pip install jupyter==1.0.0 notebook==7.0.6 ipykernel
    echo -e "${GREEN}✅ 개발 도구 설치 완료${NC}"
else
    echo "개발 도구 설치를 건너뜁니다."
fi

# 8단계: GPU 모니터링 도구 설치 (GPU가 있는 경우만)
if [ "$GPU_AVAILABLE" = true ]; then
    echo -e "\n${BLUE}📊 8단계: GPU 모니터링 도구 설치${NC}"
    pip install nvidia-ml-py3==7.352.0 || {
        echo -e "${YELLOW}⚠️ GPU 모니터링 도구 설치 실패 (선택사항)${NC}"
    }
fi

# 9단계: 설치 확인 테스트
echo -e "\n${BLUE}🧪 9단계: 설치 확인 테스트${NC}"

# 기본 import 테스트
python -c "
import sys
print(f'Python: {sys.version}')

try:
    import torch
    print(f'✅ PyTorch: {torch.__version__}')
    if torch.cuda.is_available():
        print(f'🎮 CUDA: {torch.version.cuda}')
        print(f'🎮 GPU 개수: {torch.cuda.device_count()}')
    else:
        print('💻 CPU 모드')
except ImportError as e:
    print(f'❌ PyTorch import 실패: {e}')

try:
    import fastapi
    print(f'✅ FastAPI: {fastapi.__version__}')
except ImportError as e:
    print(f'❌ FastAPI import 실패: {e}')

try:
    import transformers
    print(f'✅ Transformers: {transformers.__version__}')
except ImportError as e:
    print(f'❌ Transformers import 실패: {e}')

try:
    import streamlit
    print(f'✅ Streamlit: {streamlit.__version__}')
except ImportError as e:
    print(f'❌ Streamlit import 실패: {e}')

try:
    import redis
    print(f'✅ Redis: {redis.__version__}')
except ImportError as e:
    print(f'❌ Redis import 실패: {e}')

if '$GPU_AVAILABLE' == 'true':
    try:
        import vllm
        print(f'✅ vLLM: {vllm.__version__}')
    except ImportError as e:
        print(f'❌ vLLM import 실패: {e}')
"

# 설치 완료 메시지
echo ""
echo "================================="
echo -e "${GREEN}🎉 패키지 설치 완료!${NC}"
echo "================================="
echo ""
echo -e "${BLUE}📋 다음 단계:${NC}"
echo "1. 한국어 모델 다운로드:"
echo "   python -c \"from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1', cache_dir='./tokenizer_cache')\""
echo ""
echo "2. Redis 시작:"
echo "   docker run -d --name korean-redis -p 6379:6379 redis:alpine"
echo ""
echo "3. 시스템 시작:"
echo "   ./scripts/start_korean_system.sh"
echo ""
echo "4. 테스트 실행:"
echo "   ./scripts/test_korean.sh"
echo ""

# 설치된 패키지 목록 저장
echo -e "${BLUE}📦 설치된 패키지 목록 저장 중...${NC}"
pip freeze > installed_packages.txt
echo -e "${GREEN}✅ installed_packages.txt에 저장됨${NC}"

echo -e "${GREEN}설치 완료 시간: $(date)${NC}"