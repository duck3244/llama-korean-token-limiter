#!/bin/bash
# 한국어 Llama 모델 vLLM 서버 시작 스크립트

set -e

echo "🇰🇷 한국어 Llama 모델 vLLM 서버 시작 중..."

# 환경 변수 설정
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

# GPU 메모리 상태 확인
echo "🔍 GPU 메모리 상태 확인:"
nvidia-smi --query-gpu=memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits

# GPU 메모리 정리
echo "🧹 GPU 메모리 정리 중..."
python -c "
import torch
if torch.cuda.is_available():
    torch.cuda.empty_cache()
    print('✅ CUDA cache cleared')
else:
    print('❌ CUDA not available')
"

# Python 가상환경 활성화 확인
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "⚠️ 가상환경이 활성화되지 않았습니다."
    if [ -d "venv" ]; then
        echo "🐍 가상환경 활성화 중..."
        source venv/bin/activate
    else
        echo "❌ 가상환경을 찾을 수 없습니다. setup.sh를 먼저 실행하세요."
        exit 1
    fi
fi

# HuggingFace 토큰 확인 (필요 시)
if [ ! -z "$HUGGINGFACE_TOKEN" ]; then
    echo "🔑 HuggingFace 토큰 설정됨"
else
    echo "⚠️ HuggingFace 토큰이 설정되지 않았습니다. 공개 모델이므로 계속 진행합니다."
fi

# 모델 다운로드 확인
echo "📦 모델 다운로드 상태 확인 중..."
python -c "
try:
    from transformers import AutoTokenizer
    tokenizer = AutoTokenizer.from_pretrained(
        'torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1',
        cache_dir='./tokenizer_cache'
    )
    print('✅ 한국어 모델 토크나이저 준비 완료')
    print(f'   어휘 크기: {len(tokenizer):,}')
except Exception as e:
    print(f'❌ 모델 다운로드 실패: {e}')
    print('📥 모델 다운로드를 시작합니다...')
    exit(1)
"

if [ $? -ne 0 ]; then
    echo "📥 모델 다운로드 중... (시간이 좀 걸릴 수 있습니다)"
    python -c "
from transformers import AutoTokenizer, AutoModelForCausalLM
print('토크나이저 다운로드 중...')
tokenizer = AutoTokenizer.from_pretrained(
    'torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1',
    cache_dir='./tokenizer_cache'
)
print('✅ 토크나이저 다운로드 완료')
"
fi

# vLLM 서버 시작 (RTX 4060 8GB 최적화 설정)
echo "🚀 vLLM 서버 시작 중..."
echo "📋 서버 설정:"
echo "   - 모델: torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1"
echo "   - GPU 메모리 사용률: 80%"
echo "   - 최대 컨텍스트 길이: 2048"
echo "   - 정밀도: FP16"
echo "   - 포트: 8000"

exec python -m vllm.entrypoints.openai.api_server \
    --model torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1 \
    --port 8000 \
    --host 0.0.0.0 \
    --gpu-memory-utilization 0.8 \
    --max-model-len 2048 \
    --dtype half \
    --tensor-parallel-size 1 \
    --enforce-eager \
    --trust-remote-code \
    --disable-log-requests \
    --served-model-name korean-llama \
    --chat-template "{% for message in messages %}{{ message.role }}: {{ message.content }}\n{% endfor %}assistant:" \
    --api-key sk-vllm-korean-server-key \
    2>&1 | tee logs/vllm_korean_server.log
