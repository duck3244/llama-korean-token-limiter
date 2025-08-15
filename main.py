#!/usr/bin/env python3
"""
Korean Llama Token Limiter - 한국어 특화 메인 애플리케이션
"""

import asyncio
import json
import time
import logging
import yaml
from contextlib import asynccontextmanager
from typing import Dict, Any

import httpx
import uvicorn
from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

# 한국어 특화 컴포넌트 import
from src.core.korean_token_counter import KoreanTokenCounter
from src.core.rate_limiter import KoreanRateLimiter, UserLimits
from src.core.config import Config
from src.storage.redis_storage import RedisStorage
from src.storage.sqlite_storage import SQLiteStorage

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('logs/korean_token_limiter.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

# 글로벌 변수
config = None
storage = None
token_counter = None
rate_limiter = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """애플리케이션 시작/종료"""
    global config, storage, token_counter, rate_limiter
    
    logger.info("🇰🇷 Korean Token Limiter 시작 중...")
    
    try:
        # 설정 로드
        config = Config()
        logger.info(f"✅ Configuration loaded: {config.model_name}")
        
        # 저장소 초기화
        if config.use_redis:
            storage = RedisStorage(config.redis_url)
            if not await storage.ping():
                raise Exception("Redis connection failed")
            logger.info("✅ Redis storage initialized")
        else:
            storage = SQLiteStorage(config.sqlite_path)
            logger.info("✅ SQLite storage initialized")
        
        # 한국어 토큰 카운터 초기화
        token_counter = KoreanTokenCounter(
            model_name=config.model_name,
            korean_factor=config.korean_factor
        )
        logger.info(f"✅ Korean token counter initialized: {token_counter.get_tokenizer_info()}")
        
        # 속도 제한기 초기화
        rate_limiter = KoreanRateLimiter(storage)
        rate_limiter.set_default_limits(UserLimits(**config.get_default_limits()))
        
        # 한국어 사용자 설정 로드
        await load_korean_users()
        
        # LLM 서버 연결 확인
        await check_llm_server_connection()
        
        logger.info("✅ Korean Token Limiter 초기화 완료")
        
    except Exception as e:
        logger.error(f"❌ Initialization failed: {e}")
        raise
    
    yield
    
    # 정리 작업
    logger.info("🛑 Korean Token Limiter 종료 중...")
    if storage:
        await storage.close()
    logger.info("✅ Korean Token Limiter 종료 완료")


app = FastAPI(
    title="🇰🇷 Korean Llama Token Limiter",
    description="한국어 Llama 모델용 토큰 사용량 제한 시스템",
    version="1.0.0-korean",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def load_korean_users():
    """한국어 사용자 설정 로드"""
    try:
        with open('config/korean_users.yaml', 'r', encoding='utf-8') as f:
            users_config = yaml.safe_load(f)
        
        # API 키 매핑 로드
        api_key_mapping = users_config.get('api_keys', {})
        
        # 사용자별 제한 설정
        for user_id, limits_config in users_config.get('users', {}).items():
            # description 필드 제외하고 UserLimits 생성
            limits_data = {k: v for k, v in limits_config.items() if k != 'description'}
            limits = UserLimits(**limits_data)
            rate_limiter.set_user_limits(user_id, limits)
        
        # API 키 매핑 설정
        for api_key, user_id in api_key_mapping.items():
            rate_limiter.set_api_key_mapping(api_key, user_id)
        
        logger.info(f"✅ Korean users loaded: {len(users_config.get('users', {}))} users, {len(api_key_mapping)} API keys")
        
    except FileNotFoundError:
        logger.warning("⚠️ korean_users.yaml not found, using default settings")
    except Exception as e:
        logger.error(f"❌ Failed to load Korean users: {e}")


async def check_llm_server_connection():
    """LLM 서버 연결 확인"""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(f"{config.llm_server_url}/health")
            if response.status_code == 200:
                logger.info("✅ LLM server connection verified")
            else:
                logger.warning(f"⚠️ LLM server returned status {response.status_code}")
    except Exception as e:
        logger.warning(f"⚠️ LLM server connection check failed: {e}")


def extract_korean_user_id(request: Request) -> str:
    """한국어 사용자 ID 추출"""
    # Authorization 헤더에서 API 키 추출
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        api_key = auth_header[7:]
        
        # API 키를 사용자 ID로 매핑
        user_id = rate_limiter.get_user_from_api_key(api_key)
        return user_id
    
    # X-User-ID 헤더 (한국어 지원)
    user_id = request.headers.get("x-user-id")
    if user_id:
        return user_id
    
    # X-API-Key 헤더
    api_key = request.headers.get("x-api-key")
    if api_key:
        return rate_limiter.get_user_from_api_key(api_key)
    
    return "게스트"


@app.middleware("http")
async def korean_token_limit_middleware(request: Request, call_next):
    """한국어 특화 토큰 제한 미들웨어"""
    
    # LLM API 경로가 아니면 통과
    if not any(path in request.url.path for path in ["/v1/chat/completions", "/v1/completions", "/chat/completions", "/completions"]):
        return await call_next(request)
    
    user_id = extract_korean_user_id(request)
    
    # 요청 본문 읽기
    body = await request.body()
    
    try:
        request_data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        return JSONResponse(
            status_code=400,
            content={"error": "잘못된 JSON 형식입니다", "message": "Invalid JSON format"}
        )
    
    # 한국어 토큰 계산
    token_info = token_counter.count_request_tokens(request_data)
    estimated_total = token_info['estimated_total']
    
    # 제한 확인
    allowed, reason = await rate_limiter.check_limit(user_id, estimated_total)
    
    if not allowed:
        logger.warning(f"🚫 Rate limit exceeded for user '{user_id}': {reason}")
        return JSONResponse(
            status_code=429,
            content={
                "error": {
                    "message": reason,
                    "type": "rate_limit_exceeded_korean",
                    "code": "한국어_속도_제한",
                    "user_id": user_id,
                    "estimated_tokens": estimated_total
                }
            }
        )
    
    # 사용량 기록 (추정치)
    await rate_limiter.record_usage(
        user_id, 
        token_info['input_tokens'], 
        0,  # 출력 토큰은 응답 후 업데이트
        1   # 요청 수
    )
    
    # 요청 본문 복원
    async def receive():
        return {"type": "http.request", "body": body}
    
    request._receive = receive
    
    # 요청 처리
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    
    # 응답 헤더에 처리 시간 추가
    response.headers["X-Process-Time"] = str(process_time)
    response.headers["X-User-ID"] = user_id
    
    logger.info(f"✅ Processed request for Korean user '{user_id}' in {process_time:.3f}s")
    
    return response


@app.post("/v1/chat/completions")
@app.post("/v1/completions")
@app.post("/chat/completions")
@app.post("/completions")
async def korean_llm_proxy(request: Request, background_tasks: BackgroundTasks):
    """한국어 LLM 프록시"""
    
    body = await request.body()
    user_id = extract_korean_user_id(request)
    
    # 헤더 준비
    headers = dict(request.headers)
    headers.pop("host", None)
    headers.pop("content-length", None)
    
    try:
        llm_url = config.llm_server_url
        
        # vLLM/SGLang 서버로 요청 전달
        async with httpx.AsyncClient(timeout=300.0) as client:
            llm_response = await client.post(
                f"{llm_url}{request.url.path}",
                content=body,
                headers=headers
            )
        
        # 실제 토큰 사용량 업데이트
        if llm_response.status_code == 200:
            try:
                response_data = llm_response.json()
                if 'usage' in response_data:
                    actual_input = response_data['usage'].get('prompt_tokens', 0)
                    actual_output = response_data['usage'].get('completion_tokens', 0)
                    
                    # 백그라운드에서 실제 사용량으로 업데이트
                    background_tasks.add_task(
                        rate_limiter.update_actual_usage,
                        user_id, actual_input, actual_output
                    )
                    
                    logger.debug(f"📊 Actual usage for '{user_id}': {actual_input}+{actual_output}={actual_input+actual_output} tokens")
            except Exception as e:
                logger.warning(f"⚠️ Failed to parse LLM response for usage update: {e}")
        
        # 응답 반환
        response_content = llm_response.json() if llm_response.headers.get("content-type", "").startswith("application/json") else llm_response.text
        
        return JSONResponse(
            content=response_content,
            status_code=llm_response.status_code,
            headers={k: v for k, v in llm_response.headers.items() if k.lower() not in ['content-length', 'transfer-encoding']}
        )
    
    except httpx.TimeoutException:
        logger.error(f"❌ LLM server timeout for user '{user_id}'")
        return JSONResponse(
            status_code=504,
            content={"error": "LLM 서버 응답 시간 초과", "message": "LLM server timeout"}
        )
    except httpx.ConnectError:
        logger.error(f"❌ LLM server connection error for user '{user_id}'")
        return JSONResponse(
            status_code=503,
            content={"error": "LLM 서버에 연결할 수 없습니다", "message": "Cannot connect to LLM server"}
        )
    except Exception as e:
        logger.error(f"❌ Proxy error for user '{user_id}': {e}")
        return JSONResponse(
            status_code=500,
            content={"error": f"프록시 오류: {str(e)}", "message": f"Proxy error: {str(e)}"}
        )


@app.get("/health")
async def health_check():
    """시스템 상태 확인"""
    try:
        # 저장소 연결 확인
        storage_status = "healthy"
        if config.use_redis:
            if not await storage.ping():
                storage_status = "unhealthy"
        
        # 토큰 카운터 상태 확인
        tokenizer_info = token_counter.get_tokenizer_info()
        
        return {
            "status": "healthy" if storage_status == "healthy" else "unhealthy",
            "model": config.model_name,
            "storage_type": config.storage_type,
            "storage_status": storage_status,
            "tokenizer": tokenizer_info,
            "supports_korean": True,
            "timestamp": time.time()
        }
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={
                "status": "unhealthy",
                "error": str(e),
                "timestamp": time.time()
            }
        )


@app.get("/stats/{user_id}")
async def get_korean_user_stats(user_id: str):
    """한국어 사용자 통계 조회"""
    try:
        # 사용자 ID 유효성 검사
        if not rate_limiter.validate_korean_user_id(user_id):
            raise HTTPException(status_code=400, detail="잘못된 사용자 ID 형식입니다")
        
        stats = await rate_limiter.get_user_status(user_id)
        stats['model'] = config.model_name
        stats['system_type'] = 'korean_llm_limiter'
        
        return stats
    except Exception as e:
        logger.error(f"❌ Failed to get stats for Korean user '{user_id}': {e}")
        raise HTTPException(status_code=500, detail=f"통계 조회 실패: {str(e)}")


@app.get("/admin/users")
async def list_korean_users():
    """한국어 사용자 목록 조회"""
    try:
        users = await storage.get_all_users()
        
        # 각 사용자의 기본 정보 포함
        user_list = []
        for user_id in users:
            limits = rate_limiter.get_user_limits(user_id)
            user_list.append({
                "user_id": user_id,
                "limits": limits._asdict(),
                "user_type": "korean_user"
            })
        
        return {
            "users": users,
            "detailed_users": user_list,
            "total_count": len(users),
            "system_type": "korean_llm_limiter"
        }
    except Exception as e:
        logger.error(f"❌ Failed to get Korean users list: {e}")
        raise HTTPException(status_code=500, detail=f"사용자 목록 조회 실패: {str(e)}")


@app.post("/admin/reload-config")
async def reload_korean_config():
    """한국어 설정 다시 로드"""
    try:
        await load_korean_users()
        return {"message": "한국어 설정이 다시 로드되었습니다", "timestamp": time.time()}
    except Exception as e:
        logger.error(f"❌ Failed to reload Korean config: {e}")
        raise HTTPException(status_code=500, detail=f"설정 로드 실패: {str(e)}")


@app.delete("/admin/reset-usage/{user_id}")
async def reset_korean_user_usage(user_id: str):
    """한국어 사용자 사용량 초기화"""
    try:
        if not rate_limiter.validate_korean_user_id(user_id):
            raise HTTPException(status_code=400, detail="잘못된 사용자 ID 형식입니다")
        
        await rate_limiter.reset_user_usage(user_id)
        logger.info(f"🔄 Reset usage for Korean user '{user_id}'")
        
        return {"message": f"사용자 '{user_id}'의 사용량이 초기화되었습니다", "timestamp": time.time()}
    except Exception as e:
        logger.error(f"❌ Failed to reset usage for Korean user '{user_id}': {e}")
        raise HTTPException(status_code=500, detail=f"사용량 초기화 실패: {str(e)}")


@app.get("/admin/statistics")
async def get_korean_system_statistics():
    """한국어 시스템 전체 통계"""
    try:
        stats = await rate_limiter.get_usage_statistics()
        
        # 시스템 정보 추가
        if config.use_redis:
            system_info = await storage.get_korean_system_info()
            stats['system_info'] = system_info
        
        stats['model_info'] = {
            'model_name': config.model_name,
            'max_context_length': config.max_model_len,
            'korean_factor': config.korean_factor
        }
        
        return stats
    except Exception as e:
        logger.error(f"❌ Failed to get Korean system statistics: {e}")
        raise HTTPException(status_code=500, detail=f"시스템 통계 조회 실패: {str(e)}")


@app.get("/admin/top-users")
async def get_top_korean_users(limit: int = 10, period: str = "today"):
    """상위 한국어 사용자 조회"""
    try:
        if period not in ["today", "hour", "minute", "total"]:
            raise HTTPException(status_code=400, detail="잘못된 기간입니다. (today, hour, minute, total)")
        
        top_users = await rate_limiter.get_top_users(limit, period)
        
        return {
            "top_users": top_users,
            "period": period,
            "limit": limit,
            "timestamp": time.time()
        }
    except Exception as e:
        logger.error(f"❌ Failed to get top Korean users: {e}")
        raise HTTPException(status_code=500, detail=f"상위 사용자 조회 실패: {str(e)}")


@app.get("/token-info")
async def get_token_info(text: str = "안녕하세요! 한국어 토큰 계산 테스트입니다."):
    """토큰 계산 정보 (디버깅용)"""
    try:
        token_count = token_counter.count_tokens(text)
        composition = token_counter.analyze_text_composition(text)
        tokenizer_info = token_counter.get_tokenizer_info()
        
        return {
            "text": text,
            "token_count": token_count,
            "composition": composition,
            "tokenizer_info": tokenizer_info
        }
    except Exception as e:
        logger.error(f"❌ Failed to get token info: {e}")
        raise HTTPException(status_code=500, detail=f"토큰 정보 조회 실패: {str(e)}")


if __name__ == "__main__":
    # 로그 디렉토리 생성
    import os
    os.makedirs("logs", exist_ok=True)
    
    # 서버 실행
    uvicorn.run(
        "main_korean:app",
        host="0.0.0.0",
        port=8080,
        reload=False,
        log_level="info",
        access_log=True
    )