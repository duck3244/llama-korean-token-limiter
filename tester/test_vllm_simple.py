#!/usr/bin/env python3
"""
vLLM 간단한 테스트 스크립트
"""
import sys
import subprocess
import time

def test_vllm_import():
    """vLLM 패키지 import 테스트"""
    print("🧪 vLLM import 테스트...")
    try:
        import vllm
        print(f"✅ vLLM 버전: {vllm.__version__}")
        return True
    except ImportError as e:
        print(f"❌ vLLM import 실패: {e}")
        return False

def test_cuda():
    """CUDA 환경 테스트"""
    print("🎮 CUDA 테스트...")
    try:
        import torch
        print(f"PyTorch 버전: {torch.__version__}")
        print(f"CUDA 사용 가능: {torch.cuda.is_available()}")
        if torch.cuda.is_available():
            print(f"CUDA 버전: {torch.version.cuda}")
            print(f"GPU 개수: {torch.cuda.device_count()}")
            print(f"GPU 이름: {torch.cuda.get_device_name(0)}")
            
            # GPU 메모리 확인
            gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
            print(f"GPU 메모리: {gpu_memory:.1f}GB")
            
            # 메모리 사용량 확인
            torch.cuda.empty_cache()
            allocated = torch.cuda.memory_allocated(0) / 1024**3
            cached = torch.cuda.memory_reserved(0) / 1024**3
            print(f"할당된 메모리: {allocated:.1f}GB")
            print(f"캐시된 메모리: {cached:.1f}GB")
            
        return torch.cuda.is_available()
    except Exception as e:
        print(f"❌ CUDA 테스트 실패: {e}")
        return False

def test_small_model():
    """작은 모델로 vLLM 테스트"""
    print("🤖 작은 모델로 vLLM 테스트...")
    
    # RTX 4060 8GB에 적합한 작은 모델들
    small_models = [
        "microsoft/DialoGPT-medium",  # ~350MB
        "gpt2",  # ~500MB
        "distilgpt2",  # ~320MB
    ]
    
    for model_name in small_models:
        print(f"\n🔍 {model_name} 테스트 중...")
        
        try:
            from vllm import LLM
            
            # 매우 보수적인 설정
            llm = LLM(
                model=model_name,
                gpu_memory_utilization=0.5,  # 50%만 사용
                max_model_len=512,  # 짧은 컨텍스트
                dtype="half",
                enforce_eager=True,
                trust_remote_code=True,
                tensor_parallel_size=1
            )
            
            # 간단한 생성 테스트
            prompts = ["Hello, how are you?"]
            outputs = llm.generate(prompts, max_tokens=10)
            
            for output in outputs:
                print(f"✅ 생성 성공: {output.outputs[0].text}")
            
            print(f"✅ {model_name} 테스트 성공!")
            return True
            
        except Exception as e:
            print(f"❌ {model_name} 테스트 실패: {e}")
            continue
    
    return False

def test_vllm_server():
    """vLLM 서버 모드 테스트"""
    print("🚀 vLLM 서버 모드 테스트...")
    
    # 가장 작은 모델로 서버 시작
    cmd = [
        "python", "-m", "vllm.entrypoints.openai.api_server",
        "--model", "distilgpt2",
        "--port", "8001",  # 다른 포트 사용
        "--host", "127.0.0.1",
        "--gpu-memory-utilization", "0.4",
        "--max-model-len", "256",
        "--dtype", "half",
        "--enforce-eager",
        "--trust-remote-code"
    ]
    
    print(f"명령어: {' '.join(cmd)}")
    
    try:
        # 서버 시작
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # 10초간 대기
        for i in range(10):
            if process.poll() is not None:
                stdout, stderr = process.communicate()
                print(f"❌ 서버가 {i}초 후 종료됨")
                print(f"stdout: {stdout[-500:]}")
                print(f"stderr: {stderr[-500:]}")
                return False
            
            print(f"⏳ 서버 시작 대기 중... ({i+1}/10)")
            time.sleep(1)
        
        # 서버 종료
        process.terminate()
        process.wait(timeout=5)
        
        print("✅ 서버 테스트 완료 (정상 시작됨)")
        return True
        
    except Exception as e:
        print(f"❌ 서버 테스트 실패: {e}")
        return False

def check_system_resources():
    """시스템 리소스 확인"""
    print("💻 시스템 리소스 확인...")
    
    try:
        import psutil
        
        # CPU 정보
        print(f"CPU 코어: {psutil.cpu_count()}")
        print(f"CPU 사용률: {psutil.cpu_percent()}%")
        
        # 메모리 정보
        memory = psutil.virtual_memory()
        print(f"총 메모리: {memory.total / 1024**3:.1f}GB")
        print(f"사용 메모리: {memory.used / 1024**3:.1f}GB")
        print(f"메모리 사용률: {memory.percent}%")
        
        # 디스크 정보
        disk = psutil.disk_usage('.')
        print(f"디스크 여유공간: {disk.free / 1024**3:.1f}GB")
        
        return True
        
    except ImportError:
        print("psutil 패키지가 없어서 시스템 정보를 조회할 수 없습니다")
        return True
    except Exception as e:
        print(f"❌ 시스템 리소스 확인 실패: {e}")
        return False

def main():
    print("🧪 vLLM 진단 테스트 시작")
    print("=" * 50)
    
    # 단계별 테스트
    tests = [
        ("vLLM 패키지", test_vllm_import),
        ("CUDA 환경", test_cuda),
        ("시스템 리소스", check_system_resources),
        ("작은 모델", test_small_model),
        ("서버 모드", test_vllm_server),
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        print(f"\n{'=' * 20}")
        print(f"📋 {test_name} 테스트")
        print(f"{'=' * 20}")
        
        try:
            result = test_func()
            results[test_name] = result
            status = "✅ 통과" if result else "❌ 실패"
            print(f"\n🏁 {test_name}: {status}")
        except Exception as e:
            print(f"\n💥 {test_name} 테스트 중 예외 발생: {e}")
            results[test_name] = False
    
    # 결과 요약
    print("\n" + "=" * 50)
    print("📊 테스트 결과 요약")
    print("=" * 50)
    
    for test_name, result in results.items():
        status = "✅" if result else "❌"
        print(f"{status} {test_name}")
    
    # 권장사항
    print("\n📋 권장사항:")
    
    if not results.get("CUDA 환경", False):
        print("❗ CUDA 환경 문제. PyTorch CUDA 설치 확인 필요")
    
    if not results.get("작은 모델", False):
        print("❗ vLLM 기본 동작 문제. 패키지 재설치 권장")
        print("   pip uninstall vllm")
        print("   pip install vllm==0.2.7")
    
    if not results.get("서버 모드", False):
        print("❗ vLLM 서버 모드 문제")
        print("   1. GPU 메모리 부족 가능성")
        print("   2. 포트 충돌 확인")
        print("   3. 더 작은 모델 사용 권장")
    
    # CPU 전용 모드 제안
    if not results.get("CUDA 환경", False) or not results.get("작은 모델", False):
        print("\n💡 대안: CPU 전용 Token Limiter 실행")
        print("   python main.py  # vLLM 없이 실행")

if __name__ == "__main__":
    main()