#!/usr/bin/env bash
#
# Build an Apple Silicon (linux/arm64) Docker image of xiaozhi-esp32-server (server only).
#
# Upstream only publishes x86_64 images (server_0.8.2+), so we shallow-clone the
# upstream repo at a pinned tag, apply the "OTA websocket version:1" patch (see
# patches/0001-ota-websocket-version-1.patch and .suzukenz/findings-2026-07-25.md
# for why it's needed), and build locally following upstream's docs/docker-build.md.
#
# Re-running this script is safe: the clone is reset to a clean state before the
# patch is (re-)applied, and `docker build` is naturally idempotent/cached.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_DIR="$SCRIPT_DIR/upstream"
PATCH_DIR="$SCRIPT_DIR/patches"

UPSTREAM_REPO_URL="https://github.com/xinnan-tech/xiaozhi-esp32-server.git"
UPSTREAM_TAG="v0.9.6"
# Tags are mutable refs; pin the exact commit the tag pointed to when we verified
# this setup (2026-07-26) so a re-tagged upstream can't silently change what we build.
UPSTREAM_COMMIT="f5ed1aaec88471ba00ac778045331514066d63dc"

# Must match the FROM line in upstream's Dockerfile-server so the local build is
# picked up instead of (failing to) pull the x86_64-only image from ghcr.io.
BASE_IMAGE_TAG="ghcr.io/xinnan-tech/xiaozhi-esp32-server:server-base"
SERVER_IMAGE_TAG="xiaozhi-esp32-server:local-arm64"

PLATFORM="linux/arm64"

log() { printf '\033[1;34m[build.sh]\033[0m %s\n' "$*"; }

# --- 1. Fetch upstream source at the pinned tag ---------------------------------
if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  log "Cloning $UPSTREAM_REPO_URL @ $UPSTREAM_TAG into $UPSTREAM_DIR"
  git clone --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO_URL" "$UPSTREAM_DIR"
else
  log "upstream/ already exists; resetting to a clean $UPSTREAM_TAG checkout"
  git -C "$UPSTREAM_DIR" fetch --depth 1 origin tag "$UPSTREAM_TAG"
  git -C "$UPSTREAM_DIR" checkout --force "$UPSTREAM_TAG"
  git -C "$UPSTREAM_DIR" clean -fdx
fi

CURRENT_COMMIT="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [ "$CURRENT_COMMIT" != "$UPSTREAM_COMMIT" ]; then
  log "ERROR: upstream checkout is not at pinned commit $UPSTREAM_COMMIT (got: $CURRENT_COMMIT)"
  log "If upstream re-tagged $UPSTREAM_TAG, inspect the diff before updating UPSTREAM_COMMIT."
  exit 1
fi

# --- 2. Apply local patches in order (idempotent) --------------------------------
for PATCH_FILE in "$PATCH_DIR"/*.patch; do
  if git -C "$UPSTREAM_DIR" apply --check "$PATCH_FILE" 2>/dev/null; then
    log "Applying patch: $(basename "$PATCH_FILE")"
    git -C "$UPSTREAM_DIR" apply "$PATCH_FILE"
  elif git -C "$UPSTREAM_DIR" apply --check --reverse "$PATCH_FILE" 2>/dev/null; then
    log "Patch already applied, skipping: $(basename "$PATCH_FILE")"
  else
    log "ERROR: $(basename "$PATCH_FILE") does not apply cleanly to $UPSTREAM_TAG."
    exit 1
  fi
done

# --- 3. Build images (server-base, then server) following docs/docker-build.md ---
log "Building base image: $BASE_IMAGE_TAG ($PLATFORM)"
docker build \
  --platform "$PLATFORM" \
  -f "$UPSTREAM_DIR/Dockerfile-server-base" \
  -t "$BASE_IMAGE_TAG" \
  "$UPSTREAM_DIR"

log "Building server image: $SERVER_IMAGE_TAG ($PLATFORM)"
docker build \
  --platform "$PLATFORM" \
  -f "$UPSTREAM_DIR/Dockerfile-server" \
  -t "$SERVER_IMAGE_TAG" \
  "$UPSTREAM_DIR"

log "Done. Image ready: $SERVER_IMAGE_TAG"
log "Next: ./download-model.sh, then copy data/.config.yaml.example to data/.config.yaml and fill in your API key, then: docker compose up -d"
