#!/bin/bash
# 한국어 Llama Token Limiter 시스템 종료 스크립트

set -e

echo "🛑 한국어 Llama Token Limiter 시스템 종료 중..."
echo "=============================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# PID 파일 저장 경로
PID_DIR="./pids"

# 안전한 프로세스 종료 함수
safe_kill() {
    local pid=$1
    local name=$2
    local timeout=${3:-10}

    if [ -z "$pid" ]; then
        echo -e "${YELLOW}⚠️ $name: PID가 지정되지 않았습니다${NC}"
        return 0
    fi

    # 프로세스가 실행 중인지 확인
    if ! kill -0 $pid 2>/dev/null; then
        echo -e "${YELLOW}⚠️ $name: 프로세스가 이미 종료되었습니다 (PID: $pid)${NC}"
        return 0
    fi

    echo -e "${BLUE}🔄 $name 종료 중... (PID: $pid)${NC}"

    # SIGTERM으로 정상 종료 시도
    kill -TERM $pid 2>/dev/null || true

    # 종료 대기
    local count=0
    while [ $count -lt $timeout ]; do
        if ! kill -0 $pid 2>/dev/null; then
            echo -e "${GREEN}✅ $name 정상 종료됨${NC}"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done

    # 강제 종료
    echo -e "${YELLOW}⚠️ $name 강제 종료 중...${NC}"
    kill -KILL $pid 2>/dev/null || true
    sleep 2

    if ! kill -0 $pid 2>/dev/null; then
        echo -e "${GREEN}✅ $name 강제 종료됨${NC}"
    else
        echo -e "${RED}❌ $name 종료 실패${NC}"
        return 1
    fi
}

# PID 파일에서 프로세스 종료
stop_from_pid_file() {
    local service_name=$1
    local pid_file="$PID_DIR/${service_name}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        safe_kill "$pid" "$service_name" 15
        rm -f "$pid_file"
    else
        echo -e "${YELLOW}⚠️ $service_name: PID 파일을 찾을 수 없습니다${NC}"
    fi
}

# 프로세스 이름으로 종료
stop_by_process_name() {
    local process_pattern=$1
    local service_name=$2

    echo -e "${BLUE}🔍 $service_name 프로세스 검색 중...${NC}"

    local pids=$(pgrep -f "$process_pattern" 2>/dev/null || true)

    if [ -z "$pids" ]; then
        echo -e "${YELLOW}⚠️ $service_name: 실행 중인 프로세스를 찾을 수 없습니다${NC}"
        return 0
    fi

    echo "발견된 $service_name 프로세스: $pids"

    for pid in $pids; do
        safe_kill "$pid" "$service_name" 10
    done
}

# 메인 종료 함수
main_shutdown() {
    echo "종료 시작 시간: $(date)"

    # 1. PID 파일에서 프로세스 종료
    echo -e "\n${BLUE}📁 PID 파일 기반 종료...${NC}"

    if [ -d "$PID_DIR" ]; then
        stop_from_pid_file "token_limiter"
        stop_from_pid_file "vllm"
    else
        echo -e "${YELLOW}⚠️ PID 디렉토리가 존재하지 않습니다${NC}"
    fi

    # 2. 프로세스 이름으로 종료
    echo -e "\n${BLUE}🔎 프로세스 이름 기반 종료...${NC}"

    # Token Limiter 프로세스 종료
    stop_by_process_name "main_korean.py" "Token Limiter"
    stop_by_process_name "main.py" "Token Limiter (fallback)"

    # vLLM 프로세스 종료
    stop_by_process_name "vllm.entrypoints.openai.api_server" "vLLM Server"

    # 관련 Python 프로세스 확인 및 종료
    stop_by_process_name "korean.*token.*limiter" "Korean Token Limiter"

    # 3. Docker 컨테이너 종료
    echo -e "\n${BLUE}🐳 Docker 컨테이너 종료...${NC}"

    # Redis 컨테이너 종료
    if docker ps | grep -q korean-redis; then
        echo "Redis 컨테이너 종료 중..."
        docker stop korean-redis >/dev/null 2>&1 || true
        docker rm korean-redis >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ Redis 컨테이너 종료됨${NC}"
    else
        echo -e "${YELLOW}⚠️ Redis 컨테이너가 실행 중이지 않습니다${NC}"
    fi

    # 4. 포트 사용 중인 프로세스 확인 및 종료
    echo -e "\n${BLUE}🔌 포트 사용 프로세스 확인...${NC}"

    # 8080 포트 (Token Limiter)
    local port_8080_pid=$(lsof -ti:8080 2>/dev/null || true)
    if [ -n "$port_8080_pid" ]; then
        echo "포트 8080 사용 프로세스 종료: $port_8080_pid"
        safe_kill "$port_8080_pid" "Port 8080 Process" 5
    fi

    # 8000 포트 (vLLM)
    local port_8000_pid=$(lsof -ti:8000 2>/dev/null || true)
    if [ -n "$port_8000_pid" ]; then
        echo "포트 8000 사용 프로세스 종료: $port_8000_pid"
        safe_kill "$port_8000_pid" "Port 8000 Process" 5
    fi

    # 5. GPU 메모리 정리
    echo -e "\n${BLUE}🎮 GPU 메모리 정리...${NC}"

    if command -v nvidia-smi &> /dev/null; then
        echo "GPU 프로세스 확인 중..."
        gpu_processes=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null || true)

        if [ -n "$gpu_processes" ]; then
            echo "GPU 사용 프로세스 발견: $gpu_processes"
            for gpu_pid in $gpu_processes; do
                # 우리가 시작한 프로세스인지 확인 (vLLM 관련)
                if ps -p $gpu_pid -o cmd= 2>/dev/null | grep -q "vllm\|korean\|llama"; then
                    echo "GPU에서 vLLM 프로세스 종료: $gpu_pid"
                    safe_kill "$gpu_pid" "GPU vLLM Process" 10
                fi
            done
        else
            echo -e "${GREEN}✅ GPU에서 실행 중인 관련 프로세스 없음${NC}"
        fi

        # CUDA 메모리 정리 시도
        python3 -c "
try:
    import torch
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        print('✅ CUDA 캐시 정리 완료')
except:
    print('⚠️ CUDA 캐시 정리 실패 또는 불필요')
" 2>/dev/null || echo "⚠️ PyTorch를 사용한 GPU 메모리 정리 불가"

    else
        echo -e "${YELLOW}⚠️ nvidia-smi를 찾을 수 없습니다${NC}"
    fi

    # 6. 임시 파일 및 PID 파일 정리
    echo -e "\n${BLUE}🧹 임시 파일 정리...${NC}"

    # PID 파일들 정리
    if [ -d "$PID_DIR" ]; then
        rm -f "$PID_DIR"/*.pid
        echo "✅ PID 파일 정리 완료"
    fi

    # 임시 로그 파일 정리 (선택사항)
    if [ -d "logs" ]; then
        # 24시간 이상 된 로그 파일 압축
        find logs -name "*.log" -mtime +1 -exec gzip {} \; 2>/dev/null || true
        echo "✅ 오래된 로그 파일 압축 완료"
    fi

    # 7. 최종 상태 확인
    echo -e "\n${BLUE}🔍 최종 상태 확인...${NC}"

    # 포트 확인
    if ! lsof -i:8080 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 포트 8080 해제됨${NC}"
    else
        echo -e "${RED}❌ 포트 8080 여전히 사용 중${NC}"
    fi

    if ! lsof -i:8000 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 포트 8000 해제됨${NC}"
    else
        echo -e "${RED}❌ 포트 8000 여전히 사용 중${NC}"
    fi

    # 관련 프로세스 확인
    remaining_processes=$(pgrep -f "vllm\|korean.*token\|main_korean" 2>/dev/null || true)
    if [ -z "$remaining_processes" ]; then
        echo -e "${GREEN}✅ 관련 프로세스 모두 종료됨${NC}"
    else
        echo -e "${YELLOW}⚠️ 남은 프로세스: $remaining_processes${NC}"
        echo "수동으로 종료하려면: kill -9 $remaining_processes"
    fi

    # Docker 상태 확인
    if ! docker ps | grep -q korean-redis; then
        echo -e "${GREEN}✅ Docker 컨테이너 정리됨${NC}"
    else
        echo -e "${YELLOW}⚠️ Docker 컨테이너가 여전히 실행 중${NC}"
    fi

    echo ""
    echo "=============================================="
    echo -e "${GREEN}✅ 한국어 Llama Token Limiter 시스템 종료 완료${NC}"
    echo "=============================================="
    echo "종료 완료 시간: $(date)"

    # GPU 메모리 상태 표시
    if command -v nvidia-smi &> /dev/null; then
        echo ""
        echo "🎮 최종 GPU 상태:"
        nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits | \
        awk '{printf "GPU 메모리: %s/%s MB (%.1f%%), GPU 사용률: %s%%\n", $1, $2, ($1/$2)*100, $3}'
    fi

    echo ""
    echo "📋 시스템 재시작 명령어:"
    echo "  ./scripts/start_korean_system.sh"
    echo ""
    echo "🔍 로그 확인:"
    echo "  tail -f logs/token_limiter.log"
    echo "  tail -f logs/vllm_korean_server.log"
}

# 강제 종료 옵션 처리
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}⚠️ 강제 종료 모드 활성화${NC}"

    # 모든 관련 프로세스 강제 종료
    pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true
    pkill -9 -f "main_korean.py" 2>/dev/null || true
    pkill -9 -f "korean.*token.*limiter" 2>/dev/null || true

    # Docker 강제 정리
    docker kill korean-redis 2>/dev/null || true
    docker rm korean-redis 2>/dev/null || true

    # PID 파일 정리
    rm -rf "$PID_DIR"

    echo -e "${GREEN}✅ 강제 종료 완료${NC}"
    exit 0
fi

# 도움말 표시
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "한국어 Llama Token Limiter 시스템 종료 스크립트"
    echo ""
    echo "사용법:"
    echo "  $0              # 정상 종료"
    echo "  $0 --force      # 강제 종료"
    echo "  $0 --help       # 이 도움말 표시"
    echo ""
    echo "옵션:"
    echo "  --force, -f     모든 프로세스를 강제로 종료합니다"
    echo "  --help, -h      이 도움말을 표시합니다"
    echo ""
    exit 0
fi

# 종료 시그널 처리
cleanup_on_signal() {
    echo -e "\n${YELLOW}🛑 종료 신호 감지됨${NC}"
    exit 0
}

# 시그널 핸들러 등록
trap cleanup_on_signal SIGINT SIGTERM

# 메인 실행
main_shutdown