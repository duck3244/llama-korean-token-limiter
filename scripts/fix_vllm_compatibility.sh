#!/bin/bash
# vLLM 호환성 문제 해결 스크립트

set -e

echo "🔧 vLLM 호환성 문제 해결 중..."
echo "================================"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📋 현재 상황:${NC}"
echo "vLLM 0.2.7이 요구하는 버전:"
echo "- pydantic==1.10.13 (현재: 2.5.0)"
echo "- torch==2.1.2 (현재: 2.1.0)" 
echo "- xformers==0.0.23.post1 (현재: 0.0.22.post7)"
echo ""

#!/bin/bash
# vLLM 호환성 문제 해결 스크립트

set -e

echo "🔧 vLLM 호환성 문제 해결 중..."
echo "================================"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📋 현재 상황:${NC}"
echo "vLLM 0.2.7이 요구하는 버전:"
echo "- pydantic==1.10.13 (현재: 2.5.0)"
echo "- torch==2.1.2 (현재: 2.1.0)"
echo "- xformers==0.0.23.post1 (현재: 0.0.22.post7)"
echo ""

echo "vLLM 호환 버전으로 다운그레이드하시겠습니까? (y/N):"
read REPLY
if [ "$REPLY" = "n" ] || [ "$REPLY" = "N" ]; then
    echo "다운그레이드를 취소했습니다."
    exit 0
fi

echo -e "${BLUE}🔄 vLLM 호환 버전으로 다운그레이드 중...${NC}"

# 1. 충돌하는 패키지 제거
echo "충돌 패키지 제거 중..."
pip uninstall -y pydantic pydantic-core pydantic-settings fastapi starlette

# 2. vLLM 호환 버전 설치
echo "vLLM 호환 버전 설치 중..."

# PyTorch 업그레이드
pip install torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cu121

# Pydantic v1 설치
pip install pydantic==1.10.13

# xformers 업그레이드
pip install xformers==0.0.23.post1

# FastAPI 호환 버전 설치
pip install fastapi==0.100.1 starlette==0.27.0

echo -e "${GREEN}✅ vLLM 호환 버전 설치 완료${NC}"

# 3. 설치 확인
echo -e "\n${BLUE}🧪 설치 확인 중...${NC}"

python -c "
import sys
print('🐍 Python:', sys.version)

try:
    import torch
    print(f'✅ PyTorch: {torch.__version__}')
    print(f'🎮 CUDA available: {torch.cuda.is_available()}')
except ImportError as e:
    print(f'❌ PyTorch: {e}')

try:
    import pydantic
    print(f'✅ Pydantic: {pydantic.VERSION}')
except ImportError as e:
    print(f'❌ Pydantic: {e}')

try:
    import vllm
    print(f'✅ vLLM: {vllm.__version__}')
except ImportError as e:
    print(f'❌ vLLM: {e}')

try:
    import fastapi
    print(f'✅ FastAPI: {fastapi.__version__}')
except ImportError as e:
    print(f'❌ FastAPI: {e}')

try:
    import xformers
    print(f'✅ xformers: {xformers.__version__}')
except ImportError as e:
    print(f'❌ xformers: {e}')
"

echo ""
echo -e "${GREEN}🎉 vLLM 호환성 문제 해결 완료!${NC}"
echo ""
echo -e "${BLUE}📝 주의사항:${NC}"
echo "- Pydantic v1을 사용하므로 일부 최신 기능이 제한될 수 있습니다"
echo "- FastAPI도 호환 버전으로 다운그레이드되었습니다"
echo ""
echo -e "${BLUE}🚀 다음 단계:${NC}"
echo "1. vLLM 서버 테스트: python -c 'import vllm; print(\"vLLM OK\")'"
echo "2. 시스템 시작: ./scripts/start_korean_system.sh"

echo -e "${BLUE}🔄 vLLM 호환 버전으로 다운그레이드 중...${NC}"

# 1. 충돌하는 패키지 제거
echo "충돌 패키지 제거 중..."
pip uninstall -y pydantic pydantic-core pydantic-settings fastapi starlette

# 2. vLLM 호환 버전 설치
echo "vLLM 호환 버전 설치 중..."

# PyTorch 업그레이드
pip install torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 --index-url https://download.pytorch.org/whl/cu121

# Pydantic v1 설치
pip install pydantic==1.10.13

# xformers 업그레이드  
pip install xformers==0.0.23.post1

# FastAPI 호환 버전 설치
pip install fastapi==0.100.1 starlette==0.27.0

echo -e "${GREEN}✅ vLLM 호환 버전 설치 완료${NC}"

# 3. 설치 확인
echo -e "\n${BLUE}🧪 설치 확인 중...${NC}"

python -c "
import sys
print('🐍 Python:', sys.version)

try:
    import torch
    print(f'✅ PyTorch: {torch.__version__}')
    print(f'🎮 CUDA available: {torch.cuda.is_available()}')
except ImportError as e:
    print(f'❌ PyTorch: {e}')

try:
    import pydantic
    print(f'✅ Pydantic: {pydantic.VERSION}')
except ImportError as e:
    print(f'❌ Pydantic: {e}')

try:
    import vllm
    print(f'✅ vLLM: {vllm.__version__}')
except ImportError as e:
    print(f'❌ vLLM: {e}')

try:
    import fastapi
    print(f'✅ FastAPI: {fastapi.__version__}')
except ImportError as e:
    print(f'❌ FastAPI: {e}')

try:
    import xformers
    print(f'✅ xformers: {xformers.__version__}')
except ImportError as e:
    print(f'❌ xformers: {e}')
"

echo ""
echo -e "${GREEN}🎉 vLLM 호환성 문제 해결 완료!${NC}"
echo ""
echo -e "${BLUE}📝 주의사항:${NC}"
echo "- Pydantic v1을 사용하므로 일부 최신 기능이 제한될 수 있습니다"
echo "- FastAPI도 호환 버전으로 다운그레이드되었습니다"
echo ""
echo -e "${BLUE}🚀 다음 단계:${NC}"
echo "1. vLLM 서버 테스트: python -c 'import vllm; print(\"vLLM OK\")'"
echo "2. 시스템 시작: ./scripts/start_korean_system.sh"