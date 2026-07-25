# xiaozhi-esp32-server (self-hosted, Apple Silicon)

StackChan Phase 1: run [xinnan-tech/xiaozhi-esp32-server](https://github.com/xinnan-tech/xiaozhi-esp32-server)
(tag `v0.9.6` / image tag `server_0.9.6`) locally in Docker, server-only (no manager-web/DB/redis).

Background and design decisions: `.suzukenz/findings-2026-07-25.md`.

## Why a local build

Upstream only publishes `x86_64` images from `server_0.8.2` onward
(see upstream `docs/Deployment.md` / `docs/docker-build.md`). On Apple Silicon we
must build the `linux/arm64` image ourselves.

## Why the version:1 patch

xiaozhi-esp32 firmware (v2.2.4) defaults to WebSocket protocol **version 1** and only
changes it when the OTA response tells it to. The official Xiaozhi cloud server sends
version 2/3, and once a device has connected to it, that value is cached in the
device's NVS. If it then connects to this self-hosted server (which only implements
version 1) it will keep using the stale NVS value, resulting in "WebSocket connects
but no audio flows". The upstream OTA handler doesn't send a `version` field, so it
never overwrites that stale value.

`patches/0001-ota-websocket-version-1.patch` adds `"version": 1` to the `websocket`
object in the OTA response (`core/api/ota_handler.py`), forcing every device back to
version 1 on every OTA check-in. Applied automatically by `build.sh`.

## Setup

### 1. Build the image

```bash
./build.sh
```

This shallow-clones upstream at tag `v0.9.6` into `upstream/` (gitignored), applies
the patch, and builds `xiaozhi-esp32-server:local-arm64` following upstream's
`docs/docker-build.md` (build `Dockerfile-server-base` then `Dockerfile-server`).
Re-running is safe — the clone is reset to a clean tagged checkout each time.

Requires Docker running for `linux/arm64` (Docker Desktop, or Colima started with
`colima start --arch aarch64`). The build compiles/pulls `torch`, `funasr`, `sherpa_onnx`
etc. and can take several minutes.

### 2. Download the local ASR model

```bash
./download-model.sh
```

Downloads `models/SenseVoiceSmall/model.pt` (~950MB) from ModelScope. Skip this if
you switch `ASR` to a cloud provider (e.g. `OpenaiASR`, `GroqASR`) in your config.

### 3. Configure

```bash
cp data/.config.yaml.example data/.config.yaml
```

Edit `data/.config.yaml` (gitignored — this is where secrets and machine-specific
values live):

- `server.websocket`: replace `<LAN_IP>` with this Mac's LAN IP address
  (`ipconfig getifaddr en0`, or check System Settings > Network). This is the address
  the OTA endpoint hands out to devices, so it must be reachable on your LAN.
- `LLM.GeminiLLM.model_name`: a current Gemini model ID (default: `gemini-3.5-flash`).
- `LLM.GeminiLLM.api_key`: your Gemini API key (https://aistudio.google.com/apikey).

This file is a partial overlay: xiaozhi-esp32-server deep-merges it over the image's
built-in `config.yaml`, so you only need to specify the keys you're changing.

### 4. Run

```bash
docker compose up -d
docker compose logs -f xiaozhi-esp32-server
```

The log should show lines like:

```
OTA接口是           http://<LAN_IP>:8003/xiaozhi/ota/
Websocket地址是     ws://<LAN_IP>:8000/xiaozhi/v1/
```

### 5. Verify the OTA endpoint

```bash
curl -s -X POST http://localhost:8003/xiaozhi/ota/ \
  -H 'device-id: 11:22:33:44:55:66' \
  -H 'client-id: test-client' \
  -H 'Content-Type: application/json' \
  -d '{}' | python3 -m json.tool
```

Confirm the response contains:

- `websocket.url` — should match `ws://<LAN_IP>:8000/xiaozhi/v1/` from your config
- `websocket.version` — must be `1` (this is what the patch adds; if it's missing,
  the patch wasn't applied/built correctly)

### 6. Point a device at it

Configure the ESP32 firmware's OTA URL to `http://<LAN_IP>:8003/xiaozhi/ota/`
(see `firmware/sdkconfig.defaults.local.example`, Phase 2). If the device was ever
paired with the official cloud server, either rely on the version:1 patch above, or
fully erase NVS (`idf.py erase-flash`) to be safe.

## Notes

- ASR/TTS/LLM key names and defaults were confirmed against the actual upstream
  `v0.9.6` source (`main/xiaozhi-server/config.yaml`), not assumed.
- `Intent: function_call` requires the LLM to support tool calling. **Do not use
  the native `gemini` provider** — its SDK rejects the `minimum`/`maximum` fields
  present in the device's MCP tool schemas (`Unknown field for Schema: minimum`),
  which silently fails every LLM call and surfaces as a Chinese stock error phrase
  even for plain chit-chat. Use `type: openai` against Gemini's OpenAI-compatible
  endpoint instead (see `data/.config.yaml.example`), which accepts the same JSON
  Schema tool definitions without issue. If commands like volume control / exit
  words silently fail while chit-chat works, fall back to `Intent: intent_llm` or
  `Intent: nointent`.
- Reference for a near-identical setup: https://blog.rpine.net/posts/stackchan-local-llm
