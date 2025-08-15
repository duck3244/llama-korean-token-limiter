#!/bin/bash
# 한국어 Llama Token Limiter 전체 시스템 시작 스크립트

set -e

echo "🇰🇷 한국어 Llama Token Limiter 시스템 시작"
echo "=================================================="

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
    
    # PID 파일 정리
    rm -f $PID_DIR/*.pid
    
    sleep 2
    echo -e "${GREEN}✅ 프로세스 정리 완료${NC}"
}

# GPU 상태 확인 함수
check_gpu() {
    echo -e "${BLUE}🔍 GPU 상태 확인...${NC}"
    
    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${RED}❌ nvidia-smi를 찾을 수 없습니다. NVIDIA 드라이버를 설치하세요.${NC}"
        exit 1
    fi
    
    echo "GPU 정보:"
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu --format=csv,noheader,nounits
    
    # GPU 메모리 사용량 확인
    memory_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    memory_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
    memory_percent=$((memory_used * 100 / memory_total))
    
    echo "GPU 메모리 사용률: ${memory_percent}%"
    
    if [ $memory_percent -gt 80 ]; then
        echo -e "${YELLOW}⚠️ GPU 메모리 사용률이 높습니다 (${memory_percent}%). 정리를 권장합니다.${NC}"
        read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Python 환경 확인 함수
check_python_env() {
    echo -e "${BLUE}🐍 Python 환경 확인...${NC}"
    
    # 가상환경 활성화
    if [[ "$VIRTUAL_ENV" == "" ]]; then
        if [ -d "venv" ]; then
            echo "가상환경 활성화 중..."
            source venv/bin/activate
        else
            echo -e "${RED}❌ 가상환경을 찾을 수 없습니다. setup.sh를 먼저 실행하세요.${NC}"
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
            echo -e "${RED}❌ Redis 시작 실패${NC}"
            exit 1
        fi
    fi
    
    # Redis 연결 확인
    echo "Redis 연결 확인 중..."
    for i in {1..30}; do
        if redis-cli -h localhost -p 6379 ping >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Redis 연결 확인됨${NC}"
            break
        else
            echo "대기 중... ($i/30)"
            sleep 1
        fi
    done
    
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Redis 연결 실패${NC}"
        exit 1
    fi
}

# vLLM 서버 시작 함수
start_vllm() {
    echo -e "${BLUE}🚀 vLLM 서버 시작 중...${NC}"
    
    # vLLM 시작 스크립트 실행 권한 확인
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
    echo "vLLM 서버 준비 대기 중..."
    for i in {1..120}; do  # 최대 2분 대기
        if curl -s http://localhost:8000/health >/dev/null 2>&1; then
            echo -e "${GREEN}✅ vLLM 서버 준비 완료 (${i}초)${NC}"
            break
        elif [ $i -eq 60 ]; then
            echo "⏳ vLLM 서버 시작에 시간이 걸리고 있습니다..."
            echo "   로그 확인: tail -f logs/vllm_startup.log"
        fi
        
        # 프로세스가 죽었는지 확인
        if ! kill -0 $VLLM_PID 2>/dev/null; then
            echo -e "${RED}❌ vLLM 서버 프로세스가 종료되었습니다${NC}"
            echo "로그 확인:"
            tail -20 logs/vllm_startup.log
            exit 1
        fi
        
        sleep 1
    done
    
    if [ $i -eq 120 ]; then
        echo -e "${RED}❌ vLLM 서버 시작 시간 초과${NC}"
        echo "로그 확인:"
        tail -20 logs/vllm_startup.log
        exit 1
    fi
    
    # 모델 정보 확인
    echo "모델 정보 확인:"
    curl -s http://localhost:8000/v1/models | jq . || echo "모델 정보 조회 실패"
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
    
    # Token Limiter 백그라운드 시작
    nohup python main_korean.py > logs/token_limiter.log 2>&1 &
    LIMITER_PID=$!
    echo $LIMITER_PID > $PID_DIR/token_limiter.pid
    
    echo "Token Limiter PID: $LIMITER_PID"
    echo "로그: tail -f logs/token_limiter.log"
    
    # Token Limiter 준비 대기
    echo "Token Limiter 준비 대기 중..."
    for i in {1..60}; do
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

# 종료 시그널 처리
cleanup_on_exit() {
    echo -e "\n${YELLOW}🛑 시스템 종료 중...${NC}"
    
    # PID 파일에서 프로세스 종료
    if [ -f "$PID_DIR/token_limiter.pid" ]; then
        kill $(cat $PID_DIR/token_limiter.pid) 2>/dev/null || true
        rm -f $PID_DIR/token_limiter.pid
    fi
    
    if [ -f "$PID_DIR/vllm.pid" ]; then
        kill $(cat $PID_DIR/vllm.pid) 2>/dev/null || true
        rm -f $PID_DIR/vllm.pid
    fi
    
    cleanup_processes
    echo -e "${GREEN}✅ 시스템 종료 완료${NC}"
    exit 0
}

# 시그널 핸들러 등록
trap cleanup_on_exit SIGINT SIGTERM

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
    echo "=================================================="
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