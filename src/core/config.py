"""
Configuration management for Korean Token Limiter
"""

import os
import yaml
from typing import Optional, Dict, Any
from pydantic import BaseSettings, Field
from pathlib import Path


class Config(BaseSettings):
    """애플리케이션 설정"""
    
    # 서버 설정
    server_host: str = Field(default="0.0.0.0", env="SERVER_HOST")
    server_port: int = Field(default=8080, env="SERVER_PORT")
    debug: bool = Field(default=False, env="DEBUG")
    
    # LLM 서버 설정
    llm_server_url: str = Field(default="http://localhost:8000", env="LLM_SERVER_URL")
    model_name: str = Field(default="torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1", env="MODEL_NAME")
    
    # 저장소 설정
    storage_type: str = Field(default="redis", env="STORAGE_TYPE")  # redis or sqlite
    redis_url: str = Field(default="redis://localhost:6379", env="REDIS_URL")
    sqlite_path: str = Field(default="korean_usage.db", env="SQLITE_PATH")
    
    # 기본 제한 설정 (한국어 모델 특화)
    default_rpm: int = Field(default=30, env="DEFAULT_RPM")
    default_tpm: int = Field(default=5000, env="DEFAULT_TPM")
    default_tph: int = Field(default=300000, env="DEFAULT_TPH")
    default_daily: int = Field(default=500000, env="DEFAULT_DAILY")
    default_cooldown: int = Field(default=3, env="DEFAULT_COOLDOWN")
    
    # 토큰 카운터 설정
    tokenizer_cache_dir: str = Field(default="./tokenizer_cache", env="TOKENIZER_CACHE_DIR")
    max_token_estimation: int = Field(default=2048, env="MAX_TOKEN_ESTIMATION")
    korean_factor: float = Field(default=1.2, env="KOREAN_FACTOR")  # 한국어 토큰 보정값
    
    # 로깅 설정
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    log_file: Optional[str] = Field(default=None, env="LOG_FILE")
    
    # vLLM 최적화 설정 (RTX 4060)
    gpu_memory_utilization: float = Field(default=0.8, env="GPU_MEMORY_UTILIZATION")
    max_model_len: int = Field(default=2048, env="MAX_MODEL_LEN")
    tensor_parallel_size: int = Field(default=1, env="TENSOR_PARALLEL_SIZE")
    dtype: str = Field(default="half", env="DTYPE")
    enforce_eager: bool = Field(default=True, env="ENFORCE_EAGER")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._load_yaml_config()
    
    def _load_yaml_config(self):
        """YAML 설정 파일 로드"""
        config_path = Path("config/korean_model.yaml")
        if config_path.exists():
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    yaml_config = yaml.safe_load(f)
                
                # YAML 설정을 환경 변수보다 낮은 우선순위로 적용
                self._apply_yaml_config(yaml_config)
                
            except Exception as e:
                print(f"⚠️ YAML 설정 파일 로드 실패: {e}")
    
    def _apply_yaml_config(self, yaml_config: Dict[str, Any]):
        """YAML 설정 적용"""
        if 'server' in yaml_config:
            server_config = yaml_config['server']
            if not os.getenv('SERVER_HOST'):
                self.server_host = server_config.get('host', self.server_host)
            if not os.getenv('SERVER_PORT'):
                self.server_port = server_config.get('port', self.server_port)
        
        if 'llm_server' in yaml_config:
            llm_config = yaml_config['llm_server']
            if not os.getenv('LLM_SERVER_URL'):
                self.llm_server_url = llm_config.get('url', self.llm_server_url)
            if not os.getenv('MODEL_NAME'):
                self.model_name = llm_config.get('model_name', self.model_name)
            
            # vLLM 설정 적용
            if 'vllm_args' in llm_config:
                vllm_args = llm_config['vllm_args']
                if not os.getenv('GPU_MEMORY_UTILIZATION'):
                    self.gpu_memory_utilization = vllm_args.get('gpu_memory_utilization', self.gpu_memory_utilization)
                if not os.getenv('MAX_MODEL_LEN'):
                    self.max_model_len = vllm_args.get('max_model_len', self.max_model_len)
        
        if 'storage' in yaml_config:
            storage_config = yaml_config['storage']
            if not os.getenv('STORAGE_TYPE'):
                self.storage_type = storage_config.get('type', self.storage_type)
            if not os.getenv('REDIS_URL'):
                self.redis_url = storage_config.get('redis_url', self.redis_url)
            if not os.getenv('SQLITE_PATH'):
                self.sqlite_path = storage_config.get('sqlite_path', self.sqlite_path)
        
        if 'default_limits' in yaml_config:
            limits_config = yaml_config['default_limits']
            if not os.getenv('DEFAULT_RPM'):
                self.default_rpm = limits_config.get('rpm', self.default_rpm)
            if not os.getenv('DEFAULT_TPM'):
                self.default_tpm = limits_config.get('tpm', self.default_tpm)
            if not os.getenv('DEFAULT_TPH'):
                self.default_tph = limits_config.get('tph', self.default_tph)
            if not os.getenv('DEFAULT_DAILY'):
                self.default_daily = limits_config.get('daily', self.default_daily)
            if not os.getenv('DEFAULT_COOLDOWN'):
                self.default_cooldown = limits_config.get('cooldown_minutes', self.default_cooldown)
        
        if 'tokenizer' in yaml_config:
            tokenizer_config = yaml_config['tokenizer']
            if not os.getenv('KOREAN_FACTOR'):
                self.korean_factor = tokenizer_config.get('korean_factor', self.korean_factor)
    
    @property
    def use_redis(self) -> bool:
        """Redis 사용 여부"""
        return self.storage_type.lower() == "redis"
    
    def get_default_limits(self) -> Dict[str, int]:
        """기본 제한 설정 반환"""
        return {
            "rpm": self.default_rpm,
            "tpm": self.default_tpm,
            "tph": self.default_tph,
            "daily": self.default_daily,
            "cooldown_minutes": self.default_cooldown
        }
    
    def get_vllm_args(self) -> Dict[str, Any]:
        """vLLM 서버 실행 인자 반환"""
        return {
            "model": self.model_name,
            "gpu_memory_utilization": self.gpu_memory_utilization,
            "max_model_len": self.max_model_len,
            "tensor_parallel_size": self.tensor_parallel_size,
            "dtype": self.dtype,
            "enforce_eager": self.enforce_eager,
            "trust_remote_code": True,
            "disable_log_requests": True
        }
