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
</style>
""", unsafe_allow_html=True)

# 설정
API_BASE_URL = "http://localhost:8080"
REFRESH_INTERVAL = 5  # 초