#!/usr/bin/env python3
"""
Korean Llama Token Limiter - 메인 애플리케이션 (인코딩 문제 수정)
"""

import asyncio
import json
import time
import logging
import sys
import os
import base64
import urllib.parse

try:
    import uvicorn
    from fastapi import FastAPI, Request, HTTPException
    from fastapi.responses import JSONResponse
    from fastapi.middleware.cors import CORSMiddleware
    import httpx
except ImportError as e:
    print(f"❌ 필수 패키지 누락: {e}")
    print("pip install fastapi uvicorn httpx 를 실행하세요.")
    sys.exit(1)

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# FastAPI 앱 생성
app = FastAPI(
    title="🇰🇷 Korean Token Limiter",
    description="한국어 LLM 토큰 사용량 제한 시스템",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class SimpleTokenCounter:
    """간단한 토큰 카운터"""

    @staticmethod
    def count_tokens(text: str) -> int:
        """텍스트의 대략적인 토큰 수 계산"""
        if not text:
            return 0

        # 한국어 특화 계산 (1글자 ≈ 1.2토큰)
        korean_chars = len([c for c in text if '\uac00' <= c <= '\ud7af'])
        english_chars = len([c for c in text if c.isalpha() and ord(c) < 128])
        other_chars = len(text) - korean_chars - english_chars

        tokens = int(korean_chars * 1.2 + english_chars * 0.25 + other_chars * 0.5)
        return max(1, tokens)

    @staticmethod
    def count_messages_tokens(messages) -> int:
        """메시지의 토큰 수 계산"""
        total = 0
        for msg in messages:
            if isinstance(msg, dict) and 'content' in msg:
                total += SimpleTokenCounter.count_tokens(str(msg['content']))
                total += 3  # 역할 오버헤드
        return total + 4  # 대화 오버헤드


class SimpleRateLimiter:
    """간단한 속도 제한기"""

    def __init__(self):
        self.users = {}
        self.default_limits = {
            'rpm': 30,
            'tpm': 5000,
            'daily': 500000
        }

        # 사용자별 API 키 매핑 (한국어 -> 영어 변환)
        self.api_keys = {
            'sk-user1-korean-key-def': 'user1',
            'sk-user2-korean-key-ghi': 'user2',
            'sk-dev1-korean-key-789': 'developer1',
            'sk-test-korean-key-stu': 'test',
            'sk-guest-korean-key-vwx': 'guest'
        }

        # 영어 -> 한국어 매핑 (표시용)
        self.user_display_names = {
            'user1': '사용자1',
            'user2': '사용자2',
            'developer1': '개발자1',
            'test': '테스트',
            'guest': '게스트'
        }

    def get_user_from_api_key(self, api_key: str) -> str:
        """API 키에서 사용자 ID 추출 (ASCII 안전)"""
        return self.api_keys.get(api_key, 'guest')

    def get_display_name(self, user_id: str) -> str:
        """사용자 표시명 조회"""
        return self.user_display_names.get(user_id, user_id)

    def check_limits(self, user_id: str, tokens: int) -> tuple:
        """사용량 제한 확인"""
        now = time.time()

        if user_id not in self.users:
            self.users[user_id] = {
                'requests_minute': [],
                'tokens_minute': [],
                'tokens_daily': [],
                'total_requests': 0,
                'total_tokens': 0
            }

        user_data = self.users[user_id]

        # 1분 이내 데이터만 유지
        minute_ago = now - 60
        user_data['requests_minute'] = [t for t in user_data['requests_minute'] if t > minute_ago]
        user_data['tokens_minute'] = [t for t in user_data['tokens_minute'] if t[0] > minute_ago]

        # 하루 이내 데이터만 유지
        day_ago = now - 86400
        user_data['tokens_daily'] = [t for t in user_data['tokens_daily'] if t[0] > day_ago]

        # 현재 사용량 계산
        current_rpm = len(user_data['requests_minute'])
        current_tpm = sum(t[1] for t in user_data['tokens_minute'])
        current_daily = sum(t[1] for t in user_data['tokens_daily'])

        # 제한 확인
        if current_rpm >= self.default_limits['rpm']:
            return False, f"분당 요청 제한 초과 ({self.default_limits['rpm']}개)"

        if current_tpm + tokens > self.default_limits['tpm']:
            return False, f"분당 토큰 제한 초과 ({self.default_limits['tpm']}개)"

        if current_daily + tokens > self.default_limits['daily']:
            return False, f"일일 토큰 제한 초과 ({self.default_limits['daily']}개)"

        return True, None

    def record_usage(self, user_id: str, tokens: int):
        """사용량 기록"""
        now = time.time()

        if user_id not in self.users:
            self.users[user_id] = {
                'requests_minute': [],
                'tokens_minute': [],
                'tokens_daily': [],
                'total_requests': 0,
                'total_tokens': 0
            }

        user_data = self.users[user_id]
        user_data['requests_minute'].append(now)
        user_data['tokens_minute'].append((now, tokens))
        user_data['tokens_daily'].append((now, tokens))
        user_data['total_requests'] += 1
        user_data['total_tokens'] += tokens

    def get_user_stats(self, user_id: str) -> dict:
        """사용자 통계 조회"""
        # 한국어 사용자 ID 처리
        if user_id in self.user_display_names.values():
            # 한국어 -> 영어 변환
            for eng_id, kor_name in self.user_display_names.items():
                if kor_name == user_id:
                    user_id = eng_id
                    break

        if user_id not in self.users:
            return {
                'user_id': user_id,
                'display_name': self.get_display_name(user_id),
                'requests_this_minute': 0,
                'tokens_this_minute': 0,
                'tokens_today': 0,
                'total_requests': 0,
                'total_tokens': 0,
                'limits': self.default_limits
            }

        now = time.time()
        minute_ago = now - 60
        day_ago = now - 86400

        user_data = self.users[user_id]

        return {
            'user_id': user_id,
            'display_name': self.get_display_name(user_id),
            'requests_this_minute': len([t for t in user_data['requests_minute'] if t > minute_ago]),
            'tokens_this_minute': sum(t[1] for t in user_data['tokens_minute'] if t[0] > minute_ago),
            'tokens_today': sum(t[1] for t in user_data['tokens_daily'] if t[0] > day_ago),
            'total_requests': user_data['total_requests'],
            'total_tokens': user_data['total_tokens'],
            'limits': self.default_limits
        }


# 전역 인스턴스
token_counter = SimpleTokenCounter()
rate_limiter = SimpleRateLimiter()


def extract_user_id(request: Request) -> str:
    """요청에서 사용자 ID 추출 (ASCII 안전)"""
    # Authorization 헤더
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        api_key = auth_header[7:]
        return rate_limiter.get_user_from_api_key(api_key)

    # X-User-ID 헤더
    user_id = request.headers.get("x-user-id")
    if user_id:
        return user_id

    return "guest"


def convert_to_completion_format(messages, model="distilgpt2"):
    """채팅 메시지를 completion 형태로 변환"""
    prompt_parts = []

    for message in messages:
        role = message.get("role", "")
        content = message.get("content", "")

        if role == "system":
            prompt_parts.append(f"System: {content}")
        elif role == "user":
            prompt_parts.append(f"User: {content}")
        elif role == "assistant":
            prompt_parts.append(f"Assistant: {content}")

    # 마지막에 Assistant: 추가해서 응답 유도
    prompt_parts.append("Assistant:")

    return "\n".join(prompt_parts)


@app.middleware("http")
async def token_limit_middleware(request: Request, call_next):
    """토큰 제한 미들웨어 (인코딩 문제 수정)"""

    # API 경로가 아니면 통과
    if not any(path in request.url.path for path in ["/v1/chat/completions", "/v1/completions"]):
        return await call_next(request)

    user_id = extract_user_id(request)

    # 요청 본문 읽기
    body = await request.body()

    try:
        request_data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        return JSONResponse(
            status_code=400,
            content={"error": "잘못된 JSON 형식입니다"}
        )

    # 토큰 계산
    estimated_tokens = 0
    if 'messages' in request_data:
        estimated_tokens = token_counter.count_messages_tokens(request_data['messages'])
    elif 'prompt' in request_data:
        estimated_tokens = token_counter.count_tokens(str(request_data['prompt']))

    estimated_tokens += request_data.get('max_tokens', 100)

    # 제한 확인
    allowed, reason = rate_limiter.check_limits(user_id, estimated_tokens)

    if not allowed:
        logger.warning(f"Rate limit exceeded for user '{user_id}': {reason}")
        return JSONResponse(
            status_code=429,
            content={
                "error": {
                    "message": reason,
                    "type": "rate_limit_exceeded",
                    "user_id": user_id,
                    "estimated_tokens": estimated_tokens
                }
            }
        )

    # 사용량 기록
    rate_limiter.record_usage(user_id, estimated_tokens)

    # 요청 본문 복원
    async def receive():
        return {"type": "http.request", "body": body}

    request._receive = receive

    # 요청 처리
    response = await call_next(request)

    # ASCII 안전 헤더 추가 (URL 인코딩 사용)
    safe_user_id = urllib.parse.quote(user_id.encode('utf-8'))
    response.headers["X-User-ID"] = safe_user_id

    return response


@app.post("/v1/chat/completions")
async def chat_completions_proxy(request: Request):
    """채팅 완성 프록시 (completion API로 변환)"""

    body = await request.body()
    user_id = extract_user_id(request)

    try:
        request_data = json.loads(body)
        messages = request_data.get('messages', [])
        max_tokens = request_data.get('max_tokens', 50)
        temperature = request_data.get('temperature', 0.7)

        # 채팅 메시지를 프롬프트로 변환
        prompt = convert_to_completion_format(messages)

        # completion API 형태로 변환
        completion_request = {
            "model": "distilgpt2",
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stop": ["\nUser:", "\nSystem:"]
        }

        # vLLM completion API 호출
        async with httpx.AsyncClient(timeout=30.0) as client:
            llm_response = await client.post(
                "http://localhost:8000/v1/completions",
                json=completion_request
            )

        if llm_response.status_code != 200:
            return JSONResponse(
                status_code=llm_response.status_code,
                content={"error": "vLLM 서버 오류", "detail": llm_response.text}
            )

        completion_result = llm_response.json()

        # OpenAI 채팅 형태로 응답 변환
        if 'choices' in completion_result and len(completion_result['choices']) > 0:
            generated_text = completion_result['choices'][0]['text'].strip()

            chat_response = {
                "id": f"chatcmpl-{int(time.time())}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": "korean-llama",
                "choices": [{
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": generated_text
                    },
                    "finish_reason": "stop"
                }],
                "usage": completion_result.get('usage', {
                    "prompt_tokens": token_counter.count_tokens(prompt),
                    "completion_tokens": token_counter.count_tokens(generated_text),
                    "total_tokens": token_counter.count_tokens(prompt + generated_text)
                })
            }

            return JSONResponse(content=chat_response)
        else:
            return JSONResponse(
                status_code=500,
                content={"error": "응답 생성 실패"}
            )

    except httpx.ConnectError:
        logger.error(f"vLLM server connection error for user '{user_id}'")
        return JSONResponse(
            status_code=503,
            content={"error": "LLM 서버에 연결할 수 없습니다"}
        )
    except Exception as e:
        logger.error(f"Chat completion error for user '{user_id}': {e}")
        return JSONResponse(
            status_code=500,
            content={"error": f"채팅 완성 오류: {str(e)}"}
        )


@app.post("/v1/completions")
async def completions_proxy(request: Request):
    """텍스트 완성 프록시"""

    body = await request.body()
    user_id = extract_user_id(request)

    # 헤더 준비
    headers = dict(request.headers)
    headers.pop("host", None)
    headers.pop("content-length", None)

    try:
        # vLLM 서버로 요청 전달
        async with httpx.AsyncClient(timeout=30.0) as client:
            llm_response = await client.post(
                "http://localhost:8000/v1/completions",
                content=body,
                headers=headers
            )

        # 응답 반환
        response_content = llm_response.json() if llm_response.headers.get("content-type", "").startswith(
            "application/json") else llm_response.text

        return JSONResponse(
            content=response_content,
            status_code=llm_response.status_code,
            headers={k: v for k, v in llm_response.headers.items() if
                     k.lower() not in ['content-length', 'transfer-encoding']}
        )

    except httpx.ConnectError:
        logger.error(f"vLLM server connection error for user '{user_id}'")
        return JSONResponse(
            status_code=503,
            content={"error": "LLM 서버에 연결할 수 없습니다"}
        )
    except Exception as e:
        logger.error(f"Completion proxy error for user '{user_id}': {e}")
        return JSONResponse(
            status_code=500,
            content={"error": f"텍스트 완성 오류: {str(e)}"}
        )


@app.get("/health")
async def health_check():
    """헬스체크"""
    try:
        # vLLM 서버 확인
        async with httpx.AsyncClient(timeout=5.0) as client:
            vllm_response = await client.get("http://localhost:8000/health")
            vllm_status = vllm_response.status_code == 200
    except:
        vllm_status = False

    return {
        "status": "healthy",
        "vllm_server": "connected" if vllm_status else "disconnected",
        "model": "korean-llama",
        "supports_korean": True,
        "encoding": "utf-8_safe",
        "timestamp": time.time()
    }


@app.get("/stats/{user_id}")
async def get_user_stats(user_id: str):
    """사용자 통계 조회"""
    try:
        # URL 디코딩
        user_id = urllib.parse.unquote(user_id)
        stats = rate_limiter.get_user_stats(user_id)
        return stats
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"통계 조회 실패: {str(e)}")


@app.get("/token-info")
async def get_token_info(text: str = "안녕하세요! 한국어 토큰 계산 테스트입니다."):
    """토큰 계산 정보"""
    try:
        token_count = token_counter.count_tokens(text)
        return {
            "text": text,
            "token_count": token_count,
            "method": "korean_optimized"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"토큰 정보 조회 실패: {str(e)}")


@app.get("/admin/users")
async def list_users():
    """사용자 목록 조회"""
    try:
        users_with_display = []
        for user_id in rate_limiter.users.keys():
            users_with_display.append({
                "user_id": user_id,
                "display_name": rate_limiter.get_display_name(user_id)
            })

        return {
            "users": users_with_display,
            "total_count": len(users_with_display)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"사용자 목록 조회 실패: {str(e)}")


if __name__ == "__main__":
    print("🇰🇷 Korean Token Limiter 시작 중...")

    # 로그 디렉토리 생성
    os.makedirs("logs", exist_ok=True)

    # 서버 실행
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8080,
        log_level="info"
    )