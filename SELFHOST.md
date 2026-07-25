# StackChan セルフホスト版 (このフォークについて)

これは [m5stack/StackChan](https://github.com/m5stack/StackChan) のフォークです。
本家の AI Agent（xiaozhi.me クラウド）を、自分で立てたサーバー経由の外部API（LLM/ASR/TTS）に
差し替えるための変更を加えています。ファーム自体のロジックは変更しておらず、接続先URLの
オーバーレイ設定と、サーバー側リポジトリ（`infra/xiaozhi-server/`）の追加のみです。

> 「スタックチャン」「stack-chan」は石川真也氏 (@meganetaaan) の登録商標です。本フォークは
> 本家 [meganetaaan/stack-chan](https://github.com/meganetaaan/stack-chan) および
> [m5stack/StackChan](https://github.com/m5stack/StackChan) の成果物を利用しています。
> 商用目的ではない個人利用の改造です。

---

## 0. 工場出荷状態への戻し方（最優先で確認しておくこと）

実機を改造する前に、いつでも工場出荷ファームに戻せることを確認してください。

### 方法A: M5Burner で書き戻す（推奨・一番簡単）

1. [M5Burner](https://docs.m5stack.com/en/download) をインストールする
2. 「Only Official」タブで **StackChan** を検索する
3. 一覧から **StackChan-UserDemo** を選択して書き込む（これが工場出荷ファーム）

### ダウンロードモードへの入り方

1. 本体の **RSTボタンを約3秒長押し** する
2. 内部の **緑色LEDが点灯**し、ダウンロードモード（書き込み待ち）になる
3. **microSDカードスロット付近**にある基板側の状態を確認しつつ操作する（外装を外さない場合はUSB経由でも認識されることが多い）
4. **USB-Cケーブルはベース（土台）側のポートに挿す**ことを推奨（本体側だと認識しないことがある）

### 方法B: esptool で自前バックアップ／書き戻し

改造前に必ず自分の実機のフルバックアップを取得しておくことを強く推奨します
（M5Burner配布のファームと手元の実機に個体差・バージョン差がある可能性があるため）。

```bash
# バックアップ取得（フラッシュ全体 16MB を吸い出す。ポートは環境に合わせる）
esptool.py --chip esp32s3 --port /dev/tty.usbmodemXXXX --baud 1500000 \
  read_flash 0 0x1000000 stackchan-factory-backup.bin

# 書き戻し（フルフラッシュ書き込み）
esptool.py --chip esp32s3 --port /dev/tty.usbmodemXXXX --baud 1500000 \
  write_flash 0x0 stackchan-factory-backup.bin
```

バックアップファイルは秘密情報ではありませんが、容量が大きいため git 管理には含めず、
別途（外付けディスク等）で保管してください。

---

## 1. 概要とアーキテクチャ

本フォークでは、ファーム内蔵の AI Agent（実体は `xiaozhi-esp32` プロトコル）の接続先を
公式クラウド（`api.tenclass.net`）から、自分で管理するサーバーに向け直します。

```
┌─────────────────────┐   CONFIG_OTA_URL (sdkconfig.defaults.local)
│ StackChan 実機        │──────────────────────────────────┐
│ (xiaozhi-esp32 v2.2.4 │                                   │
│  組み込みファーム)      │◀───── WebSocket (音声/イベント) ───┤
└─────────────────────┘                                   │
                                                            ▼
                                    ┌──────────────────────────────────┐
                                    │ セルフホスト                        │
                                    │ xiaozhi-esp32-server (Docker)      │
                                    │ infra/xiaozhi-server/              │
                                    │                                    │
                                    │  ASR : SenseVoice (ja, ローカル)    │
                                    │  LLM : Gemini                      │
                                    │        (OpenAI互換エンドポイント)   │
                                    │  TTS : EdgeTTS (ja-JP-NanamiNeural) │
                                    └──────────────────────────────────┘
```

- ファーム側は接続先URL（`CONFIG_OTA_URL`）を書き換えるだけで、xiaozhi-esp32 側のロジックには
  一切手を入れていません。OTA応答から WebSocket 接続先を受け取る仕組みをそのまま利用しています。
- サーバー側は [xinnan-tech/xiaozhi-esp32-server](https://github.com/xinnan-tech/xiaozhi-esp32-server)
  をベースに、Apple Silicon 向けローカルビルドとプロトコル互換パッチを当てたものです。
- 詳細な調査記録・意思決定の経緯は `.suzukenz/findings-2026-07-25.md`（個人用メモ、リポジトリには
  含まれません）を参照してください。

---

## 2. セットアップ手順

### 2.1 サーバー側

詳細手順は `infra/xiaozhi-server/README.md` を参照してください。要点のみ以下に記載します。

1. `infra/xiaozhi-server/build.sh` で Apple Silicon 向けにローカルビルド
   （上流は `server_0.8.2` 以降 x86_64 イメージのみ配布のため）
2. 必要なら `infra/xiaozhi-server/download-model.sh` でローカルASR（SenseVoiceSmall）モデルを取得
3. `cp infra/xiaozhi-server/data/.config.yaml.example infra/xiaozhi-server/data/.config.yaml`
   を作成し、`<LAN_IP>` や APIキー等のプレースホルダを埋める（このファイルは gitignore 済み）
4. `docker compose up -d` で起動。ログに以下のような行が出れば起動成功:
   ```
   OTA接口是           http://<LAN_IP>:8003/xiaozhi/ota/
   Websocket地址是     ws://<LAN_IP>:8000/xiaozhi/v1/
   ```
5. `curl` でOTAエンドポイントの応答を確認（`infra/xiaozhi-server/README.md` の手順参照）

### 2.2 ファーム側

1. ESP-IDF **v5.5.4** を構築する（バージョン厳守。`firmware/README.md` 記載）
   ```bash
   . ~/esp/esp-idf/export.sh   # 環境ごとにパスは異なる
   ```
2. 依存取得
   ```bash
   cd firmware
   python3 ./fetch_repos.py
   ```
3. 接続先オーバーレイを作成
   ```bash
   cp sdkconfig.defaults.local.example sdkconfig.defaults.local
   # CONFIG_OTA_URL を自サーバーの http://<LAN_IP>:8003/xiaozhi/ota/ に書き換える
   ```
4. ビルド・書き込み
   ```bash
   idf.py build
   idf.py flash
   ```

> ⚠️ **sdkconfig の罠（必読）**: `sdkconfig.defaults.local` は `SDKCONFIG_DEFAULTS` として
> 読み込まれますが、これは **「まだ確定していない設定項目」にしか効きません**。すでに
> `firmware/sdkconfig`（一度ビルドすると生成される確定済み設定ファイル）に値が書き込まれて
> いる場合、`sdkconfig.defaults.local` を後から変更しても再ビルドだけでは反映されません。
>
> `sdkconfig.defaults.local` を新規作成した時・内容を変更した時は、必ず以下を実行してください:
> ```bash
> rm firmware/sdkconfig
> idf.py fullclean
> idf.py build
> ```

---

## 3. 既知の制約

- **公式OTAは使えません**。今後のファームアップデートは自前で `fetch_repos.py` → ビルド →
  書き込みを行う必要があります。
- **上流リポジトリは市販ファームより更新が遅れることがあります**（実測: 手元の市販ファームは
  `v1.4.4` 表示だったが、フォーク元の `m5stack/StackChan` main は `v1.4.3` 相当だった）。
- **StackChan World アプリ連携、映像視聴、アプリストア等の M5Stack クラウド機能は動作しません**。
  これらは `CONFIG_STACKCHAN_SERVER_URL`（`http://47.113.125.164:12800` 系のエコシステムAPI）が
  前提であり、AIエージェントの接続先とは別系統です。本フォークではこの値は変更していません。
  自前で動かすには `server/`（Go バックエンド）を別途セルフホストする必要がありますが、本フォークの
  スコープ外です。
- xiaozhi.me（公式クラウド）にペアリング済みの実機は、NVSに残ったプロトコルバージョン情報が
  原因で「WebSocketは繋がるが音声が通らない」症状が出ることがあります。対策はサーバー側パッチ
  （`infra/xiaozhi-server/patches/0001-ota-websocket-version-1.patch`）適用、または
  `idf.py erase-flash` によるNVS全消去です。詳細は `infra/xiaozhi-server/README.md` 参照。

---

## 4. 上流追従方針

このフォークは、フォーク時点で `m5stack/StackChan` の履歴とコミット単位で完全に一致しています
（フォーク後にこのリポジトリ独自のコミットはまだありません）。フォーク時点（＝現時点の上流最新）
のコミットハッシュ:

```
b72b3ed  Merge pull request #100 from m5stack/firmware-dev
```

今後、上流の更新を取り込む場合は以下の運用を想定しています。

```bash
git remote add upstream https://github.com/m5stack/StackChan.git
git fetch upstream
git merge upstream/main
```

- 変更は「接続先オーバーレイ（`firmware/sdkconfig.defaults.local.example` と関連 `.gitignore`）」
  「サーバーリポジトリ追加（`infra/`）」「本ドキュメント」に限定し、上流ファイル自体（firmware の
  ロジック等）にはできるだけ手を入れないことで、マージコンフリクトを最小化しています。
- ルート README.md への変更も最上部の短い注記のみに留めています。

---

## 5. クレジット

- 「スタックチャン」「stack-chan」は石川真也氏（[@meganetaaan](https://github.com/meganetaaan)）の
  登録商標です。本家プロジェクト: https://github.com/meganetaaan/stack-chan
- 本フォークの元になった M5Stack 公式リポジトリ: https://github.com/m5stack/StackChan
- サーバー実装のベース: https://github.com/xinnan-tech/xiaozhi-esp32-server
- デバイス側AIエージェントの上流: https://github.com/78/xiaozhi-esp32
