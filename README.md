# runpod-h3

RunPod の公式 ComfyUI イメージに、MiniMax H3(音声つき動画生成モデル)のモデル 7 本を自動で入れる起動スクリプトです。
RunPod のテンプレート「**Vidubus MiniMax H3 ComfyUI 0.35 CUDA13**」が、このリポジトリの `setup-h3.sh` を起動時に流します。
Ollama(gemma4:12b-it-qat)も同じ pod に入れるオールイン版「**Vidubus MiniMax H3 Ollama ComfyUI 0.35 CUDA13**」もあります(`setup-h3-ollama.sh` · [下の節](#オールイン版ollama-込み))。

- 解説記事: (準備中 · note の記事 URL をここに入れます)
- テンプレート: https://console.runpod.io/deploy?template=uv8e4qky3x
- テンプレート(オールイン版): https://console.runpod.io/deploy?template=74lrexbk5l
- Vidubus(日本語で頼むと H3 の動画ができるローカルアプリ): https://vidubus.pages.dev/

## 何をするか

1. pod が起動すると、RunPod 公式の `/start.sh` がいつもどおり ComfyUI を立ち上げます(ポート 8188)
2. その裏で `setup-h3.sh` が、ComfyUI のフォルダができるのを待ってから、Hugging Face の [Comfy-Org/MiniMax-H3](https://huggingface.co/Comfy-Org/MiniMax-H3) からモデル 7 本(64.96 GB)を aria2c で落とします
3. 2 回目の起動(Stop → Start · Network Volume)では、大きさが合っているファイルは落とし直しません

| 置き場所(`ComfyUI/models/`) | ファイル |
| --- | --- |
| diffusion_models | minimax_h3_fl2va_pruned_int8_convrot.safetensors · minimax_h3_ref2va_pruned_int8_convrot.safetensors |
| text_encoders | qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors |
| vae | minimax_h3_video_vae_int8_convrot.safetensors · minimax_h3_audio_vae_fp32.safetensors |
| loras | minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors · minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors |

- ComfyUI 本体 · torch · カスタムノードには触りません。モデルを落とすだけです
- テンプレートのイメージは `runpod/comfyui:1.4.0-comfyuiv0.35.0-cuda13.0`(RunPod 公式 · ComfyUI 0.35.0)を指しています
- Hugging Face のリビジョンは固定しています(`e5eb578a…` · 2026-09-29)
- 進み具合は RunPod の画面の **Logs**(`[h3-setup]` の行)と `/workspace/h3-setup.log` に出ます。`H3 models ready` が出たら完了です

## テンプレートの設定

| 項目 | 値 |
| --- | --- |
| Container image | `runpod/comfyui:1.4.0-comfyuiv0.35.0-cuda13.0` |
| Container start command | 下の JSON |
| Container disk | 150 GB |
| Volume disk | 100 GB · `/workspace` |
| HTTP ports | 8188(ComfyUI) |
| Environment variables | なし |

```json
{
  "entrypoint": ["bash", "-c"],
  "cmd": ["curl -fsSL --retry 5 -o /tmp/setup-h3.sh https://raw.githubusercontent.com/AKB428/runpod-h3/ca84611c456edba735bef4253cba7fdd6711fd8e/setup-h3.sh && (bash /tmp/setup-h3.sh &); exec /start.sh"]
}
```

URL はこのリポジトリのコミットで固定しています(`main` は指しません)。スクリプトを直したら、テンプレートの URL を新しいコミットに書き換えます。

## オールイン版(Ollama 込み)

ComfyUI(8188)と Ollama(11434)を 1 つの pod に入れます。Vidubus の接続設定で、Ollama と ComfyUI の両方をこの pod に向けられます(手元の PC に GPU が要りません)。

1. `setup-h3-ollama.sh` が apt で aria2 と zstd を入れる
2. Ollama **0.32.13** を `/workspace/ollama/0.32.13` に展開し、`0.0.0.0:11434` で起動する(落ちたら 3 秒後に立て直す)
3. `gemma4:12b-it-qat` を落とす(`/workspace/ollama/models` · 約 7 GB)
4. 隣の `setup-h3.sh` で H3 のモデル 7 本を落とす(上と同じ)
5. Logs に `[ollama-setup] … all ready: ComfyUI 8188 + Ollama 11434 (gemma4:12b-it-qat)` が出たら完了

- Ollama の版は 0.32.13 に固定しています。0.32.14 以降は、コア数の多いホストのコンテナの中で生成が数倍遅くなります(2026-09-28 に RunPod で実測)
- モデルは `gemma4:12b-it-qat` だけです(切り替えの仕組みはありません)。ほかのモデルが欲しいときは、Web terminal から `OLLAMA_HOST=127.0.0.1:11434 /workspace/ollama/0.32.13/bin/ollama pull <名前>` で足せます
- Vidubus の「VRAM を空ける」(Ollama タブ / ComfyUI タブ)は **2 つとも ON のまま**にしてください。OFF にすると H3 が VRAM を占めたままになり、英語プロンプトが 4.7 tok/s まで落ちました(RTX PRO 4500 · 2026-10-16)
- 2 回目の起動(Volume disk)では、Ollama と gemma が揃っていれば落とし直しません
- 進み具合 = Logs と `/workspace/ollama-setup.log`(Ollama 自体のログ = `/workspace/ollama-serve.log`)

| 項目 | 値 |
| --- | --- |
| Container image | `runpod/comfyui:1.4.0-comfyuiv0.35.0-cuda13.0` |
| Container start command | 下の JSON |
| Container disk | 150 GB |
| Volume disk | 100 GB · `/workspace` |
| HTTP ports | 8188(ComfyUI)· 11434(Ollama) |
| Environment variables | なし |

```json
{
  "entrypoint": ["bash", "-c"],
  "cmd": ["curl -fsSL --retry 5 -o /tmp/setup-h3.sh https://raw.githubusercontent.com/AKB428/runpod-h3/cab9e5a1e1a3174259e910eda1bd91c1fc09fcf0/setup-h3.sh && curl -fsSL --retry 5 -o /tmp/setup-h3-ollama.sh https://raw.githubusercontent.com/AKB428/runpod-h3/cab9e5a1e1a3174259e910eda1bd91c1fc09fcf0/setup-h3-ollama.sh && (bash /tmp/setup-h3-ollama.sh &); exec /start.sh"]
}
```

実測(2026-10-16 · RTX PRO 4500 Blackwell · Secure): Deploy → Ollama が外から応答 1 分 21 秒 → gemma 揃い 3 分 → H3 の 7 本揃い · all ready **13 分**。Vidubus のシンプルモード 1 本(864×480 · 5 秒 · turbo)= 英語プロンプト 53〜85 秒 + 動画 224〜227 秒。

## 注意

- ComfyUI のポート 8188(オールイン版は Ollama の 11434 も)には認証がありません。URL を人に見せないでください。使い終わったら pod を Stop か Terminate してください
- 使い終わったら **Terminate** をおすすめします。Stop → Start は、同じマシンの GPU が埋まっていると再開できません(2026-10-15 に RTX PRO 4500 で再開できませんでした)
- Stop でモデルを残したいときだけ、Deploy の画面で **Add volume → Volume disk → 100 GB** を付けてください。付けないと `/workspace` は Container disk の中になり、Stop するとモデルが消えます
- GPU は CUDA 13 に対応したもの(RTX 5090 · RTX PRO 4500 など)を、Deploy の画面の **Additional filters → CUDA Versions = 13.0** で選んでください
- MiniMax H3 のモデル(オールイン版は Gemma も)の利用規約は、各自で確認してください(自己責任でお使いください)

## English

`setup-h3.sh` is a start-up helper for a RunPod pod template. The template uses RunPod's official ComfyUI image (`runpod/comfyui:1.4.0-comfyuiv0.35.0-cuda13.0`) as is, and its start command runs this script in the background before handing over to the image's own `/start.sh`. The script waits until ComfyUI has been copied into `/workspace`, then downloads the seven MiniMax H3 files (64.96 GB, pinned revision of `Comfy-Org/MiniMax-H3`) with aria2c into `ComfyUI/models/`. Files that already exist with the correct size are skipped. It does not modify ComfyUI, torch or custom nodes. Progress is shown in the pod's Logs and in `/workspace/h3-setup.log`. Terminating the pod after use is recommended: a stopped pod cannot be restarted when its host's GPU has been taken. If you want the models to survive a Stop, add a Volume disk on the Deploy page (Add volume → Volume disk → 100 GB); otherwise `/workspace` lives on the container disk. Port 8188 has no authentication, so stop or terminate the pod when you are done. Check the MiniMax H3 model license yourself.

The all-in variant (`setup-h3-ollama.sh`, template `74lrexbk5l`) additionally installs Ollama 0.32.13 (pinned: later versions run several times slower inside containers on many-core hosts), pulls `gemma4:12b-it-qat`, serves it on `0.0.0.0:11434` (no authentication) and then runs `setup-h3.sh`. Wait for `[ollama-setup] … all ready` in the Logs (about 13 minutes on an RTX PRO 4500). Check the Gemma license as well.

## License

MIT(このスクリプトだけ。モデルは MiniMax H3 のライセンスに従います)
