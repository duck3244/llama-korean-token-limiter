"""
SQLite storage implementation for Korean token usage tracking
"""

import aiosqlite
import json
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging

logger = logging.getLogger(__name__)


class SQLiteStorage:
    """SQLite 기반 한국어 사용량 저장소"""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self._initialized = False

    async def _ensure_initialized(self):
        """데이터베이스 초기화 확인"""
        if not self._initialized:
            await self._init_db()
            self._initialized = True

    async def _init_db(self):
        """데이터베이스 테이블 생성"""
        try:
            async with aiosqlite.connect(self.db_path) as db:
                # 한국어 사용자 정보 테이블
                await db.execute("""
                    CREATE TABLE IF NOT EXISTS korean_users (
                        user_id TEXT PRIMARY KEY,
                        user_type TEXT DEFAULT 'korean_user',
                        total_tokens INTEGER DEFAULT 0,
                        total_requests INTEGER DEFAULT 0,
                        last_request_time REAL DEFAULT 0,
                        cooldown_until REAL DEFAULT 0,
                        created_at REAL DEFAULT 0,
                        updated_at REAL DEFAULT 0
                    )
                """)

                # 시간별 사용량 테이블
                await db.execute("""
                    CREATE TABLE IF NOT EXISTS korean_usage_by_time (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id TEXT NOT NULL,
                        time_key TEXT NOT NULL,
                        time_type TEXT NOT NULL,  -- 'minute', 'hour', 'day'
                        tokens INTEGER DEFAULT 0,
                        requests INTEGER DEFAULT 0,
                        timestamp REAL NOT NULL,
                        UNIQUE(user_id, time_key, time_type)
                    )
                """)

                # 사용량 히스토리 테이블
                await db.execute("""
                    CREATE TABLE IF NOT EXISTS korean_usage_history (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        user_id TEXT NOT NULL,
                        tokens INTEGER NOT NULL,
                        requests INTEGER NOT NULL,
                        timestamp REAL NOT NULL,
                        date_str TEXT NOT NULL,
                        additional_data TEXT  -- JSON 형태의 추가 데이터
                    )
                """)

                # 인덱스 생성
                await db.execute(
                    "CREATE INDEX IF NOT EXISTS idx_korean_usage_user_time ON korean_usage_by_time(user_id, time_key)")
                await db.execute(
                    "CREATE INDEX IF NOT EXISTS idx_korean_history_user_time ON korean_usage_history(user_id, timestamp)")
                await db.execute("CREATE INDEX IF NOT EXISTS idx_korean_users_updated ON korean_users(updated_at)")

                await db.commit()
                logger.info(f"✅ SQLite Korean database initialized: {self.db_path}")

        except Exception as e:
            logger.error(f"❌ Failed to initialize Korean SQLite database: {e}")
            raise

    async def ping(self) -> bool:
        """데이터베이스 연결 상태 확인"""
        try:
            await self._ensure_initialized()
            async with aiosqlite.connect(self.db_path) as db:
                await db.execute("SELECT 1")
            return True
        except Exception as e:
            logger.error(f"❌ SQLite ping failed: {e}")
            return False

    async def close(self):
        """연결 종료 (SQLite는 자동으로 닫힘)"""
        logger.info("✅ SQLite connection closed")

    def _get_time_keys(self, timestamp: Optional[float] = None) -> Dict[str, str]:
        """시간대별 키 생성"""
        if timestamp is None:
            timestamp = time.time()

        dt = datetime.fromtimestamp(timestamp)

        return {
            'minute': dt.strftime('%Y%m%d%H%M'),
            'hour': dt.strftime('%Y%m%d%H'),
            'day': dt.strftime('%Y%m%d')
        }

    async def get_user_usage(self, user_id: str) -> Dict[str, int]:
        """한국어 사용자 사용량 조회"""
        try:
            await self._ensure_initialized()

            current_time = time.time()
            time_keys = self._get_time_keys(current_time)

            async with aiosqlite.connect(self.db_path) as db:
                # 사용자 기본 정보 조회
                cursor = await db.execute("""
                    SELECT total_tokens, total_requests, last_request_time, cooldown_until
                    FROM korean_users WHERE user_id = ?
                """, (user_id,))
                user_row = await cursor.fetchone()

                if user_row:
                    total_tokens, total_requests, last_request_time, cooldown_until = user_row
                else:
                    total_tokens, total_requests, last_request_time, cooldown_until = 0, 0, 0, 0

                # 시간별 사용량 조회
                usage_data = {}
                for time_type, time_key in time_keys.items():
                    cursor = await db.execute("""
                        SELECT tokens, requests FROM korean_usage_by_time 
                        WHERE user_id = ? AND time_key = ? AND time_type = ?
                    """, (user_id, time_key, time_type))
                    row = await cursor.fetchone()

                    if row:
                        tokens, requests = row
                        usage_data[f'tokens_this_{time_type}'] = tokens
                        if time_type == 'minute':
                            usage_data['requests_this_minute'] = requests
                    else:
                        usage_data[f'tokens_this_{time_type}'] = 0
                        if time_type == 'minute':
                            usage_data['requests_this_minute'] = 0

                return {
                    'requests_this_minute': usage_data.get('requests_this_minute', 0),
                    'tokens_this_minute': usage_data.get('tokens_this_minute', 0),
                    'tokens_this_hour': usage_data.get('tokens_this_hour', 0),
                    'tokens_today': usage_data.get('tokens_this_day', 0),
                    'total_requests': total_requests,
                    'total_tokens': total_tokens,
                    'last_request_time': last_request_time,
                    'cooldown_until': cooldown_until,
                    'user_type': 'korean_user'
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
            await self._ensure_initialized()

            current_time = time.time()
            time_keys = self._get_time_keys(current_time)

            async with aiosqlite.connect(self.db_path) as db:
                # 사용자 기본 정보 업데이트
                await db.execute("""
                    INSERT INTO korean_users (user_id, total_tokens, total_requests, last_request_time, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET
                        total_tokens = total_tokens + ?,
                        total_requests = total_requests + ?,
                        last_request_time = ?,
                        updated_at = ?
                """, (user_id, tokens, requests, current_time, current_time, current_time,
                      tokens, requests, current_time, current_time))

                # 시간별 사용량 업데이트
                for time_type, time_key in time_keys.items():
                    await db.execute("""
                        INSERT INTO korean_usage_by_time (user_id, time_key, time_type, tokens, requests, timestamp)
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(user_id, time_key, time_type) DO UPDATE SET
                            tokens = tokens + ?,
                            requests = requests + ?,
                            timestamp = ?
                    """, (user_id, time_key, time_type, tokens, requests if time_type == 'minute' else 0, current_time,
                          tokens, requests if time_type == 'minute' else 0, current_time))

                # 사용량 히스토리 기록
                await db.execute("""
                    INSERT INTO korean_usage_history (user_id, tokens, requests, timestamp, date_str)
                    VALUES (?, ?, ?, ?, ?)
                """, (user_id, tokens, requests, current_time,
                      datetime.fromtimestamp(current_time).strftime('%Y-%m-%d %H:%M:%S')))

                await db.commit()

                logger.debug(f"📊 Recorded Korean usage: {user_id} -> {tokens} tokens, {requests} requests")

        except Exception as e:
            logger.error(f"❌ Failed to record usage for Korean user {user_id}: {e}")
            raise

    async def update_actual_tokens(self, user_id: str, actual_input: int, actual_output: int):
        """실제 토큰 사용량으로 업데이트"""
        try:
            await self._ensure_initialized()

            actual_total = actual_input + actual_output
            current_time = time.time()

            # 추가 데이터로 실제 토큰 정보 저장
            additional_data = json.dumps({
                'actual_input': actual_input,
                'actual_output': actual_output,
                'actual_total': actual_total,
                'updated_at': current_time
            }, ensure_ascii=False)

            async with aiosqlite.connect(self.db_path) as db:
                await db.execute("""
                    INSERT INTO korean_usage_history (user_id, tokens, requests, timestamp, date_str, additional_data)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (user_id, actual_total, 0, current_time,
                      datetime.fromtimestamp(current_time).strftime('%Y-%m-%d %H:%M:%S'),
                      additional_data))

                await db.commit()

                logger.debug(f"🔄 Updated actual tokens for Korean user {user_id}: {actual_total}")

        except Exception as e:
            logger.error(f"❌ Failed to update actual tokens for Korean user {user_id}: {e}")

    async def set_user_cooldown(self, user_id: str, cooldown_until: float):
        """한국어 사용자 쿨다운 설정"""
        try:
            await self._ensure_initialized()

            current_time = time.time()

            async with aiosqlite.connect(self.db_path) as db:
                await db.execute("""
                    INSERT INTO korean_users (user_id, cooldown_until, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET
                        cooldown_until = ?,
                        updated_at = ?
                """, (user_id, cooldown_until, current_time, current_time,
                      cooldown_until, current_time))

                await db.commit()

                logger.info(f"⏰ Set cooldown for Korean user '{user_id}' until {cooldown_until}")

        except Exception as e:
            logger.error(f"❌ Failed to set cooldown for Korean user {user_id}: {e}")

    async def reset_user_usage(self, user_id: str):
        """한국어 사용자 사용량 초기화"""
        try:
            await self._ensure_initialized()

            current_time = time.time()

            async with aiosqlite.connect(self.db_path) as db:
                # 현재 시간 기준 시간별 사용량 삭제
                time_keys = self._get_time_keys(current_time)
                for time_type, time_key in time_keys.items():
                    await db.execute("""
                        DELETE FROM korean_usage_by_time 
                        WHERE user_id = ? AND time_key = ? AND time_type = ?
                    """, (user_id, time_key, time_type))

                # 쿨다운 해제
                await db.execute("""
                    UPDATE korean_users SET cooldown_until = 0, updated_at = ?
                    WHERE user_id = ?
                """, (current_time, user_id))

                await db.commit()

                logger.info(f"🔄 Reset usage for Korean user '{user_id}'")

        except Exception as e:
            logger.error(f"❌ Failed to reset usage for Korean user {user_id}: {e}")
            raise

    async def get_all_users(self) -> List[str]:
        """모든 한국어 사용자 목록 조회"""
        try:
            await self._ensure_initialized()

            async with aiosqlite.connect(self.db_path) as db:
                cursor = await db.execute("SELECT user_id FROM korean_users ORDER BY updated_at DESC")
                rows = await cursor.fetchall()

                users = [row[0] for row in rows]

                logger.debug(f"📋 Found {len(users)} Korean users")
                return users

        except Exception as e:
            logger.error(f"❌ Failed to get all Korean users: {e}")
            return []

    async def get_top_users(self, limit: int = 10, period: str = "today") -> List[Dict]:
        """상위 한국어 사용자 조회"""
        try:
            await self._ensure_initialized()

            current_time = time.time()
            time_keys = self._get_time_keys(current_time)

            async with aiosqlite.connect(self.db_path) as db:
                if period == "today":
                    time_key = time_keys['day']
                    time_type = 'day'
                elif period == "hour":
                    time_key = time_keys['hour']
                    time_type = 'hour'
                elif period == "minute":
                    time_key = time_keys['minute']
                    time_type = 'minute'
                else:  # total
                    # 전체 사용량 기준
                    cursor = await db.execute("""
                        SELECT user_id, total_tokens, total_requests
                        FROM korean_users
                        ORDER BY total_tokens DESC
                        LIMIT ?
                    """, (limit,))
                    rows = await cursor.fetchall()

                    return [
                        {
                            'user_id': row[0],
                            'tokens': row[1],
                            'requests': row[2],
                            'user_type': 'korean_user'
                        }
                        for row in rows
                    ]

                # 시간별 사용량 기준
                cursor = await db.execute("""
                    SELECT u.user_id, ut.tokens, ut.requests, u.total_requests
                    FROM korean_usage_by_time ut
                    JOIN korean_users u ON ut.user_id = u.user_id
                    WHERE ut.time_key = ? AND ut.time_type = ?
                    ORDER BY ut.tokens DESC
                    LIMIT ?
                """, (time_key, time_type, limit))
                rows = await cursor.fetchall()

                return [
                    {
                        'user_id': row[0],
                        'tokens': row[1],
                        'requests': row[2] if row[2] else row[3],
                        'user_type': 'korean_user'
                    }
                    for row in rows
                ]

        except Exception as e:
            logger.error(f"❌ Failed to get top Korean users: {e}")
            return []

    async def get_usage_statistics(self) -> Dict:
        """전체 한국어 사용량 통계"""
        try:
            await self._ensure_initialized()

            current_time = time.time()
            time_keys = self._get_time_keys(current_time)

            async with aiosqlite.connect(self.db_path) as db:
                # 총 사용자 수
                cursor = await db.execute("SELECT COUNT(*) FROM korean_users")
                total_users = (await cursor.fetchone())[0]

                # 오늘 활성 사용자 수
                cursor = await db.execute("""
                    SELECT COUNT(*) FROM korean_usage_by_time 
                    WHERE time_key = ? AND time_type = 'day' AND tokens > 0
                """, (time_keys['day'],))
                active_users_today = (await cursor.fetchone())[0]

                # 오늘 총 토큰 사용량
                cursor = await db.execute("""
                    SELECT COALESCE(SUM(tokens), 0) FROM korean_usage_by_time 
                    WHERE time_key = ? AND time_type = 'day'
                """, (time_keys['day'],))
                total_tokens_today = (await cursor.fetchone())[0]

                # 오늘 총 요청 수 (근사치)
                cursor = await db.execute("""
                    SELECT COALESCE(SUM(requests), 0) FROM korean_usage_by_time 
                    WHERE time_key = ? AND time_type = 'minute' 
                """, (time_keys['minute'],))
                total_requests_today = (await cursor.fetchone())[0]

                return {
                    'total_users': total_users,
                    'active_users_today': active_users_today,
                    'total_tokens_today': total_tokens_today,
                    'total_requests_today': total_requests_today,
                    'average_tokens_per_user': total_tokens_today / max(active_users_today, 1),
                    'timestamp': current_time,
                    'system_type': 'korean_llm_limiter'
                }

        except Exception as e:
            logger.error(f"❌ Failed to get Korean usage statistics: {e}")
            return {}

    async def cleanup_expired_data(self):
        """만료된 한국어 데이터 정리"""
        try:
            await self._ensure_initialized()

            current_time = time.time()
            cutoff_time = current_time - (7 * 24 * 3600)  # 7일 전

            async with aiosqlite.connect(self.db_path) as db:
                # 오래된 시간별 사용량 데이터 삭제
                cursor = await db.execute("""
                    DELETE FROM korean_usage_by_time 
                    WHERE timestamp < ?
                """, (cutoff_time,))

                # 오래된 히스토리 데이터 삭제 (1000개 초과 시)
                cursor = await db.execute("""
                    DELETE FROM korean_usage_history 
                    WHERE id NOT IN (
                        SELECT id FROM korean_usage_history 
                        ORDER BY timestamp DESC 
                        LIMIT 1000
                    )
                """)

                deleted_rows = cursor.rowcount
                await db.commit()

                if deleted_rows > 0:
                    logger.info(f"🧹 Cleaned up {deleted_rows} expired Korean data rows")

        except Exception as e:
            logger.error(f"❌ Failed to cleanup expired Korean data: {e}")

    async def get_user_history(self, user_id: str, limit: int = 100) -> List[Dict]:
        """한국어 사용자 사용량 히스토리 조회"""
        try:
            await self._ensure_initialized()

            async with aiosqlite.connect(self.db_path) as db:
                cursor = await db.execute("""
                    SELECT tokens, requests, timestamp, date_str, additional_data
                    FROM korean_usage_history
                    WHERE user_id = ?
                    ORDER BY timestamp DESC
                    LIMIT ?
                """, (user_id, limit))
                rows = await cursor.fetchall()

                history = []
                for row in rows:
                    tokens, requests, timestamp, date_str, additional_data = row

                    data = {
                        'tokens': tokens,
                        'requests': requests,
                        'timestamp': timestamp,
                        'date': date_str,
                        'user_id': user_id
                    }

                    # 추가 데이터가 있으면 포함
                    if additional_data:
                        try:
                            extra_data = json.loads(additional_data)
                            data.update(extra_data)
                        except json.JSONDecodeError:
                            pass

                    history.append(data)

                return history

        except Exception as e:
            logger.error(f"❌ Failed to get Korean user history for {user_id}: {e}")
            return []