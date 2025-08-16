#!/bin/bash
# RTX 4060 최적화된 vLLM 서버 시작 스크립트

echo "🚀 RTX 4060 최적화 vLLM 서버 시작 중..."

# 환경 변수 설정
export CUDA_VISIBLE_DEVICES=0
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256

# GPU 메모리 정리
python -c "
import torch
if torch.cuda.is_available():
    torch.cuda.empty_cache()
    print('✅ GPU 메모리 정리 완료')
"

# 작은 모델로 vLLM 서버 시작 (검증된 설정)
exec python -m vllm.entrypoints.openai.api_server \
    --model "distilgpt2" \
    --port 8000 \
    --host 0.0.0.0 \
    --gpu-memory-utilization 0.4 \
    --max-model-len 256 \
    --dtype half \
    --enforce-eager \
    --trust-remote-code \
    --served-model-name korean-llama \
    --disable-log-requests