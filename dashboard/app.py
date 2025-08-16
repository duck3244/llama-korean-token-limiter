"""
한국어 Token Limiter 대시보드
"""

import streamlit as st
import requests
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import time
from datetime import datetime, timedelta
import json
import asyncio

# 페이지 설정
st.set_page_config(
    page_title="🇰🇷 Korean Token Limiter Dashboard",
    page_icon="🇰🇷",
    layout="wide",
    initial_sidebar_state="expanded"
)

# CSS 스타일
st.markdown("""
<style>
    .main-header {
        font-size: 2.5rem;
        font-weight: bold;
        text-align: center;
        color: #1f77b4;
        margin-bottom: 2rem;
    }
    
    .metric-container {
        background-color: #f0f2f6;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 0.5rem 0;
    }
    
    .status-healthy {
        color: #28a745;
        font-weight: bold;
    }
    
    .status-warning {
        color: #ffc107;
        font-weight: bold;
    }
    
    .status-error {
        color: #dc3545;
        font-weight: bold;
    }
    
    .korean-text {
        font-family: 'Noto Sans KR', sans-serif;
    }
    
    .stTabs [data-baseweb="tab-list"] {
        gap: 2px;
    }
    
    .stTabs [data-baseweb="tab"] {
        height: 50px;
        padding: 0px 20px;
        background-color: #f0f2f6;
        border-radius: 4px 4px 0px 0px;
    }
    
    .stTabs [aria-selected="true"] {
        background-color: #1f77b4;
        color: white;
    }
</style>
""", unsafe_allow_html=True)

# 설정
API_BASE_URL = "http://localhost:8080"
REFRESH_INTERVAL = 5  # 초

# 유틸리티 함수
@st.cache_data(ttl=5)
def get_system_health():
    """시스템 상태 조회"""
    try:
        response = requests.get(f"{API_BASE_URL}/health", timeout=5)
        if response.status_code == 200:
            return response.json()
        else:
            return {"status": "error", "error": f"HTTP {response.status_code}"}
    except requests.exceptions.RequestException as e:
        return {"status": "error", "error": str(e)}

@st.cache_data(ttl=10)
def get_user_list():
    """사용자 목록 조회"""
    try:
        response = requests.get(f"{API_BASE_URL}/admin/users", timeout=5)
        if response.status_code == 200:
            return response.json()
        else:
            return {"users": [], "total_count": 0}
    except requests.exceptions.RequestException:
        return {"users": [], "total_count": 0}

def get_user_stats(user_id):
    """사용자 통계 조회"""
    try:
        response = requests.get(f"{API_BASE_URL}/stats/{user_id}", timeout=5)
        if response.status_code == 200:
            return response.json()
        else:
            return None
    except requests.exceptions.RequestException:
        return None

def get_token_info(text="안녕하세요"):
    """토큰 계산 테스트"""
    try:
        response = requests.get(f"{API_BASE_URL}/token-info",
                              params={"text": text}, timeout=5)
        if response.status_code == 200:
            return response.json()
        else:
            return None
    except requests.exceptions.RequestException:
        return None

def test_chat_completion(user_key="sk-user1-korean-key-def", message="안녕하세요!"):
    """채팅 완성 테스트"""
    try:
        response = requests.post(
            f"{API_BASE_URL}/v1/chat/completions",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {user_key}"
            },
            json={
                "model": "korean-llama",
                "messages": [{"role": "user", "content": message}],
                "max_tokens": 50
            },
            timeout=30
        )
        return {
            "status_code": response.status_code,
            "response": response.json() if response.headers.get("content-type", "").startswith("application/json") else response.text
        }
    except requests.exceptions.RequestException as e:
        return {"status_code": 0, "error": str(e)}

# 메인 헤더
st.markdown('<h1 class="main-header">🇰🇷 Korean Token Limiter Dashboard</h1>',
            unsafe_allow_html=True)

# 사이드바 - 실시간 상태
with st.sidebar:
    st.header("⚡ 실시간 상태")

    # 자동 새로고침 설정
    auto_refresh = st.checkbox("자동 새로고침 (5초)", value=True)
    if auto_refresh:
        time.sleep(0.1)  # 작은 지연으로 새로고침 효과
        st.rerun()

    # 시스템 상태
    health = get_system_health()

    if health.get("status") == "healthy":
        st.success("✅ 시스템 정상")

        vllm_status = health.get("vllm_server", "unknown")
        if vllm_status == "connected":
            st.success("🚀 vLLM 연결됨")
        else:
            st.error("❌ vLLM 연결 실패")

        st.info(f"🤖 모델: {health.get('model', 'Unknown')}")
        st.info(f"⏰ 업데이트: {datetime.now().strftime('%H:%M:%S')}")
    else:
        st.error("❌ 시스템 오류")
        st.error(f"오류: {health.get('error', 'Unknown error')}")

    # 빠른 테스트
    st.subheader("🧪 빠른 테스트")

    if st.button("토큰 계산 테스트"):
        token_result = get_token_info("안녕하세요! 테스트입니다.")
        if token_result:
            st.success(f"✅ 토큰 수: {token_result.get('token_count', 0)}")
        else:
            st.error("❌ 토큰 계산 실패")

# 메인 탭 구성
tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "📊 대시보드 개요",
    "👥 사용자 관리",
    "🧪 API 테스트",
    "📈 실시간 모니터링",
    "⚙️ 시스템 설정"
])

# 탭 1: 대시보드 개요
with tab1:
    st.header("📊 시스템 개요")

    # 상단 메트릭
    col1, col2, col3, col4 = st.columns(4)

    health = get_system_health()
    user_list = get_user_list()

    with col1:
        status_color = "green" if health.get("status") == "healthy" else "red"
        st.metric("시스템 상태",
                 "정상" if health.get("status") == "healthy" else "오류",
                 delta=None)

    with col2:
        total_users = user_list.get("total_count", 0)
        st.metric("총 사용자 수", total_users)

    with col3:
        vllm_status = health.get("vllm_server", "disconnected")
        st.metric("vLLM 서버",
                 "연결됨" if vllm_status == "connected" else "연결 안됨")

    with col4:
        model_name = health.get("actual_vllm_model", health.get("model", "Unknown"))
        st.metric("사용 모델", model_name)

    st.divider()

    # 시스템 정보 표시
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("🔧 시스템 정보")

        info_data = {
            "항목": ["서버 포트", "vLLM 포트", "모델명", "인코딩", "한국어 지원"],
            "값": [
                "8080",
                "8000",
                health.get("model", "Unknown"),
                health.get("encoding", "utf-8"),
                "✅" if health.get("supports_korean") else "❌"
            ]
        }
        st.dataframe(pd.DataFrame(info_data), hide_index=True)

    with col2:
        st.subheader("📊 API 엔드포인트")

        endpoints = [
            {"엔드포인트": "/health", "상태": "✅", "설명": "시스템 상태 확인"},
            {"엔드포인트": "/v1/chat/completions", "상태": "✅", "설명": "채팅 완성 API"},
            {"엔드포인트": "/v1/completions", "상태": "✅", "설명": "텍스트 완성 API"},
            {"엔드포인트": "/stats/{user_id}", "상태": "✅", "설명": "사용자 통계"},
            {"엔드포인트": "/token-info", "상태": "✅", "설명": "토큰 계산"}
        ]
        st.dataframe(pd.DataFrame(endpoints), hide_index=True)

# 탭 2: 사용자 관리
with tab2:
    st.header("👥 사용자 관리")

    user_list = get_user_list()

    if user_list.get("total_count", 0) > 0:
        st.subheader(f"총 {user_list['total_count']}명의 사용자")

        # 사용자별 통계 수집
        user_stats_list = []

        for user_info in user_list.get("users", []):
            if isinstance(user_info, dict):
                user_id = user_info.get("user_id")
                display_name = user_info.get("display_name", user_id)
            else:
                user_id = user_info
                display_name = user_id

            stats = get_user_stats(user_id)
            if stats:
                user_stats_list.append({
                    "사용자 ID": user_id,
                    "표시명": display_name,
                    "분당 요청": f"{stats.get('requests_this_minute', 0)}/{stats.get('limits', {}).get('rpm', 0)}",
                    "분당 토큰": f"{stats.get('tokens_this_minute', 0):,}/{stats.get('limits', {}).get('tpm', 0):,}",
                    "오늘 토큰": f"{stats.get('tokens_today', 0):,}",
                    "총 요청": f"{stats.get('total_requests', 0):,}",
                    "총 토큰": f"{stats.get('total_tokens', 0):,}"
                })

        if user_stats_list:
            df = pd.DataFrame(user_stats_list)
            st.dataframe(df, hide_index=True, use_container_width=True)

            # 사용자별 사용량 차트
            st.subheader("📊 사용자별 토큰 사용량")

            # 오늘 토큰 사용량 차트
            fig = px.bar(
                df,
                x="표시명",
                y=[int(x.replace(",", "")) for x in df["오늘 토큰"]],
                title="사용자별 오늘 토큰 사용량",
                labels={"y": "토큰 수", "x": "사용자"}
            )
            fig.update_layout(showlegend=False)
            st.plotly_chart(fig, use_container_width=True)

        else:
            st.info("📝 사용량 데이터가 있는 사용자가 없습니다.")
    else:
        st.info("👤 등록된 사용자가 없습니다.")

    # 사용자 선택 및 세부 정보
    st.subheader("🔍 사용자 세부 정보")

    if user_list.get("users"):
        user_options = []
        for user_info in user_list["users"]:
            if isinstance(user_info, dict):
                user_id = user_info.get("user_id")
                display_name = user_info.get("display_name", user_id)
                user_options.append(f"{display_name} ({user_id})")
            else:
                user_options.append(user_info)

        selected_user = st.selectbox("사용자 선택", user_options)

        if selected_user:
            # 사용자 ID 추출
            if "(" in selected_user:
                selected_user_id = selected_user.split("(")[1].strip(")")
            else:
                selected_user_id = selected_user

            user_stats = get_user_stats(selected_user_id)

            if user_stats:
                col1, col2 = st.columns(2)

                with col1:
                    st.metric("분당 요청",
                             f"{user_stats.get('requests_this_minute', 0)}/{user_stats.get('limits', {}).get('rpm', 0)}")
                    st.metric("분당 토큰",
                             f"{user_stats.get('tokens_this_minute', 0):,}/{user_stats.get('limits', {}).get('tpm', 0):,}")

                with col2:
                    st.metric("오늘 토큰", f"{user_stats.get('tokens_today', 0):,}")
                    st.metric("총 토큰", f"{user_stats.get('total_tokens', 0):,}")

                # 제한 정보
                limits = user_stats.get('limits', {})
                st.subheader("📋 사용 제한")

                limits_data = {
                    "제한 유형": ["분당 요청 수", "분당 토큰 수", "일일 토큰 수"],
                    "제한값": [
                        f"{limits.get('rpm', 0):,}개",
                        f"{limits.get('tpm', 0):,}개",
                        f"{limits.get('daily', 0):,}개"
                    ],
                    "현재 사용": [
                        f"{user_stats.get('requests_this_minute', 0):,}개",
                        f"{user_stats.get('tokens_this_minute', 0):,}개",
                        f"{user_stats.get('tokens_today', 0):,}개"
                    ]
                }
                st.dataframe(pd.DataFrame(limits_data), hide_index=True)

# 탭 3: API 테스트
with tab3:
    st.header("🧪 API 테스트")

    # 토큰 계산 테스트
    st.subheader("🔢 토큰 계산 테스트")

    test_text = st.text_area(
        "테스트할 텍스트를 입력하세요:",
        value="안녕하세요! 한국어 토큰 계산 테스트입니다. 이 텍스트는 몇 개의 토큰으로 계산될까요?",
        height=100
    )

    if st.button("토큰 계산 실행"):
        with st.spinner("토큰 계산 중..."):
            result = get_token_info(test_text)

            if result:
                col1, col2, col3 = st.columns(3)
                with col1:
                    st.metric("토큰 수", result.get("token_count", 0))
                with col2:
                    st.metric("글자 수", len(test_text))
                with col3:
                    ratio = result.get("token_count", 0) / len(test_text) if len(test_text) > 0 else 0
                    st.metric("토큰/글자 비율", f"{ratio:.2f}")

                st.success("✅ 토큰 계산 완료")
            else:
                st.error("❌ 토큰 계산 실패")

    st.divider()

    # 채팅 완성 테스트
    st.subheader("💬 채팅 완성 테스트")

    col1, col2 = st.columns(2)

    with col1:
        test_api_key = st.selectbox(
            "API 키 선택:",
            [
                "sk-user1-korean-key-def",
                "sk-user2-korean-key-ghi",
                "sk-dev1-korean-key-789",
                "sk-test-korean-key-stu",
                "sk-guest-korean-key-vwx"
            ]
        )

    with col2:
        max_tokens = st.slider("최대 토큰 수", 10, 200, 50)

    test_message = st.text_input(
        "테스트 메시지:",
        value="안녕하세요! 간단한 자기소개를 해주세요."
    )

    if st.button("채팅 완성 테스트 실행"):
        with st.spinner("AI 응답 생성 중..."):
            result = test_chat_completion(test_api_key, test_message)

            if result["status_code"] == 200:
                response_data = result["response"]
                if "choices" in response_data:
                    ai_response = response_data["choices"][0]["message"]["content"]

                    st.success("✅ 채팅 완성 성공")
                    st.text_area("AI 응답:", ai_response, height=150)

                    # 사용량 정보 표시
                    usage = response_data.get("usage", {})
                    if usage:
                        col1, col2, col3 = st.columns(3)
                        with col1:
                            st.metric("입력 토큰", usage.get("prompt_tokens", 0))
                        with col2:
                            st.metric("출력 토큰", usage.get("completion_tokens", 0))
                        with col3:
                            st.metric("총 토큰", usage.get("total_tokens", 0))
                else:
                    st.error("❌ 응답 형식 오류")
                    st.json(response_data)

            elif result["status_code"] == 429:
                st.warning("⚠️ 속도 제한 초과")
                error_data = result.get("response", {})
                if isinstance(error_data, dict) and "error" in error_data:
                    st.error(f"제한 사유: {error_data['error'].get('message', '알 수 없음')}")

            else:
                st.error(f"❌ API 오류 (HTTP {result['status_code']})")
                if "error" in result:
                    st.error(f"오류: {result['error']}")
                elif "response" in result:
                    st.json(result["response"])

# 탭 4: 실시간 모니터링
with tab4:
    st.header("📈 실시간 모니터링")

    # 자동 새로고침
    if st.checkbox("실시간 업데이트 (5초 간격)", value=False, key="monitoring_refresh"):
        time.sleep(5)
        st.rerun()

    # 시스템 상태 모니터링
    st.subheader("🖥️ 시스템 상태")

    health = get_system_health()

    col1, col2, col3 = st.columns(3)

    with col1:
        if health.get("status") == "healthy":
            st.success("🟢 시스템 정상")
        else:
            st.error("🔴 시스템 오류")

    with col2:
        vllm_status = health.get("vllm_server")
        if vllm_status == "connected":
            st.success("🟢 vLLM 연결됨")
        else:
            st.error("🔴 vLLM 연결 안됨")

    with col3:
        st.info(f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # 사용자 활동 모니터링
    st.subheader("👥 사용자 활동")

    user_list = get_user_list()
    if user_list.get("users"):
        # 활성 사용자 찾기
        active_users = []

        for user_info in user_list["users"]:
            if isinstance(user_info, dict):
                user_id = user_info.get("user_id")
                display_name = user_info.get("display_name", user_id)
            else:
                user_id = user_info
                display_name = user_id

            stats = get_user_stats(user_id)
            if stats and (stats.get("requests_this_minute", 0) > 0 or stats.get("tokens_this_minute", 0) > 0):
                active_users.append({
                    "사용자": display_name,
                    "분당 요청": stats.get("requests_this_minute", 0),
                    "분당 토큰": stats.get("tokens_this_minute", 0),
                    "사용률": f"{(stats.get('tokens_this_minute', 0) / stats.get('limits', {}).get('tpm', 1) * 100):.1f}%"
                })

        if active_users:
            st.dataframe(pd.DataFrame(active_users), hide_index=True, use_container_width=True)
        else:
            st.info("현재 활성 사용자가 없습니다.")

    # 성능 메트릭 (가상 데이터)
    st.subheader("⚡ 성능 메트릭")

    # 간단한 성능 지표 표시
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("평균 응답 시간", "1.2초", "↓0.1s")

    with col2:
        st.metric("요청 처리율", "95.8%", "↑2.1%")

    with col3:
        st.metric("동시 사용자", len(active_users) if 'active_users' in locals() else 0)

    with col4:
        st.metric("시스템 업타임", "99.9%", "↑0.1%")

# 탭 5: 시스템 설정
with tab5:
    st.header("⚙️ 시스템 설정")

    st.subheader("🔧 현재 설정")

    health = get_system_health()

    config_data = {
        "설정 항목": [
            "Token Limiter 포트",
            "vLLM 서버 포트",
            "사용 모델",
            "실제 vLLM 모델",
            "한국어 지원",
            "인코딩 방식",
            "자동 새로고침"
        ],
        "현재 값": [
            "8080",
            "8000",
            health.get("model", "Unknown"),
            health.get("actual_vllm_model", "Unknown"),
            "✅" if health.get("supports_korean") else "❌",
            health.get("encoding", "utf-8"),
            "활성화됨" if auto_refresh else "비활성화됨"
        ]
    }

    st.dataframe(pd.DataFrame(config_data), hide_index=True, use_container_width=True)

    st.subheader("📊 기본 제한 설정")

    # 기본 제한값들 (실제로는 서버에서 가져와야 함)
    default_limits = {
        "제한 유형": ["분당 요청 수 (RPM)", "분당 토큰 수 (TPM)", "일일 토큰 수"],
        "기본값": ["30개", "5,000개", "500,000개"],
        "설명": ["1분간 최대 요청 횟수", "1분간 최대 토큰 수", "하루 최대 토큰 수"]
    }

    st.dataframe(pd.DataFrame(default_limits), hide_index=True, use_container_width=True)

    st.subheader("🌐 API 엔드포인트")

    endpoints_info = {
        "엔드포인트": [
            "GET /health",
            "POST /v1/chat/completions",
            "POST /v1/completions",
            "GET /stats/{user_id}",
            "GET /token-info",
            "GET /admin/users",
            "GET /models"
        ],
        "설명": [
            "시스템 상태 확인",
            "채팅 형태 AI 응답 생성",
            "텍스트 완성 AI 응답 생성",
            "사용자별 사용량 통계",
            "텍스트 토큰 수 계산",
            "전체 사용자 목록",
            "사용 가능한 모델 목록"
        ],
        "인증": [
            "불필요", "API 키 필요", "API 키 필요",
            "불필요", "불필요", "불필요", "불필요"
        ]
    }

    st.dataframe(pd.DataFrame(endpoints_info), hide_index=True, use_container_width=True)

    # 시스템 정보
    st.subheader("💻 시스템 정보")

    if st.button("시스템 정보 새로고침"):
        health = get_system_health()
        st.success("✅ 정보가 새로고침되었습니다.")

    # 연결 테스트
    st.subheader("🔗 연결 테스트")

    col1, col2 = st.columns(2)

    with col1:
        if st.button("Token Limiter 연결 테스트"):
            health = get_system_health()
            if health.get("status") == "healthy":
                st.success("✅ Token Limiter 연결 성공")
            else:
                st.error("❌ Token Limiter 연결 실패")

    with col2:
        if st.button("vLLM 서버 연결 테스트"):
            health = get_system_health()
            vllm_status = health.get("vllm_server")
            if vllm_status == "connected":
                st.success("✅ vLLM 서버 연결 성공")
            else:
                st.error("❌ vLLM 서버 연결 실패")

# 푸터
st.divider()
st.markdown("""
<div style='text-align: center; color: #666; padding: 20px;'>
    🇰🇷 Korean Token Limiter Dashboard v1.0<br>
    실시간 모니터링 및 관리 시스템
</div>
""", unsafe_allow_html=True)