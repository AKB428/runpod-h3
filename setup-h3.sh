#!/usr/bin/env bash
# setup-h3.sh — Put the 7 MiniMax H3 model files (64.96 GB) into RunPod's official ComfyUI image.
# RunPod 公式の ComfyUI イメージに MiniMax H3 のモデル 7 本(64.96 GB)を入れる。
#
# - Runs in the background from the template's start command; ComfyUI (/start.sh) starts without waiting.
# - Does NOT touch ComfyUI itself, torch, or custom nodes. Only downloads model files.
# - Files that already exist with the right size are skipped (2nd boot / Network Volume).
# - Log: RunPod "Logs" tab and /workspace/h3-setup.log
set -u
COMFY=/workspace/runpod-slim/ComfyUI
LOG=/workspace/h3-setup.log
REV=e5eb578a89295337b8ff433a035929ce0279e0b6   # Comfy-Org/MiniMax-H3 revision (2026-09-29)
HF=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/$REV
FILES="
diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors 20970379616
diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors 20970379616
text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors 15687142551
vae/minimax_h3_video_vae_int8_convrot.safetensors 2811065184
vae/minimax_h3_audio_vae_fp32.safetensors 605254808
loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors 1956193000
loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors 1956193000
"
mkdir -p /workspace
exec > >(tee -a "$LOG") 2>&1
say() { echo "[h3-setup] $(date -u +%H:%M:%S) $*"; }

say "start (driver CUDA $(nvidia-smi 2>/dev/null | grep -o 'CUDA Version: [0-9.]*' | cut -d' ' -f3))"

# Wait until /start.sh has copied ComfyUI into /workspace (the venv exists = copy finished)
for i in $(seq 1 120); do [ -d "$COMFY/.venv-cu128" ] && break; sleep 5; done
[ -d "$COMFY/models" ] || { say "ERROR: ComfyUI not found at $COMFY"; exit 1; }

if ! command -v aria2c >/dev/null; then
  { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq aria2 >/dev/null; } </dev/null \
    || say "aria2 unavailable, falling back to curl (slow)"
fi

echo "$FILES" | while read -r f size; do
  [ -n "$f" ] || continue
  dst="$COMFY/models/$f"
  if [ "$(stat -c %s "$dst" 2>/dev/null)" = "$size" ]; then say "skip $f"; continue; fi
  mkdir -p "$(dirname "$dst")"
  say "get  $f ($((size / 1000000000)) GB)"
  if command -v aria2c >/dev/null; then
    aria2c -c -x16 -s16 -k1M --console-log-level=warn --summary-interval=60 \
      -d "$(dirname "$dst")" -o "$(basename "$dst")" "$HF/$f" </dev/null
  else
    curl -fsSL -C - --retry 5 -o "$dst" "$HF/$f" </dev/null
  fi
  [ "$(stat -c %s "$dst" 2>/dev/null)" = "$size" ] || say "ERROR: size mismatch $f"
done
say "H3 models ready ($(du -sh "$COMFY/models" | cut -f1))"
