#!/usr/bin/env python3
"""ComfyUI Monitor for vLLM + ComfyUI on NVIDIA GB10 (DGX Spark)
Shared GPU resource monitor
"""
import subprocess
import socket
import time
import json
import os
import sys

try:
    import torch
except ImportError:
    torch = None

def run(cmd, timeout=10):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "timeout"
    except Exception as e:
        return str(e)

def print_separator(title):
    print(f"\n{'='*50}")
    print(f"  {title}")
    print(f"{'='*50}")

def docker_nvidia(args=""):
    return run(f"docker exec nemoclaw-vllm nvidia-smi {args} 2>/dev/null")

def docker_check():
    return run("docker inspect -f '{{.State.Status}}' nemoclaw-vllm 2>/dev/null")

def curl_health(port):
    try:
        import urllib.request
        req = urllib.request.Request(f"http://127.0.0.1:{port}/health")
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.getcode()
            data = json.loads(resp.read())
            return status, data
    except:
        return None, None

def get_torch_vram():
    if not torch or not torch.cuda.is_available():
        return 0, 0, 0
    props = torch.cuda.get_device_properties(0)
    total = props.total_memory
    used = torch.cuda.memory_allocated()
    reserved = torch.cuda.memory_reserved()
    return round(total/1e9, 2), round(used/1e9, 2), round(reserved/1e9, 2)

def main():
    print(f"\n  ComfyUI + vLLM GPU Monitor — {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  System: Linux on NVIDIA GB10 / DGX Spark")
    print()
    
    # GPU Memory
    print_separator("GPU Memory (NVIDIA GB10)")
    if torch and torch.cuda.is_available():
        total, used_allocated, used_reserved = get_torch_vram()
        print(f"  PyTorch CUDA: Enabled")
        print(f"  Device: {torch.cuda.get_device_name(0)}")
        print(f"  Total VRAM: {total:.1f} GB")
        print(f"  Allocated: {used_allocated:.1f} GB")
        print(f"  Reserved: {used_reserved:.1f} GB")
        print(f"  Free (available): {total - used_reserved:.1f} GB")
    else:
        print("  PyTorch: Not available (not installed in this Python)")
    
    # vLLM status
    print_separator("vLLM Container (nemoclaw-vllm)")
    status = docker_check()
    if status:
        print(f"  State: {status}")
        status_code, health_data = curl_health(8000)
        if status_code == 200:
            print(f"  HTTP /health: OK (200)")
            if health_data and isinstance(health_data, dict):
                vram = health_data.get('gpu_cache', health_data.get('memory', ''))
                print(f"  Status: {json.dumps(health_data, indent=8).replace('\\n', '|')}")
        else:
            print(f"  HTTP /health: {'FAIL' if status_code else 'TIMEOUT'} ({status_code})")
    else:
        print("  State: DOWN (container not running)")
    
    # GPU memory from nvidia-smi
    print_separator("Detailed GPU Memory (docker exec)")
    nvidia_output = docker_nvidia("--query-gpu=memory.total,memory.used,memory.free --format=csv,noheader,nounits -i 0")
    if nvidia_output and nvidia_output != "timeout" and "Error" not in nvidia_output:
        mem_total, mem_used, mem_free = nvidia_output.split(',')
        print(f"  Total: {mem_total.strip()} MiB")
        print(f"  Used: {mem_used.strip()} MiB ({int(mem_used)/1024:.1f} GB)")
        print(f"  Free: {mem_free.strip()} MiB ({int(mem_free)/1024:.1f} GB)")
    else:
        print("  N/A (container not responding)")
    
    # ComfyUI status
    print_separator("ComfyUI (host PyTorch)")
    comfy_path = "/home/victoria/ComfyUI"
    if os.path.exists(comfy_path):
        print(f"  Path: {comfy_path}")
        models_dir = os.path.join(comfy_path, "models")
        if os.path.exists(models_dir):
            model_count = 0
            model_size = 0
            model_dir_size = 0
            for root, dirs, files in os.walk(models_dir):
                for f in files:
                    if f.endswith(('.safetensors', '.ckpt', '.bin')):
                        model_count += 1
                        try:
                            fpath = os.path.join(root, f)
                            model_size += os.path.getsize(fpath)
                        except:
                            pass
                for d in dirs:
                    dpath = os.path.join(root, d)
                    try:
                        model_dir_size += sum(os.path.getsize(os.path.join(dp, df)) for dp, dn, fn in os.walk(dpath) for df in fn)
                    except:
                        pass
            print(f"  Models: {model_count} files, ~{(model_size + model_dir_size)/1e9:.1f} GB")
        print(f"  Custom nodes: {len([d for d in os.listdir(os.path.join(comfy_path, 'custom_nodes')) if os.path.isdir(os.path.join(comfy_path, 'custom_nodes', d))])} installed")
    else:
        print("  NOT INSTALLED")
    
    # Recommended config
    print_separator("Shared GPU Config")
    print("  vLLM: ~47.6 GB (Qwen3.6-35B)")
    print("  ComfyUI: 8-30 GB (image generation)")
    print(f"  Headroom: ~{round(128 - 47.6 - 30, 1):.0f}-80.4 GB available")
    print("  Safe mode: ComfyUI lowvram when headroom < 20 GB")
    print("  OOM prevention: Monitor with 'watch -n 5 nvidia-smi'")
    print()
    
    # OOM check
    print_separator("OOM Check (last 24h)")
    oom = subprocess.run(["dmesg", "-T"], capture_output=True, text=True, timeout=5)
    oom_events = [line for line in oom.stdout.split('\n') if 'out of memory' in line.lower() or 'oom' in line.lower()]
    if oom_events:
        for e in oom_events[-3:]:
            print(f"  {e.strip()}")
    else:
        print("  No OOM events detected")
    
    print("\n  [DONE]\n")

if __name__ == "__main__":
    main()
