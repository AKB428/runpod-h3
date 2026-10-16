#!/usr/bin/env bash
# setup-h3-ollama.sh — All-in template: Ollama (pinned version) + gemma4:12b-it-qat, then the 7 MiniMax H3 models.
# オールインのテンプレート用。Ollama(版を固定)と gemma4:12b-it-qat を入れて 11434 で起動し、
# そのあと setup-h3.sh で MiniMax H3 のモデル 7 本を入れる。
#
# - Runs in the background from the template's start command; ComfyUI (/start.sh) starts without waiting.
# - Expects setup-h3.sh next to this file (the start command downloads both from the same commit).
# - Ollama listens on 0.0.0.0:11434 (no authentication). Models go to /workspace/ollama/models.
# - Ollama is pinned to 0.32.13: from 0.32.14 on, generation inside a container gets several times slower
#   (CPU thread pool spins on a host with many cores; measured on RunPod 2026-09-28).
# - Files that already exist are skipped (2nd boot / Volume disk).
# - Log: RunPod "Logs" tab and /workspace/ollama-setup.log (+ /workspace/h3-setup.log)
set -u
OLLAMA_VER=0.32.13
OLLAMA_MODEL=gemma4:12b-it-qat
ODIR=/workspace/ollama
OBIN=$ODIR/$OLLAMA_VER/bin/ollama
LOG=/workspace/ollama-setup.log
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$ODIR/models"
exec > >(tee -a "$LOG") 2>&1
say() { echo "[ollama-setup] $(date -u +%H:%M:%S) $*"; }

say "start (Ollama $OLLAMA_VER + $OLLAMA_MODEL)"

# aria2 (for setup-h3.sh) and zstd (Ollama's tar.zst) in one apt run
need=""
command -v aria2c >/dev/null || need="$need aria2"
command -v zstd   >/dev/null || need="$need zstd"
if [ -n "$need" ]; then
  { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $need >/dev/null; } </dev/null \
    || say "apt failed:$need"
fi

if [ -x "$OBIN" ]; then
  say "skip Ollama $OLLAMA_VER (already in $ODIR/$OLLAMA_VER)"
else
  say "get  Ollama $OLLAMA_VER"
  mkdir -p "$ODIR/$OLLAMA_VER"
  curl -fsSL --retry 5 "https://github.com/ollama/ollama/releases/download/v$OLLAMA_VER/ollama-linux-amd64.tar.zst" </dev/null \
    | zstd -d | tar -xf - -C "$ODIR/$OLLAMA_VER" \
    || { say "ERROR: Ollama download failed"; rm -rf "$ODIR/$OLLAMA_VER"; }
fi

if [ -x "$OBIN" ]; then
  # Keep serve running: restart it if it ever exits. Its own log is /workspace/ollama-serve.log
  setsid bash -c "while true; do
      OLLAMA_HOST=0.0.0.0:11434 OLLAMA_ORIGINS='*' OLLAMA_MODELS='$ODIR/models' '$OBIN' serve
      echo \"[ollama-serve] exited \$?, restarting in 3s\"; sleep 3
    done" >> /workspace/ollama-serve.log 2>&1 </dev/null &
  for i in $(seq 1 60); do curl -sf http://127.0.0.1:11434/api/version >/dev/null && break; sleep 1; done
  say "serve $(curl -s http://127.0.0.1:11434/api/version) on 0.0.0.0:11434"

  say "pull $OLLAMA_MODEL"
  OLLAMA_HOST=127.0.0.1:11434 "$OBIN" pull "$OLLAMA_MODEL" >> /workspace/ollama-pull.log 2>&1 </dev/null \
    || say "ERROR: pull failed (see /workspace/ollama-pull.log)"
  if OLLAMA_HOST=127.0.0.1:11434 "$OBIN" list 2>/dev/null | grep -q "^$OLLAMA_MODEL "; then
    say "Ollama ready ($OLLAMA_MODEL · $(du -sh "$ODIR/models" | cut -f1))"
  else
    say "ERROR: $OLLAMA_MODEL not found after pull"
  fi
fi

# Then the H3 models (same script as the ComfyUI-only template)
bash "$HERE/setup-h3.sh"
say "all ready: ComfyUI 8188 + Ollama 11434 ($OLLAMA_MODEL)"
