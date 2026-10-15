# runpod-h3

RunPod の公式 ComfyUI イメージに、MiniMax H3(音声つき動画生成モデル)のモデル 7 本を自動で入れる起動スクリプトです。
RunPod のテンプレート「**MiniMax H3 ComfyUI 0.35 CUDA13 - Vidubus**」が、このリポジトリの `setup-h3.sh` を起動時に流します。

- 解説記事: (準備中 · note の記事 URL をここに入れます)
- テンプレート: https://console.runpod.io/deploy?template=uv8e4qky3x
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

## 注意

- ComfyUI のポート 8188 には認証がありません。URL を人に見せないでください。使い終わったら pod を Stop か Terminate してください
- 使い終わったら **Terminate** をおすすめします。Stop → Start は、同じマシンの GPU が埋まっていると再開できません(2026-10-15 に RTX PRO 4500 で再開できませんでした)
- Stop でモデルを残したいときだけ、Deploy の画面で **Add volume → Volume disk → 100 GB** を付けてください。付けないと `/workspace` は Container disk の中になり、Stop するとモデルが消えます
- GPU は CUDA 13 に対応したもの(RTX 5090 · RTX PRO 4500 など)を、Deploy の画面の **Additional filters → CUDA Versions = 13.0** で選んでください
- MiniMax H3 のモデルの利用規約は、各自で確認してください(自己責任でお使いください)

## English

`setup-h3.sh` is a start-up helper for a RunPod pod template. The template uses RunPod's official ComfyUI image (`runpod/comfyui:1.4.0-comfyuiv0.35.0-cuda13.0`) as is, and its start command runs this script in the background before handing over to the image's own `/start.sh`. The script waits until ComfyUI has been copied into `/workspace`, then downloads the seven MiniMax H3 files (64.96 GB, pinned revision of `Comfy-Org/MiniMax-H3`) with aria2c into `ComfyUI/models/`. Files that already exist with the correct size are skipped. It does not modify ComfyUI, torch or custom nodes. Progress is shown in the pod's Logs and in `/workspace/h3-setup.log`. Terminating the pod after use is recommended: a stopped pod cannot be restarted when its host's GPU has been taken. If you want the models to survive a Stop, add a Volume disk on the Deploy page (Add volume → Volume disk → 100 GB); otherwise `/workspace` lives on the container disk. Port 8188 has no authentication, so stop or terminate the pod when you are done. Check the MiniMax H3 model license yourself.

## License

MIT(このスクリプトだけ。モデルは MiniMax H3 のライセンスに従います)
