"""
Redis storage implementation for Korean token usage tracking
"""

import json
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import redis.asyncio as redis
import logging

logger = logging.getLogger(__name__)


class RedisStorage:
    """Redis 기반 한국어 사용량 저장소"""
    
    def __init__(self, redis_url: str):
        self.redis_url = redis_url
        self.redis = None
        self._connect()
    
    def _connect(self):
        """Redis 연결"""
        try:
            self.redis = redis.from_url(
                self.redis_url, 
                decode_responses=True,
                encoding='utf-8',
                socket_keepalive=True,
                socket_keepalive_options={}
            )
            logger.info(f"✅ Connected to Redis: {self.redis_url}")
        except Exception as e:
            logger.error(f"❌ Redis connection failed: {e}")
            raise
    
    async def ping(self) -> bool:
        """Redis 연결 상태 확인"""
        try:
            await self.redis.ping()
            return True
        except Exception as e:
            logger.error(f"❌ Redis ping failed: {e}")
            return False
    
    async def close(self):
        """연결 종료"""
        if self.redis:
            await self.redis.close()
            logger.info("✅ Redis connection closed")
    
    def _get_time_keys(self, user_id: str, timestamp: Optional[float] = None) -> Dict[str, str]:
        """시간대별 키 생성 (한국어 사용자 ID 지원)"""
        if timestamp is None:
            timestamp = time.time()
        
        dt = datetime.fromtimestamp(timestamp)
        
        # 한국어 사용자 ID를 위해 URL 인코딩
        encoded_user_id = user_id.encode('utf-8').hex()
        
        return {
            'minute': f"korean_usage:{encoded_user_id}:minute:{dt.strftime('%Y%m%d%H%M')}",
            'hour': f"korean_usage:{encoded_user_id}:hour:{dt.strftime('%Y%m%d%H')}",
            'day': f"korean_usage:{encoded_user_id}:day:{dt.strftime('%Y%m%d')}",
            'user_info': f"korean_user:{encoded_user_id}:info",
            'user_mapping': f"korean_mapping:{encoded_user_id}"
        }
    
    def _encode_user_id(self, user_id: str) -> str:
        """한국어 사용자 ID 인코딩"""
        return user_id.encode('utf-8').hex()
    
    def _decode_user_id(self, encoded_id: str) -> str:
        """한국어 사용자 ID 디코딩"""
        try:
            return bytes.fromhex(encoded_id).decode('utf-8')
        except:
            return encoded_id  # 디코딩 실패 시 원본 반환
    
    async def get_user_usage(self, user_id: str) -> Dict[str, int]:
        """한국어 사용자 사용량 조회"""
        try:
            keys = self._get_time_keys(user_id)
            
            # 사용자 ID 매핑 저장 (한국어 -> 인코딩된 형태)
            await self.redis.hset(keys['user_mapping'], mapping={
                'original_id': user_id,
                'encoded_id': self._encode_user_id(user_id),
                'last_access': time.time()
            })
            
            # 파이프라인으로 모든 데이터 한번에 조회
            pipe = self.redis.pipeline()
            pipe.hgetall(keys['minute'])
            pipe.hgetall(keys['hour'])
            pipe.hgetall(keys['day'])
            pipe.hgetall(keys['user_info'])
            
            results = await pipe.execute()
            minute_data, hour_data, day_data, user_info = results
            
            return {
                'requests_this_minute': int(minute_data.get('requests', 0)),
                'tokens_this_minute': int(minute_data.get('tokens', 0)),
                'tokens_this_hour': int(hour_data.get('tokens', 0)),
                'tokens_today': int(day_data.get('tokens', 0)),
                'total_requests': int(user_info.get('total_requests', 0)),
                'total_tokens': int(user_info.get('total_tokens', 0)),
                'last_request_time': float(user_info.get('last_request_time', 0)),
                'cooldown_until': float(user_info.get('cooldown_until', 0)),
                'user_type': user_info.get('user_type', 'korean_user')
            }
        
        except Exception as e:
            logger.error(f"❌ Failed to get usage for Korean user {user_id}: {e}")
            return {
                'requests_this_minute': 0,
                'tokens_this_minute': 0,
                'tokens_this_hour': 0,
                'tokens_today': 0,
                'total_requests': 0,
                'total_tokens': 0,
                'last_request_time': 0,
                'cooldown_until': 0,
                'user_type': 'korean_user'
            }
    
    async def record_usage(self, user_id: str, tokens: int, requests: int = 1):
        """한국어 사용자 사용량 기록"""
        try:
            current_time = time.time()
            keys = self._get_time_keys(user_id, current_time)
            
            # 파이프라인으로 모든 업데이트를 원자적으로 실행
            pipe = self.redis.pipeline()
            
            # 시간대별 사용량 증가
            pipe.hincrby(keys['minute'], 'tokens', tokens)
            pipe.hincrby(keys['minute'], 'requests', requests)
            pipe.hincrby(keys['hour'], 'tokens', tokens)
            pipe.hincrby(keys['day'], 'tokens', tokens)
            
            # 사용자 전체 통계 업데이트
            pipe.hincrby(keys['user_info'], 'total_tokens', tokens)
            pipe.hincrby(keys['user_info'], 'total_requests', requests)
            pipe.hset(keys['user_info'], mapping={
                'last_request_time': current_time,
                'user_type': 'korean_user',
                'original_user_id': user_id
            })
            
            # TTL 설정 (한국어 사용자 데이터는 조금 더 길게 보관)
            pipe.expire(keys['minute'], 3600)     # 1시간
            pipe.expire(keys['hour'], 86400)      # 1일
            pipe.expire(keys['day'], 604800)      # 1주일
            pipe.expire(keys['user_info'], 2592000)  # 30일
            pipe.expire(keys['user_mapping'], 2592000)  # 30일
            
            await pipe.execute()
            
            # 사용량 히스토리 저장 (선택사항)
            await self._record_korean_usage_history(user_id, tokens, requests, current_time)
            
            logger.debug(f"📊 Recorded Korean usage: {user_id} -> {tokens} tokens, {requests} requests")
            
        except Exception as e:
            logger.error(f"❌ Failed to record usage for Korean user {user_id}: {e}")
            raise
    
    async def _record_korean_usage_history(self, user_id: str, tokens: int, requests: int, timestamp: float):
        """한국어 사용자 사용량 히스토리 저장"""
        try:
            encoded_user_id = self._encode_user_id(user_id)
            history_key = f"korean_history:{encoded_user_id}:usage"
            
            history_data = {
                'timestamp': timestamp,
                'tokens': tokens,
                'requests': requests,
                'user_id': user_id,  # 원본 한국어 ID 저장
                'date': datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')
            }
            
            # 리스트에 추가 (최근 1000개만 유지)
            pipe = self.redis.pipeline()
            pipe.lpush(history_key, json.dumps(history_data, ensure_ascii=False))
            pipe.ltrim(history_key, 0, 999)  # 최근 1000개만 유지
            pipe.expire(history_key, 604800)  # 1주일
            await pipe.execute()
            
        except Exception as e:
            logger.debug(f"❌ Failed to record Korean usage history: {e}")
    
    async def update_actual_tokens(self, user_id: str, actual_input: int, actual_output: int):
        """실제 토큰 사용량으로 업데이트"""
        try:
            actual_total = actual_input + actual_output
            current_time = time.time()
            encoded_user_id = self._encode_user_id(user_id)
            
            # 실제 사용량 기록
            adjustment_key = f"korean_actual:{encoded_user_id}:tokens"
            await self.redis.hset(adjustment_key, mapping={
                'last_actual_input': actual_input,
                'last_actual_output': actual_output,
                'last_actual_total': actual_total,
                'updated_at': current_time,
                'original_user_id': user_id
            })
            await self.redis.expire(adjustment_key, 3600)  # 1시간
            
            logger.debug(f"🔄 Updated actual tokens for Korean user {user_id}: {actual_total}")
            
        except Exception as e:
            logger.error(f"❌ Failed to update actual tokens for Korean user {user_id}: {e}")
    
    async def set_user_cooldown(self, user_id: str, cooldown_until: float):
        """한국어 사용자 쿨다운 설정"""
        try:
            keys = self._get_time_keys(user_id)
            await self.redis.hset(keys['user_info'], mapping={
                'cooldown_until': cooldown_until,
                'cooldown_set_at': time.time(),
                'user_type': 'korean_user'
            })
            await self.redis.expire(keys['user_info'], 2592000)  # 30일
            
            logger.info(f"⏰ Set cooldown for Korean user '{user_id}' until {cooldown_until}")
            
        except Exception as e:
            logger.error(f"❌ Failed to set cooldown for Korean user {user_id}: {e}")
    
    async def reset_user_usage(self, user_id: str):
        """한국어 사용자 사용량 초기화"""
        try:
            keys = self._get_time_keys(user_id)
            
            # 현재 시간 기준 키들 삭제
            await self.redis.delete(
                keys['minute'],
                keys['hour'],
                keys['day']
            )
            
            # 쿨다운 해제
            await self.redis.hdel(keys['user_info'], 'cooldown_until', 'cooldown_set_at')
            
            logger.info(f"🔄 Reset usage for Korean user '{user_id}'")
            
        except Exception as e:
            logger.error(f"❌ Failed to reset usage for Korean user {user_id}: {e}")
            raise
    
    async def get_all_users(self) -> List[str]:
        """모든 한국어 사용자 목록 조회"""
        try:
            # korean_user:*:info 패턴으로 사용자 찾기
            pattern = "korean_user:*:info"
            keys = await self.redis.keys(pattern)
            
            users = []
            for key in keys:
                # "korean_user:encoded_id:info" 형태에서 encoded_id 추출
                parts = key.split(':')
                if len(parts) >= 3:
                    encoded_id = parts[1]
                    original_id = self._decode_user_id(encoded_id)
                    users.append(original_id)
            
            # 중복 제거
            users = list(set(users))
            
            logger.debug(f"📋 Found {len(users)} Korean users")
            return users
            
        except Exception as e:
            logger.error(f"❌ Failed to get all Korean users: {e}")
            return []
    
    async def get_top_users(self, limit: int = 10, period: str = "today") -> List[Dict]:
        """상위 한국어 사용자 조회"""
        try:
            users = await self.get_all_users()
            user_stats = []
            
            for user_id in users:
                usage = await self.get_user_usage(user_id)
                
                if period == "today":
                    tokens = usage['tokens_today']
                elif period == "hour":
                    tokens = usage['tokens_this_hour']
                elif period == "minute":
                    tokens = usage['tokens_this_minute']
                else:
                    tokens = usage['total_tokens']
                
                user_stats.append({
                    'user_id': user_id,
                    'tokens': tokens,
                    'requests': usage.get('total_requests', 0),
                    'user_type': 'korean_user'
                })
            
            # 토큰 수로 정렬
            user_stats.sort(key=lambda x: x['tokens'], reverse=True)
            return user_stats[:limit]
            
        except Exception as e:
            logger.error(f"❌ Failed to get top Korean users: {e}")
            return []
    
    async def get_usage_statistics(self) -> Dict:
        """전체 한국어 사용량 통계"""
        try:
            users = await self.get_all_users()
            
            total_users = len(users)
            total_tokens_today = 0
            total_requests_today = 0
            active_users_today = 0
            
            for user_id in users:
                usage = await self.get_user_usage(user_id)
                tokens_today = usage['tokens_today']
                
                total_tokens_today += tokens_today
                if tokens_today > 0:
                    active_users_today += 1
                
                # 오늘의 요청 수는 근사치로 계산
                if usage['tokens_this_minute'] > 0:
                    total_requests_today += usage.get('total_requests', 0)
            
            return {
                'total_users': total_users,
                'active_users_today': active_users_today,
                'total_tokens_today': total_tokens_today,
                'total_requests_today': total_requests_today,
                'average_tokens_per_user': total_tokens_today / max(active_users_today, 1),
                'timestamp': time.time(),
                'system_type': 'korean_llm_limiter'
            }
            
        except Exception as e:
            logger.error(f"❌ Failed to get Korean usage statistics: {e}")
            return {}
    
    async def cleanup_expired_data(self):
        """만료된 한국어 데이터 정리"""
        try:
            # 한국어 히스토리 키들 찾기
            pattern = "korean_history:*:usage"
            keys = await self.redis.keys(pattern)
            
            cleanup_count = 0
            for key in keys:
                ttl = await self.redis.ttl(key)
                if ttl == -1:  # TTL이 설정되지 않은 키
                    await self.redis.expire(key, 604800)  # 1주일 TTL 설정
                    cleanup_count += 1
            
            if cleanup_count > 0:
                logger.info(f"🧹 Set TTL for {cleanup_count} Korean history keys")
                
        except Exception as e:
            logger.error(f"❌ Failed to cleanup expired Korean data: {e}")
    
    async def get_user_history(self, user_id: str, limit: int = 100) -> List[Dict]:
        """한국어 사용자 사용량 히스토리 조회"""
        try:
            encoded_user_id = self._encode_user_id(user_id)
            history_key = f"korean_history:{encoded_user_id}:usage"
            
            # 최근 limit개 기록 조회
            history_data = await self.redis.lrange(history_key, 0, limit - 1)
            
            history = []
            for data_str in history_data:
                try:
                    data = json.loads(data_str)
                    history.append(data)
                except json.JSONDecodeError:
                    continue
            
            return history
            
        except Exception as e:
            logger.error(f"❌ Failed to get Korean user history for {user_id}: {e}")
            return []
    
    async def get_korean_system_info(self) -> Dict:
        """한국어 시스템 정보 조회"""
        try:
            info = await self.redis.info()
            
            # Redis 메모리 사용량
            used_memory = info.get('used_memory_human', 'Unknown')
            connected_clients = info.get('connected_clients', 0)
            
            # 한국어 키 개수
            korean_keys = 0
            patterns = ['korean_usage:*', 'korean_user:*', 'korean_history:*', 'korean_mapping:*']
            for pattern in patterns:
                keys = await self.redis.keys(pattern)
                korean_keys += len(keys)
            
            return {
                'redis_memory_used': used_memory,
                'connected_clients': connected_clients,
                'korean_keys_count': korean_keys,
                'system_status': 'healthy',
                'encoding': 'utf-8',
                'supports_korean': True
            }
            
        except Exception as e:
            logger.error(f"❌ Failed to get Korean system info: {e}")
            return {
                'system_status': 'error',
                'error': str(e)
            }
