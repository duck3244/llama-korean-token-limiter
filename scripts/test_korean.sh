#!/bin/bash
# 한국어 Token Limiter 테스트 스크립트

set -e

echo "🧪 한국어 Token Limiter 테스트 시작"
echo "=================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOKEN_LIMITER_URL="http://localhost:8080"
VLLM_URL="http://localhost:8000"

# 테스트 결과 저장
PASSED=0
FAILED=0
TOTAL=0

# 테스트 함수
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_status="$3"

    echo -e "\n${BLUE}🧪 테스트: $test_name${NC}"
    TOTAL=$((TOTAL + 1))

    # 사용량 통계 확인
    echo "📊 [$user] 사용량 확인..."
    stats=$(curl -s "$TOKEN_LIMITER_URL/stats/$user")
    if echo "$stats" | grep -q "user_id"; then
        echo "$stats" | jq -r '"토큰(분): \(.usage.tokens_this_minute)/\(.limits.tpm), 요청(분): \(.usage.requests_this_minute)/\(.limits.rpm)"' 2>/dev/null || echo "통계 파싱 실패"
    else
        echo "❌ 통계 조회 실패"
    fi

    sleep 1
done

echo ""
echo "=== 속도 제한 테스트 ==="

# 부하 테스트 (테스트 계정으로 연속 요청)
echo -e "${BLUE}🚀 부하 테스트 (테스트 계정으로 연속 요청)...${NC}"

for i in {1..8}; do
    echo "요청 #$i..."
    response=$(curl -s -w "%{http_code}" -X POST "$TOKEN_LIMITER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer sk-test-korean-key-stu" \
        -d "{
            \"model\": \"korean-llama\",
            \"messages\": [
                {\"role\": \"user\", \"content\": \"짧은 인사말을 해주세요. (${i}번째 요청)\"}
            ],
            \"max_tokens\": 30
        }")

    http_code="${response: -3}"

    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ 응답: HTTP $http_code${NC}"
    elif [ "$http_code" = "429" ]; then
        echo -e "${YELLOW}🎯 속도 제한 성공적으로 작동! (HTTP $http_code)${NC}"
        echo "${response%???}" | jq -r '.error.message // "제한 메시지 없음"' 2>/dev/null
        break
    else
        echo -e "${RED}❌ 예상치 못한 응답: HTTP $http_code${NC}"
    fi

    sleep 0.5
done

echo ""
echo "=== API 엔드포인트 테스트 ==="

# 관리자 API 테스트
run_test "사용자 목록 조회" "curl -s $TOKEN_LIMITER_URL/admin/users | grep -q users" "success"

run_test "시스템 통계 조회" "curl -s $TOKEN_LIMITER_URL/admin/statistics | grep -q total_users" "success"

run_test "상위 사용자 조회" "curl -s '$TOKEN_LIMITER_URL/admin/top-users?limit=5' | grep -q top_users" "success"

run_test "설정 다시 로드" "curl -s -X POST $TOKEN_LIMITER_URL/admin/reload-config | grep -q message" "success"

echo ""
echo "=== 잘못된 요청 테스트 ==="

# 잘못된 JSON 테스트
echo -e "${BLUE}🧪 잘못된 JSON 요청 테스트${NC}"
response=$(curl -s -w "%{http_code}" -X POST "$TOKEN_LIMITER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer sk-user1-korean-key-def" \
    -d "{invalid json}")

http_code="${response: -3}"
if [ "$http_code" = "400" ]; then
    echo -e "${GREEN}✅ 잘못된 JSON 적절히 처리됨 (HTTP 400)${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ 잘못된 JSON 처리 실패 (HTTP $http_code)${NC}"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# 존재하지 않는 사용자 테스트
echo -e "${BLUE}🧪 존재하지 않는 사용자 요청 테스트${NC}"
response=$(curl -s -w "%{http_code}" -X POST "$TOKEN_LIMITER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer invalid-key-123" \
    -d '{
        "model": "korean-llama",
        "messages": [{"role": "user", "content": "테스트"}],
        "max_tokens": 50
    }')

http_code="${response: -3}"
if [ "$http_code" = "200" ] || [ "$http_code" = "429" ]; then
    echo -e "${GREEN}✅ 존재하지 않는 사용자 적절히 처리됨 (HTTP $http_code)${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ 존재하지 않는 사용자 처리 실패 (HTTP $http_code)${NC}"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

echo ""
echo "=== 한국어 토큰 계산 테스트 ==="

# 다양한 한국어 텍스트의 토큰 계산 테스트
korean_texts=(
    "안녕하세요"
    "한국어 토큰 계산 테스트입니다"
    "복잡한 한국어 문장: 안녕하세요! 오늘은 날씨가 정말 좋네요. 어떻게 지내시나요?"
    "English mixed 한국어 텍스트 123 테스트"
    "이모지 포함 😊 한국어 텍스트 🇰🇷"
)

for text in "${korean_texts[@]}"; do
    echo -e "\n${BLUE}🔤 토큰 계산: \"$text\"${NC}"

    response=$(curl -s "$TOKEN_LIMITER_URL/token-info" \
        --data-urlencode "text=$text")

    if echo "$response" | grep -q "token_count"; then
        token_count=$(echo "$response" | jq -r '.token_count // "N/A"' 2>/dev/null)
        composition=$(echo "$response" | jq -r '.composition // {}' 2>/dev/null)
        echo -e "${GREEN}✅ 토큰 수: $token_count${NC}"
        echo "$response" | jq -r '"한글: \(.composition.korean_chars // 0)자, 영어: \(.composition.english_chars // 0)자, 한글비율: \((.composition.korean_ratio // 0) * 100 | floor)%"' 2>/dev/null || echo "구성 정보 파싱 실패"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ 토큰 계산 실패${NC}"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

echo ""
echo "=== 성능 테스트 ==="

# 동시 요청 테스트
echo -e "${BLUE}⚡ 동시 요청 성능 테스트${NC}"

# 백그라운드에서 동시에 여러 요청 실행
pids=()
start_time=$(date +%s.%N)

for i in {1..5}; do
    (
        response=$(curl -s -w "%{http_code}" -X POST "$TOKEN_LIMITER_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer sk-user1-korean-key-def" \
            -d "{
                \"model\": \"korean-llama\",
                \"messages\": [{\"role\": \"user\", \"content\": \"동시 요청 테스트 $i\"}],
                \"max_tokens\": 20
            }")
        echo "요청 $i: ${response: -3}"
    ) &
    pids+=($!)
done

# 모든 백그라운드 작업 완료 대기
for pid in "${pids[@]}"; do
    wait $pid
done

end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "시간 측정 실패")

echo -e "${GREEN}✅ 동시 요청 5개 완료 (소요 시간: ${duration}초)${NC}"

echo ""
echo "=== 데이터베이스 무결성 테스트 ==="

# 사용량 초기화 테스트 (관리자 기능)
echo -e "${BLUE}🔄 사용량 초기화 테스트${NC}"
response=$(curl -s -w "%{http_code}" -X DELETE "$TOKEN_LIMITER_URL/admin/reset-usage/테스트")
http_code="${response: -3}"

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✅ 사용량 초기화 성공${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}❌ 사용량 초기화 실패 (HTTP $http_code)${NC}"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# 초기화 후 사용량 확인
echo "🔍 초기화 후 사용량 확인..."
stats=$(curl -s "$TOKEN_LIMITER_URL/stats/테스트")
if echo "$stats" | jq -r '.usage.tokens_this_minute' 2>/dev/null | grep -q "0"; then
    echo -e "${GREEN}✅ 사용량이 정상적으로 초기화됨${NC}"
else
    echo -e "${YELLOW}⚠️ 사용량 초기화 확인 불가${NC}"
fi

echo ""
echo "=== 최종 시스템 상태 확인 ==="

# 최종 헬스체크
echo -e "${BLUE}🏥 최종 시스템 헬스체크${NC}"
health_response=$(curl -s "$TOKEN_LIMITER_URL/health")

if echo "$health_response" | grep -q "healthy"; then
    echo -e "${GREEN}✅ 시스템 정상 상태 유지${NC}"
    echo "$health_response" | jq -r '"모델: \(.model // "N/A"), 저장소: \(.storage_type // "N/A"), 한국어 지원: \(.supports_korean // false)"' 2>/dev/null || echo "상태 정보 파싱 실패"
else
    echo -e "${RED}❌ 시스템 상태 이상${NC}"
    echo "$health_response"
fi

# 전체 통계 확인
echo -e "\n${BLUE}📈 시스템 전체 통계${NC}"
system_stats=$(curl -s "$TOKEN_LIMITER_URL/admin/statistics")
if echo "$system_stats" | grep -q "total_users"; then
    echo "$system_stats" | jq -r '"총 사용자: \(.total_users // 0), 오늘 활성 사용자: \(.active_users_today // 0), 오늘 총 토큰: \(.total_tokens_today // 0)"' 2>/dev/null || echo "통계 파싱 실패"
else
    echo "통계 조회 실패"
fi

echo ""
echo "=================================="
echo "🧪 한국어 Token Limiter 테스트 완료"
echo "=================================="
echo -e "${GREEN}✅ 통과: $PASSED${NC}"
echo -e "${RED}❌ 실패: $FAILED${NC}"
echo -e "${BLUE}📊 전체: $TOTAL${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 모든 테스트가 성공적으로 완료되었습니다!${NC}"
    echo ""
    echo "=== 추가 테스트 명령어 ==="
    echo "# 수동 채팅 테스트:"
    echo "curl -X POST http://localhost:8080/v1/chat/completions \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -H 'Authorization: Bearer sk-user1-korean-key-def' \\"
    echo "  -d '{"
    echo "    \"model\": \"korean-llama\","
    echo "    \"messages\": [{"
    echo "      \"role\": \"user\","
    echo "      \"content\": \"한국어로 자기소개를 해주세요.\""
    echo "    }],"
    echo "    \"max_tokens\": 150"
    echo "  }' | jq ."
    echo ""
    echo "# 사용량 모니터링:"
    echo "watch -n 2 'curl -s http://localhost:8080/stats/사용자1 | jq .'"
    echo ""
    echo "# 로그 확인:"
    echo "tail -f logs/token_limiter.log"

    exit 0
else
    echo -e "\n${RED}⚠️ 일부 테스트가 실패했습니다.${NC}"
    echo "로그를 확인하여 문제를 해결하세요:"
    echo "- tail -f logs/token_limiter.log"
    echo "- tail -f logs/vllm_korean_server.log"

    exit 1
fi

    # 명령어 실행
    response=$(eval "$test_command" 2>/dev/null)
    exit_code=$?

    if [ $exit_code -eq 0 ] && [ "$expected_status" = "success" ]; then
        echo -e "${GREEN}✅ 통과${NC}"
        PASSED=$((PASSED + 1))
        return 0
    elif [ $exit_code -ne 0 ] && [ "$expected_status" = "fail" ]; then
        echo -e "${GREEN}✅ 통과 (예상된 실패)${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ 실패${NC}"
        echo "응답: $response"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# HTTP 요청 헬퍼 함수
make_request() {
    local method="$1"
    local url="$2"
    local headers="$3"
    local data="$4"

    if [ -n "$data" ]; then
        curl -s -w "%{http_code}" -X "$method" "$url" $headers -d "$data"
    else
        curl -s -w "%{http_code}" -X "$method" "$url" $headers
    fi
}

# 시스템 상태 확인
echo -e "${BLUE}🔍 시스템 상태 확인...${NC}"

# Token Limiter 헬스체크
if curl -s "$TOKEN_LIMITER_URL/health" | grep -q "healthy"; then
    echo -e "${GREEN}✅ Token Limiter 정상${NC}"
else
    echo -e "${RED}❌ Token Limiter 오류 - 테스트를 중단합니다${NC}"
    exit 1
fi

# vLLM 서버 헬스체크
if curl -s "$VLLM_URL/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ vLLM 서버 정상${NC}"
else
    echo -e "${YELLOW}⚠️ vLLM 서버 연결 불가 - 일부 테스트가 실패할 수 있습니다${NC}"
fi

echo ""
echo "=== 기본 기능 테스트 ==="

# 1. 헬스체크 테스트
run_test "헬스체크" "curl -s $TOKEN_LIMITER_URL/health | grep -q healthy" "success"

# 2. 토큰 정보 테스트
run_test "토큰 정보 조회" "curl -s '$TOKEN_LIMITER_URL/token-info?text=안녕하세요' | grep -q token_count" "success"

# 3. 사용자 통계 조회 테스트
run_test "사용자 통계 조회" "curl -s $TOKEN_LIMITER_URL/stats/사용자1 | grep -q user_id" "success"

echo ""
echo "=== 한국어 사용자별 테스트 ==="

# 한국어 사용자 및 API 키 배열
korean_users=("사용자1" "사용자2" "개발자1" "테스트" "게스트")
api_keys=("sk-user1-korean-key-def" "sk-user2-korean-key-ghi" "sk-dev1-korean-key-789" "sk-test-korean-key-stu" "sk-guest-korean-key-vwx")

# 한국어 테스트 메시지들
korean_messages=(
    "안녕하세요! 한국어로 대화할 수 있나요?"
    "오늘 날씨가 어떤가요? 간단히 답변해주세요."
    "파이썬 프로그래밍에 대해 짧게 설명해주세요."
    "김치찌개 레시피를 알려주세요."
    "K-pop에 대한 당신의 생각은 어떤가요?"
)

# 사용자별 채팅 완성 요청 테스트
for i in ${!korean_users[@]}; do
    user=${korean_users[$i]}
    api_key=${api_keys[$i]}
    message=${korean_messages[$i]}

    echo -e "\n${BLUE}🇰🇷 [$user] 채팅 완성 테스트${NC}"
    echo "메시지: $message"

    # 채팅 완성 요청
    response=$(curl -s -w "%{http_code}" -X POST "$TOKEN_LIMITER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "{
            \"model\": \"korean-llama\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"당신은 친근한 한국어 AI 어시스턴트입니다. 간결하고 정확하게 답변해주세요.\"},
                {\"role\": \"user\", \"content\": \"$message\"}
            ],
            \"max_tokens\": 100,
            \"temperature\": 0.7
        }")

    http_code="${response: -3}"
    response_body="${response%???}"

    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ [$user] 요청 성공 (HTTP $http_code)${NC}"
        PASSED=$((PASSED + 1))

        # 응답 내용 일부 표시
        echo "$response_body" | jq -r '.choices[0].message.content // "응답 파싱 실패"' 2>/dev/null | head -2 || echo "응답 파싱 실패"

    elif [ "$http_code" = "429" ]; then
        echo -e "${YELLOW}⚠️ [$user] 속도 제한 감지 (HTTP $http_code)${NC}"
        echo "$response_body" | jq -r '.error.message // "제한 메시지 없음"' 2>/dev/null
        PASSED=$((PASSED + 1))  # 예상된 동작

    else
        echo -e "${RED}❌ [$user] 요청 실패 (HTTP $http_code)${NC}"
        echo "$response_body" | head -2
        FAILED=$((FAILED + 1))
    fi

    TOTAL=$((TOTAL + 1))