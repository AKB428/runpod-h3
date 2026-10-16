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
#   The pull shows "[ollama-setup] HH:MM:SS <model> 45% (3.0/6.7 GB)" every 10 s / 10 %; raw lines = /workspace/ollama-pull.log
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

  # Pull through the API (one JSON line per update). The raw lines go to /workspace/ollama-pull.log;
  # the Logs tab gets "<model> 45% (3.0/6.7 GB)" every 10 s or every 10 %.
  say "pull $OLLAMA_MODEL"
  gb() { local x=$(($1 / 100000000)); echo "$((x / 10)).$((x % 10))"; }
  pull_progress() {
    local line d pct now sum_t sum_c last_pct=-10 last_t=0 last_status=""
    declare -A tot=() com=()
    while IFS= read -r line; do
      echo "$line" >> /workspace/ollama-pull.log
      if [[ $line =~ \"error\":\"([^\"]*)\" ]]; then say "ERROR: pull: ${BASH_REMATCH[1]}"; return 1; fi
      if [[ $line =~ \"digest\":\"([^\"]+)\" ]]; then
        d=${BASH_REMATCH[1]}
        [[ $line =~ \"total\":([0-9]+) ]] && tot[$d]=${BASH_REMATCH[1]}
        [[ $line =~ \"completed\":([0-9]+) ]] && com[$d]=${BASH_REMATCH[1]}
        sum_t=0; sum_c=0
        for d in "${!tot[@]}"; do sum_t=$((sum_t + tot[$d])); sum_c=$((sum_c + ${com[$d]:-0})); done
        [ "$sum_t" -gt 0 ] || continue
        pct=$((sum_c * 100 / sum_t)); printf -v now "%(%s)T" -1
        if [ $((pct - last_pct)) -ge 10 ] || [ $((now - last_t)) -ge 10 ] || { [ "$pct" -eq 100 ] && [ "$last_pct" -ne 100 ]; }; then
          say "$OLLAMA_MODEL $pct% ($(gb $sum_c)/$(gb $sum_t) GB)"
          last_pct=$pct; last_t=$now
        fi
      elif [[ $line =~ \"status\":\"([^\"]*)\" ]] && [ "${BASH_REMATCH[1]}" != "$last_status" ]; then
        last_status=${BASH_REMATCH[1]}
        say "$OLLAMA_MODEL $last_status"
      fi
    done
  }
  curl -sN --fail-with-body http://127.0.0.1:11434/api/pull -d "{\"model\":\"$OLLAMA_MODEL\"}" </dev/null | pull_progress \
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
