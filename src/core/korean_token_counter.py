"""
Korean-optimized token counter for Llama-3.2-Korean model
"""

import tiktoken
from transformers import AutoTokenizer
from typing import Dict, Any, Optional, List
import logging
import re

logger = logging.getLogger(__name__)


class KoreanTokenCounter:
    """한국어 최적화된 토큰 카운터"""
    
    def __init__(self, model_name: str = "torchtorchkimtorch/Llama-3.2-Korean-GGACHI-1B-Instruct-v1", korean_factor: float = 1.2):
        self.model_name = model_name
        self.korean_factor = korean_factor
        self.tokenizer = None
        self.tokenizer_type = None
        self._load_tokenizer()
    
    def _load_tokenizer(self):
        """한국어 모델용 토크나이저 로드"""
        try:
            # HuggingFace에서 한국어 모델 토크나이저 로드
            self.tokenizer = AutoTokenizer.from_pretrained(
                self.model_name,
                trust_remote_code=True,
                use_fast=True,
                cache_dir="./tokenizer_cache"
            )
            self.tokenizer_type = "korean_llama"
            logger.info(f"✅ Loaded Korean tokenizer for {self.model_name}")
            
        except Exception as e:
            logger.warning(f"⚠️ Korean tokenizer failed, trying fallback: {e}")
            # Fallback 1: Llama-2 기본 토크나이저
            try:
                self.tokenizer = AutoTokenizer.from_pretrained(
                    "meta-llama/Llama-2-7b-hf",
                    trust_remote_code=True,
                    cache_dir="./tokenizer_cache"
                )
                self.tokenizer_type = "llama_fallback"
                logger.info("✅ Loaded Llama-2 fallback tokenizer")
            except Exception as e2:
                logger.warning(f"⚠️ Llama fallback failed: {e2}")
                # Fallback 2: tiktoken
                try:
                    self.tokenizer = tiktoken.get_encoding("cl100k_base")
                    self.tokenizer_type = "tiktoken"
                    logger.info("✅ Loaded tiktoken fallback")
                except Exception as e3:
                    logger.error(f"❌ All tokenizers failed: {e3}")
                    self.tokenizer = None
                    self.tokenizer_type = "approximate"
    
    def count_tokens(self, text: str) -> int:
        """한국어 텍스트의 토큰 수 계산"""
        if not text:
            return 0
        
        try:
            if self.tokenizer_type in ["korean_llama", "llama_fallback"]:
                # HuggingFace 토크나이저 사용
                tokens = self.tokenizer.encode(text, add_special_tokens=False)
                return len(tokens)
            
            elif self.tokenizer_type == "tiktoken":
                return len(self.tokenizer.encode(text))
            
            else:
                # 한국어 근사치 계산
                return self._korean_approximate_count(text)
        
        except Exception as e:
            logger.error(f"❌ Token counting failed: {e}")
            return self._korean_approximate_count(text)
    
    def _korean_approximate_count(self, text: str) -> int:
        """한국어 텍스트 근사치 토큰 계산"""
        # 문자 유형별 분류
        korean_chars = len(re.findall(r'[가-힣]', text))
        english_chars = len(re.findall(r'[a-zA-Z]', text))
        number_chars = len(re.findall(r'[0-9]', text))
        space_chars = len(re.findall(r'\s', text))
        punctuation_chars = len(re.findall(r'[^\w\s가-힣]', text))
        
        # 한국어 특화 토큰 계산
        # 한글: 1글자 ≈ 1.2 토큰 (복합어 특성)
        # 영어: 4글자 ≈ 1 토큰  
        # 숫자: 2글자 ≈ 1 토큰
        # 공백: 4글자 ≈ 1 토큰
        # 구두점: 1글자 ≈ 1 토큰
        
        korean_tokens = korean_chars * self.korean_factor
        english_tokens = english_chars / 4.0
        number_tokens = number_chars / 2.0
        space_tokens = space_chars / 4.0
        punctuation_tokens = punctuation_chars
        
        total_tokens = korean_tokens + english_tokens + number_tokens + space_tokens + punctuation_tokens
        
        return max(1, int(total_tokens))
    
    def count_request_tokens(self, request_data: Dict[Any, Any]) -> Dict[str, int]:
        """요청의 입력 토큰 수 계산"""
        input_tokens = 0
        max_tokens = request_data.get('max_tokens', 100)
        
        try:
            # OpenAI 형식 (messages)
            if 'messages' in request_data:
                input_tokens = self.count_messages_tokens(request_data['messages'])
            
            # 단순 프롬프트 형식
            elif 'prompt' in request_data:
                prompt = request_data['prompt']
                if isinstance(prompt, str):
                    input_tokens = self.count_tokens(prompt)
                elif isinstance(prompt, list):
                    input_tokens = sum(self.count_tokens(str(p)) for p in prompt)
            
            # 텍스트 형식
            elif 'text' in request_data:
                input_tokens = self.count_tokens(str(request_data['text']))
            
            # 입력 형식
            elif 'input' in request_data:
                input_text = request_data['input']
                if isinstance(input_text, str):
                    input_tokens = self.count_tokens(input_text)
                elif isinstance(input_text, list):
                    input_tokens = sum(self.count_tokens(str(item)) for item in input_text)
        
        except Exception as e:
            logger.error(f"❌ Request token counting failed: {e}")
            input_tokens = 0
        
        return {
            'input_tokens': input_tokens,
            'max_tokens': max_tokens,
            'estimated_total': input_tokens + max_tokens
        }
    
    def count_messages_tokens(self, messages: List[Dict[str, Any]]) -> int:
        """한국어 메시지 포맷의 토큰 수 계산"""
        total_tokens = 0
        
        for message in messages:
            if not isinstance(message, dict):
                continue
            
            # 시스템/사용자/어시스턴트 역할 토큰
            role = message.get('role', '')
            content = message.get('content', '')
            
            # 역할별 오버헤드 (한국어 프롬프트 특성 반영)
            role_overhead = {
                'system': 4,      # "시스템:" 등의 토큰
                'user': 3,        # "사용자:" 등의 토큰
                'assistant': 4,   # "어시스턴트:" 등의 토큰
                'human': 3,       # "인간:" 등의 토큰
                'ai': 2,          # "AI:" 등의 토큰
                'bot': 2          # "봇:" 등의 토큰
            }
            
            total_tokens += role_overhead.get(role, 3)  # 기본 3토큰
            
            # 내용 토큰 계산
            if isinstance(content, str):
                total_tokens += self.count_tokens(content)
            elif isinstance(content, list):
                # 멀티모달 메시지 (텍스트 + 이미지 등)
                for item in content:
                    if isinstance(item, dict):
                        if item.get('type') == 'text':
                            total_tokens += self.count_tokens(item.get('text', ''))
                        elif item.get('type') == 'image_url':
                            # 이미지 토큰 근사치 (Vision 모델용)
                            total_tokens += 765  # 기본 이미지 토큰
                    elif isinstance(item, str):
                        total_tokens += self.count_tokens(item)
            
            # 함수 호출이 있는 경우
            if 'function_call' in message:
                func_call = message['function_call']
                if isinstance(func_call, dict):
                    total_tokens += self.count_tokens(str(func_call.get('name', '')))
                    total_tokens += self.count_tokens(str(func_call.get('arguments', '')))
            
            # 도구 호출이 있는 경우 (새로운 OpenAI API)
            if 'tool_calls' in message:
                tool_calls = message['tool_calls']
                if isinstance(tool_calls, list):
                    for tool_call in tool_calls:
                        if isinstance(tool_call, dict):
                            function = tool_call.get('function', {})
                            total_tokens += self.count_tokens(str(function.get('name', '')))
                            total_tokens += self.count_tokens(str(function.get('arguments', '')))
        
        # 대화 형식 오버헤드 (한국어 특성)
        total_tokens += 4  # 대화 시작/끝 토큰
        
        return total_tokens
    
    def count_response_tokens(self, response_data: Dict[Any, Any]) -> Dict[str, int]:
        """응답의 토큰 수 계산"""
        output_tokens = 0
        
        try:
            # OpenAI 응답 형식
            if 'usage' in response_data:
                usage = response_data['usage']
                return {
                    'input_tokens': usage.get('prompt_tokens', 0),
                    'output_tokens': usage.get('completion_tokens', 0),
                    'total_tokens': usage.get('total_tokens', 0)
                }
            
            # choices에서 토큰 계산
            elif 'choices' in response_data:
                for choice in response_data['choices']:
                    if 'message' in choice:
                        content = choice['message'].get('content', '')
                        output_tokens += self.count_tokens(content)
                    elif 'text' in choice:
                        output_tokens += self.count_tokens(choice['text'])
            
            # 단순 텍스트 응답
            elif 'text' in response_data:
                output_tokens = self.count_tokens(response_data['text'])
            
            elif 'content' in response_data:
                output_tokens = self.count_tokens(response_data['content'])
        
        except Exception as e:
            logger.error(f"❌ Response token counting failed: {e}")
        
        return {
            'input_tokens': 0,  # 응답에서는 입력 토큰을 알 수 없음
            'output_tokens': output_tokens,
            'total_tokens': output_tokens
        }
    
    def estimate_max_response_tokens(self, max_tokens: Optional[int], context_length: int = 2048) -> int:
        """최대 응답 토큰 수 추정"""
        if max_tokens:
            return min(max_tokens, context_length)
        
        # 기본값: 컨텍스트 길이의 25% (한국어 특성 고려)
        return min(512, context_length // 4)
    
    def get_tokenizer_info(self) -> Dict[str, Any]:
        """토크나이저 정보 반환"""
        vocab_size = 0
        if self.tokenizer:
            if hasattr(self.tokenizer, 'vocab_size'):
                vocab_size = self.tokenizer.vocab_size
            elif hasattr(self.tokenizer, '__len__'):
                vocab_size = len(self.tokenizer)
        
        return {
            'model_name': self.model_name,
            'tokenizer_type': self.tokenizer_type,
            'tokenizer_available': self.tokenizer is not None,
            'vocab_size': vocab_size,
            'korean_factor': self.korean_factor,
            'supports_korean': True
        }
    
    def analyze_text_composition(self, text: str) -> Dict[str, int]:
        """텍스트 구성 분석 (디버깅용)"""
        korean_chars = len(re.findall(r'[가-힣]', text))
        english_chars = len(re.findall(r'[a-zA-Z]', text))
        number_chars = len(re.findall(r'[0-9]', text))
        space_chars = len(re.findall(r'\s', text))
        punctuation_chars = len(re.findall(r'[^\w\s가-힣]', text))
        
        total_chars = len(text)
        
        return {
            'total_chars': total_chars,
            'korean_chars': korean_chars,
            'english_chars': english_chars,
            'number_chars': number_chars,
            'space_chars': space_chars,
            'punctuation_chars': punctuation_chars,
            'korean_ratio': korean_chars / total_chars if total_chars > 0 else 0,
            'estimated_tokens': self.count_tokens(text)
        }
