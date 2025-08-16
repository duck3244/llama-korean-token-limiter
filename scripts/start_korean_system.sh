#!/bin/bash
# 한국어 Llama Token Limiter 시스템 시작 (작동 검증된 버전)

set -e

echo "🇰🇷 한국어 Llama Token Limiter 시스템 시작"
echo "=============================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 디렉토리 생성
mkdir -p logs pids

# 프로세스 정리
cleanup_processes() {
    echo -e "${YELLOW}🧹 기존 프로세스 정리...${NC}"
    pkill -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true
    pkill -f "main.py\|main_korean.py" 2>/dev/null || true
    rm -f pids/*.pid 2>/dev/null || true
    sleep 2
    echo -e "${GREEN}✅ 정리 완료${NC}"
}

# GPU 확인
check_gpu() {
    echo -e "${BLUE}🔍 GPU 확인...${NC}"
    if nvidia-smi >/dev/null 2>&1; then
        echo "✅ GPU 사용 가능"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
        return 0
    else
        echo -e "${YELLOW}⚠️ GPU 없음. CPU 모드로 진행${NC}"
        return 1
    fi
}

# Redis 시작
start_redis() {
    echo -e "${BLUE}🔴 Redis 시작...${NC}"

    if redis-cli ping >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Redis 실행 중${NC}"
        return 0
    fi

    if command -v docker >/dev/null 2>&1; then
        docker rm korean-redis 2>/dev/null || true
        docker run -d --name korean-redis -p 6379:6379 redis:alpine

        # 연결 대기
        for i in {1..20}; do
            if redis-cli ping >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Redis 연결 완료${NC}"
                return 0
            fi
            sleep 1
        done
    fi

    echo -e "${RED}❌ Redis 시작 실패. SQLite 모드로 전환${NC}"

    # SQLite 모드로 변경
    if [ -f "config/korean_model.yaml" ]; then
        cp config/korean_model.yaml config/korean_model.yaml.backup
        sed -i 's/type: "redis"/type: "sqlite"/' config/korean_model.yaml
        sed -i 's/type: redis/type: sqlite/' config/korean_model.yaml
        echo -e "${GREEN}✅ SQLite 모드로 변경${NC}"
    fi
}

# vLLM 서버 시작 (검증된 설정)
start_vllm() {
    if ! check_gpu; then
        echo -e "${YELLOW}⚠️ GPU 없음. vLLM 건너뛰기${NC}"
        return 0
    fi

    echo -e "${BLUE}🚀 vLLM 서버 시작...${NC}"

    # GPU 메모리 정리
    python -c "
import torch
if torch.cuda.is_available():
    torch.cuda.empty_cache()
    print('GPU 메모리 정리 완료')
"

    # 검증된 작은 모델로 시작
    nohup python -m vllm.entrypoints.openai.api_server \
        --model "distilgpt2" \
        --port 8000 \
        --host 0.0.0.0 \
        --gpu-memory-utilization 0.4 \
        --max-model-len 256 \
        --dtype half \
        --enforce-eager \
        --trust-remote-code \
        --served-model-name korean-llama \
        --disable-log-requests \
        > logs/vllm.log 2>&1 &

    VLLM_PID=$!
    echo $VLLM_PID > pids/vllm.pid
    echo "vLLM PID: $VLLM_PID"

    # 서버 준비 대기
    echo "vLLM 서버 준비 대기..."
    for i in {1..60}; do
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ vLLM 서버 준비 완료 (${i}초)${NC}"
            return 0
        fi

        # 프로세스 체크
        if ! kill -0 $VLLM_PID 2>/dev/null; then
            echo -e "${RED}❌ vLLM 프로세스 종료됨${NC}"
            echo "로그 확인:"
            tail -20 logs/vllm.log
            return 1
        fi

        if [ $((i % 10)) -eq 0 ]; then
            echo "⏳ 대기 중... (${i}/60초)"
        fi
        sleep 1
    done

    echo -e "${RED}❌ vLLM 서버 시작 시간 초과${NC}"
    return 1
}

# Token Limiter 시작
start_token_limiter() {
    echo -e "${BLUE}🛡️ Token Limiter 시작...${NC}"

    # 메인 스크립트 찾기
    if [ -f "main.py" ]; then
        MAIN_SCRIPT="main.py"
    elif [ -f "main_korean.py" ]; then
        MAIN_SCRIPT="main_korean.py"
    else
        echo -e "${RED}❌ 메인 스크립트 없음${NC}"
        return 1
    fi

    # Token Limiter 실행
    nohup python $MAIN_SCRIPT > logs/token_limiter.log 2>&1 &
    LIMITER_PID=$!
    echo $LIMITER_PID > pids/token_limiter.pid
    echo "Token Limiter PID: $LIMITER_PID"

    # 준비 대기
    echo "Token Limiter 준비 대기..."
    for i in {1..30}; do
        if curl -s http://localhost:8080/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Token Limiter 준비 완료 (${i}초)${NC}"
            return 0
        fi

        if ! kill -0 $LIMITER_PID 2>/dev/null; then
            echo -e "${RED}❌ Token Limiter 프로세스 종료됨${NC}"
            echo "로그 확인:"
            tail -20 logs/token_limiter.log
            return 1
        fi

        sleep 1
    done

    echo -e "${RED}❌ Token Limiter 시작 시간 초과${NC}"
    return 1
}

# 상태 확인
check_status() {
    echo -e "${BLUE}🔍 시스템 상태 확인${NC}"
    echo "========================="

    # 서비스 상태
    if curl -s http://localhost:8000/health >/dev/null 2>&1; then
        echo -e "vLLM 서버:      ${GREEN}✅ 정상${NC}"
    else
        echo -e "vLLM 서버:      ${RED}❌ 오류${NC}"
    fi

    if curl -s http://localhost:8080/health >/dev/null 2>&1; then
        echo -e "Token Limiter:  ${GREEN}✅ 정상${NC}"
    else
        echo -e "Token Limiter:  ${RED}❌ 오류${NC}"
    fi

    if redis-cli ping >/dev/null 2>&1; then
        echo -e "Redis:          ${GREEN}✅ 정상${NC}"
    else
        echo -e "Redis:          ${YELLOW}⚠️ SQLite 모드${NC}"
    fi

    echo ""
    echo "=== 접속 정보 ==="
    echo "🔗 vLLM 서버: http://localhost:8000"
    echo "🔗 Token Limiter: http://localhost:8080"
    echo "🔗 헬스체크: curl http://localhost:8080/health"

    echo ""
    echo "=== 테스트 명령어 ==="
    echo 'curl -X POST http://localhost:8080/v1/chat/completions \'
    echo '  -H "Content-Type: application/json" \'
    echo '  -H "Authorization: Bearer sk-user1-korean-key-def" \'
    echo '  -d '"'"'{'
    echo '    "model": "korean-llama",'
    echo '    "messages": [{"role": "user", "content": "Hello!"}],'
    echo '    "max_tokens": 50'
    echo '  }'"'"
}

# 종료 처리
cleanup_on_exit() {
    echo ""
    echo -e "${YELLOW}🛑 시스템 종료 중...${NC}"

    if [ -f "pids/token_limiter.pid" ]; then
        kill $(cat pids/token_limiter.pid) 2>/dev/null || true
        rm -f pids/token_limiter.pid
    fi

    if [ -f "pids/vllm.pid" ]; then
        kill $(cat pids/vllm.pid) 2>/dev/null || true
        rm -f pids/vllm.pid
    fi

    cleanup_processes
    echo -e "${GREEN}✅ 종료 완료${NC}"
    exit 0
}

# 시그널 핸들러
trap cleanup_on_exit INT TERM

# 메인 실행
main() {
    echo "시작 시간: $(date)"

    # 단계별 실행
    cleanup_processes
    start_redis
    start_vllm
    start_token_limiter
    check_status

    echo ""
    echo -e "${GREEN}🎉 시스템 시작 완료!${NC}"
    echo "========================="
    echo "종료하려면 Ctrl+C를 누르세요."
    echo ""

    # 모니터링
    while true; do
        sleep 30

        # 프로세스 생존 확인
        if [ -f "pids/vllm.pid" ] && ! kill -0 $(cat pids/vllm.pid) 2>/dev/null; then
            echo -e "${RED}❌ vLLM 서버 종료됨${NC}"
            break
        fi

        if [ -f "pids/token_limiter.pid" ] && ! kill -0 $(cat pids/token_limiter.pid) 2>/dev/null; then
            echo -e "${RED}❌ Token Limiter 종료됨${NC}"
            break
        fi
    done
}

# 실행
main "$@"