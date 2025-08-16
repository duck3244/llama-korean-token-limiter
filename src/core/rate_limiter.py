"""
Rate limiter for Korean token usage control
"""

import time
import asyncio
from typing import Dict, Optional, Tuple, List
from dataclasses import dataclass, asdict
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class LimitType(Enum):
    """제한 타입"""
    REQUESTS_PER_MINUTE = "rpm"
    TOKENS_PER_MINUTE = "tpm"
    TOKENS_PER_HOUR = "tph"
    DAILY_TOKEN_LIMIT = "daily"


@dataclass
class UserLimits:
    """사용자별 제한 설정"""
    rpm: int = 30  # requests per minute (한국어 모델 기본값)
    tpm: int = 5000  # tokens per minute (한국어 특성 반영)
    tph: int = 300000  # tokens per hour
    daily: int = 500000  # daily token limit
    cooldown_minutes: int = 3  # 제한 후 대기 시간 (짧게 설정)
    description: str = ""  # 사용자 설명
    
    def _asdict(self):
        return asdict(self)


@dataclass
class UsageInfo:
    """사용량 정보"""
    requests_this_minute: int = 0
    tokens_this_minute: int = 0
    tokens_this_hour: int = 0
    tokens_today: int = 0
    last_request_time: float = 0
    cooldown_until: float = 0


class KoreanRateLimiter:
    """한국어 토큰 사용량 기반 속도 제한기"""
    
    def __init__(self, storage):
        self.storage = storage
        self.user_limits: Dict[str, UserLimits] = {}
        self.default_limits = UserLimits()
        self.api_key_mapping: Dict[str, str] = {}  # API 키 -> 사용자 ID 매핑
    
    def set_user_limits(self, user_id: str, limits: UserLimits):
        """사용자별 제한 설정"""
        self.user_limits[user_id] = limits
        logger.info(f"✅ Set limits for Korean user '{user_id}': RPM={limits.rpm}, TPM={limits.tpm}")
    
    def set_api_key_mapping(self, api_key: str, user_id: str):
        """API 키와 사용자 ID 매핑 설정"""
        self.api_key_mapping[api_key] = user_id
        logger.debug(f"✅ Mapped API key to user: {api_key[:8]}... -> {user_id}")
    
    def get_user_from_api_key(self, api_key: str) -> str:
        """API 키로부터 사용자 ID 조회"""
        return self.api_key_mapping.get(api_key, api_key)
    
    def get_user_limits(self, user_id: str) -> UserLimits:
        """사용자 제한 설정 조회"""
        return self.user_limits.get(user_id, self.default_limits)
    
    async def check_limit(self, user_id: str, estimated_tokens: int) -> Tuple[bool, Optional[str]]:
        """사용량 제한 확인 (한국어 메시지)"""
        try:
            limits = self.get_user_limits(user_id)
            current_time = time.time()
            
            # 현재 사용량 조회
            usage = await self.storage.get_user_usage(user_id)
            
            # 쿨다운 상태 확인
            cooldown_until = usage.get('cooldown_until', 0)
            if cooldown_until > current_time:
                remaining_cooldown = int(cooldown_until - current_time)
                return False, f"🚫 쿨다운 중입니다. {remaining_cooldown}초 후 다시 시도하세요."
            
            # 분당 요청 수 확인
            current_requests = usage.get('requests_this_minute', 0)
            if current_requests >= limits.rpm:
                await self._apply_cooldown(user_id, limits.cooldown_minutes)
                return False, f"⏰ 분당 요청 제한 초과 ({limits.rpm}개). {limits.cooldown_minutes}분 후 다시 시도하세요."
            
            # 분당 토큰 수 확인
            current_minute_tokens = usage.get('tokens_this_minute', 0)
            if current_minute_tokens + estimated_tokens > limits.tpm:
                await self._apply_cooldown(user_id, limits.cooldown_minutes)
                return False, f"🔢 분당 토큰 제한 초과 ({limits.tpm:,}개). 현재: {current_minute_tokens:,}, 요청: {estimated_tokens:,}"
            
            # 시간당 토큰 수 확인
            current_hour_tokens = usage.get('tokens_this_hour', 0)
            if current_hour_tokens + estimated_tokens > limits.tph:
                await self._apply_cooldown(user_id, limits.cooldown_minutes)
                return False, f"⏳ 시간당 토큰 제한 초과 ({limits.tph:,}개). 현재: {current_hour_tokens:,}, 요청: {estimated_tokens:,}"
            
            # 일일 토큰 수 확인
            current_daily_tokens = usage.get('tokens_today', 0)
            if current_daily_tokens + estimated_tokens > limits.daily:
                await self._apply_cooldown(user_id, limits.cooldown_minutes * 2)  # 일일 제한은 더 긴 쿨다운
                return False, f"📅 일일 토큰 제한 초과 ({limits.daily:,}개). 현재: {current_daily_tokens:,}, 요청: {estimated_tokens:,}"
            
            return True, None
            
        except Exception as e:
            logger.error(f"❌ Rate limit check failed for Korean user {user_id}: {e}")
            # 에러 시 허용 (fail-open 정책)
            return True, None
    
    async def _apply_cooldown(self, user_id: str, cooldown_minutes: int):
        """쿨다운 적용"""
        cooldown_until = time.time() + (cooldown_minutes * 60)
        await self.storage.set_user_cooldown(user_id, cooldown_until)
        logger.warning(f"⚠️ Applied {cooldown_minutes}min cooldown for Korean user '{user_id}'")
    
    async def record_usage(self, user_id: str, input_tokens: int, output_tokens: int, requests: int = 1):
        """사용량 기록 (추정치)"""
        try:
            total_tokens = input_tokens + output_tokens
            await self.storage.record_usage(user_id, total_tokens, requests)
            
            logger.debug(f"📊 Recorded usage for Korean user '{user_id}': {input_tokens}+{output_tokens}={total_tokens} tokens, {requests} requests")
            
        except Exception as e:
            logger.error(f"❌ Usage recording failed for Korean user {user_id}: {e}")
    
    async def update_actual_usage(self, user_id: str, actual_input: int, actual_output: int):
        """실제 사용량으로 업데이트"""
        try:
            # 추정치와 실제값의 차이를 계산하여 조정
            await self.storage.update_actual_tokens(user_id, actual_input, actual_output)
            
            logger.debug(f"🔄 Updated actual usage for Korean user '{user_id}': {actual_input}+{actual_output}={actual_input + actual_output} tokens")
            
        except Exception as e:
            logger.error(f"❌ Actual usage update failed for Korean user {user_id}: {e}")
    
    async def get_user_status(self, user_id: str) -> Dict:
        """사용자 상태 조회 (한국어 사용자명 지원)"""
        try:
            usage = await self.storage.get_user_usage(user_id)
            limits = self.get_user_limits(user_id)
            current_time = time.time()
            
            # 남은 할당량 계산
            remaining_rpm = max(0, limits.rpm - usage.get('requests_this_minute', 0))
            remaining_tpm = max(0, limits.tpm - usage.get('tokens_this_minute', 0))
            remaining_tph = max(0, limits.tph - usage.get('tokens_this_hour', 0))
            remaining_daily = max(0, limits.daily - usage.get('tokens_today', 0))
            
            # 쿨다운 상태
            cooldown_until = usage.get('cooldown_until', 0)
            is_cooldown = cooldown_until > current_time
            cooldown_remaining = max(0, int(cooldown_until - current_time)) if is_cooldown else 0
            
            # 사용률 계산
            rpm_percent = (usage.get('requests_this_minute', 0) / limits.rpm) * 100 if limits.rpm > 0 else 0
            tpm_percent = (usage.get('tokens_this_minute', 0) / limits.tpm) * 100 if limits.tpm > 0 else 0
            tph_percent = (usage.get('tokens_this_hour', 0) / limits.tph) * 100 if limits.tph > 0 else 0
            daily_percent = (usage.get('tokens_today', 0) / limits.daily) * 100 if limits.daily > 0 else 0
            
            return {
                'user_id': user_id,
                'user_type': 'korean_user',
                'limits': limits._asdict(),
                'usage': usage,
                'remaining': {
                    'requests_this_minute': remaining_rpm,
                    'tokens_this_minute': remaining_tpm,
                    'tokens_this_hour': remaining_tph,
                    'tokens_today': remaining_daily
                },
                'cooldown': {
                    'is_active': is_cooldown,
                    'remaining_seconds': cooldown_remaining,
                    'status_message': f"쿨다운 {cooldown_remaining}초 남음" if is_cooldown else "정상"
                },
                'utilization': {
                    'rpm_percent': round(rpm_percent, 1),
                    'tpm_percent': round(tpm_percent, 1),
                    'tph_percent': round(tph_percent, 1),
                    'daily_percent': round(daily_percent, 1)
                },
                'status_summary': self._get_status_summary(rpm_percent, tpm_percent, tph_percent, daily_percent, is_cooldown)
            }
        
        except Exception as e:
            logger.error(f"❌ User status retrieval failed for Korean user {user_id}: {e}")
            return {
                'user_id': user_id,
                'error': f"통계 조회 실패: {str(e)}"
            }
    
    def _get_status_summary(self, rpm_percent: float, tpm_percent: float, tph_percent: float, daily_percent: float, is_cooldown: bool) -> str:
        """상태 요약 메시지 생성 (한국어)"""
        if is_cooldown:
            return "🚫 쿨다운 중"
        
        max_usage = max(rpm_percent, tpm_percent, tph_percent, daily_percent)
        
        if max_usage >= 90:
            return "🔴 위험 (90% 이상 사용)"
        elif max_usage >= 70:
            return "🟡 주의 (70% 이상 사용)"
        elif max_usage >= 50:
            return "🟢 보통 (50% 이상 사용)"
        else:
            return "🔵 여유 (50% 미만 사용)"
    
    async def reset_user_usage(self, user_id: str):
        """사용자 사용량 초기화"""
        try:
            await self.storage.reset_user_usage(user_id)
            logger.info(f"🔄 Reset usage for Korean user '{user_id}'")
        except Exception as e:
            logger.error(f"❌ Usage reset failed for Korean user {user_id}: {e}")
            raise
    
    def set_default_limits(self, limits: UserLimits):
        """기본 제한 설정"""
        self.default_limits = limits
        logger.info(f"✅ Set default Korean limits: {limits}")
    
    async def cleanup_expired_data(self):
        """만료된 데이터 정리 (백그라운드 태스크용)"""
        try:
            await self.storage.cleanup_expired_data()
            logger.debug("🧹 Cleaned up expired Korean usage data")
        except Exception as e:
            logger.error(f"❌ Data cleanup failed: {e}")
    
    async def get_top_users(self, limit: int = 10, period: str = "today") -> list:
        """상위 사용자 조회 (한국어 사용자명 지원)"""
        try:
            return await self.storage.get_top_users(limit, period)
        except Exception as e:
            logger.error(f"❌ Top Korean users retrieval failed: {e}")
            return []
    
    async def get_usage_statistics(self) -> Dict:
        """전체 사용량 통계 (한국어 레이블)"""
        try:
            stats = await self.storage.get_usage_statistics()
            
            # 한국어 레이블 추가
            stats['labels'] = {
                'total_users': '총 사용자 수',
                'active_users_today': '오늘 활성 사용자',
                'total_tokens_today': '오늘 총 토큰 사용량',
                'total_requests_today': '오늘 총 요청 수',
                'average_tokens_per_user': '사용자당 평균 토큰'
            }
            
            return stats
        except Exception as e:
            logger.error(f"❌ Korean usage statistics retrieval failed: {e}")
            return {}
    
    def calculate_korean_cost(self, input_tokens: int, output_tokens: int) -> Dict[str, float]:
        """한국어 모델 토큰 기반 비용 추정"""
        # 한국어 모델 가상 가격 (실제 서비스 시 조정 필요)
        # 1B 모델이므로 상대적으로 저렴하게 설정
        pricing = {
            'input_per_1k': 0.0005,   # 입력 토큰 1000개당 USD
            'output_per_1k': 0.001,   # 출력 토큰 1000개당 USD
        }
        
        input_cost = (input_tokens / 1000) * pricing['input_per_1k']
        output_cost = (output_tokens / 1000) * pricing['output_per_1k']
        total_cost = input_cost + output_cost
        
        return {
            'input_cost_usd': round(input_cost, 6),
            'output_cost_usd': round(output_cost, 6),
            'total_cost_usd': round(total_cost, 6),
            'input_cost_krw': round(input_cost * 1300, 2),  # 원화 환산 (가정)
            'output_cost_krw': round(output_cost * 1300, 2),
            'total_cost_krw': round(total_cost * 1300, 2)
        }
    
    async def get_user_history(self, user_id: str, limit: int = 100) -> List[Dict]:
        """사용자 사용량 히스토리 조회"""
        try:
            return await self.storage.get_user_history(user_id, limit)
        except Exception as e:
            logger.error(f"❌ User history retrieval failed for {user_id}: {e}")
            return []
    
    def validate_korean_user_id(self, user_id: str) -> bool:
        """한국어 사용자 ID 유효성 검사"""
        if not user_id or len(user_id) > 50:
            return False
        
        # 한국어, 영어, 숫자, 일부 특수문자 허용
        import re
        pattern = "r'^[가-힣a-zA-Z0-9_\-\.]+"
        return bool(re.match(pattern, user_id))
    
    async def bulk_update_limits(self, user_limits_dict: Dict[str, UserLimits]):
        """여러 사용자 제한 일괄 업데이트"""
        updated_count = 0
        for user_id, limits in user_limits_dict.items():
            try:
                self.set_user_limits(user_id, limits)
                updated_count += 1
            except Exception as e:
                logger.error(f"❌ Failed to update limits for {user_id}: {e}")
        
        logger.info(f"✅ Bulk updated limits for {updated_count} Korean users")
        return updated_count


# 호환성을 위한 별칭
RateLimiter = KoreanRateLimiter