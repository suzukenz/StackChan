#!/usr/bin/env bash
#
# Download the SenseVoiceSmall ASR model weights used by ASR.FunASR (type: fun_local)
# in data/.config.yaml.example. Only needed if you keep ASR local; skip this if you
# switch to a cloud ASR provider (OpenaiASR, GroqASR, ...).
#
# Safe to re-run: skips the download if the file already exists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$SCRIPT_DIR/models/SenseVoiceSmall"
MODEL_PATH="$MODEL_DIR/model.pt"
MODEL_URL="https://modelscope.cn/models/iic/SenseVoiceSmall/resolve/master/model.pt"
# SHA256 of the model.pt we verified working on 2026-07-26 (.pt files are pickle-based
# and can execute code when loaded, so an unverified download is a supply-chain risk).
# If upstream legitimately updates the model, re-verify and update this hash.
MODEL_SHA256="833ca2dcfdf8ec91bd4f31cfac36d6124e0c459074d5e909aec9cabe6204a3ea"

log() { printf '\033[1;34m[download-model.sh]\033[0m %s\n' "$*"; }

mkdir -p "$MODEL_DIR"

if [ -s "$MODEL_PATH" ]; then
  log "Already present: $MODEL_PATH (skipping)"
  exit 0
fi

log "Downloading SenseVoiceSmall model.pt from $MODEL_URL"
curl -fL --retry 3 -o "$MODEL_PATH.tmp" "$MODEL_URL"

ACTUAL_SHA256="$(shasum -a 256 "$MODEL_PATH.tmp" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$MODEL_SHA256" ]; then
  log "ERROR: SHA256 mismatch for model.pt"
  log "  expected: $MODEL_SHA256"
  log "  actual:   $ACTUAL_SHA256"
  log "Refusing to install. Delete $MODEL_PATH.tmp after inspecting it."
  exit 1
fi

mv "$MODEL_PATH.tmp" "$MODEL_PATH"
log "Saved to $MODEL_PATH (sha256 verified)"
