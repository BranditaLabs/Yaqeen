# On-device models

Yaqeen ships no model in the app bundle. The recitation model below is downloaded on request,
checked by SHA-256, and runs entirely on the phone (docs/SECURITY_PRIVACY.md item 11).

## Recitation recognition — `yaqeen-asr-v1` («تسميع», voice «تحفيظ», recordings)

| | |
| --- | --- |
| Weights | [`tarteel-ai/whisper-tiny-ar-quran`](https://huggingface.co/tarteel-ai/whisper-tiny-ar-quran) at revision `c3d7e624af5c81bef25a10a2af3a5a84cb4dd0f0` — Whisper tiny (37 M parameters) fine-tuned by Tarteel on Quran recitation |
| Licence | **Apache-2.0** (model card `license: apache-2.0`, checked 2026-11-14) — commercial use, modification and redistribution allowed with the licence and notices kept. The card does not name its training data ("None dataset"); its reported WER is 7.05 % on Tarteel's own evaluation set. |
| Base model | `openai/whisper-tiny` (MIT) |
| Exporter | sherpa-onnx `scripts/whisper/export-onnx.py` at commit `7be9a38e275ece9ee9a9277cc78295f2cbfd6673` (Apache-2.0), SHA-256 `5e0ddabf…bf976e45` |
| Runtime | `sherpa_onnx` 2.0.1 (Flutter, Apache-2.0) on Android and iOS; microphone `record` 7.2 (BSD-3-Clause) |
| VAD | Silero VAD (MIT), sherpa-onnx release asset `asr-models/silero_vad.onnx` |
| Conversion | `tools/asr/convert.py` (pinned, deterministic): HF → openai-whisper (strict load) → sherpa export → logits rewritten as `MatMul(x, Wᵀ)` (checked equal to the export, max \|Δ\| 1.1e-5) → int8 dynamic quantisation of every MatMul → the token lookup reads the same int8 embedding (`Gather → Transpose → DequantizeLinear`) instead of an 80 MB fp32 copy |
| Decoding | language `ar`, task `transcribe`, greedy search, 2 threads |
| Hosting | `ASR_MODEL_BASE_URL` (dart-define) → a folder with the files below. Without it, development builds download the interim export (`AsrModelManifest.interim`, same tarteel weights converted by a third party with sherpa's exporter, MatMul-only int8, 104 MB, pinned revision `cb901509…` of `kasimyazan/sherpa-tarteel-whisper-tiny-ar-quran`, no licence file of its own — **not for production**). |

### Files (`tools/asr/manifest.json`, pinned in `apps/mobile/lib/core/platform/asr/asr_model.dart`)

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `yaqeen-asr-v1-encoder.int8.onnx` | 12 926 470 | `d3b05195086f02c565084638faa1d5d1710b63ea8703201246c9fb4f0207ab42` |
| `yaqeen-asr-v1-decoder.int8.onnx` | 30 099 011 | `2b983686b02c7cad345b2d399aea0180f66e0c754ca5709b1ab5dd0d25f68fe2` |
| `yaqeen-asr-v1-tokens.txt` | 866 987 | `febeed8e568f92d9ca984580bc2e6b605b867dc5ba4486f9646de381b44a8226` |
| `silero_vad.onnx` | 643 854 | `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` |
| **Total** | **44.5 MB** | one download for «تسميع», «تحفيظ» and recordings |

Re-running `convert.py` reproduces these hashes byte for byte (checked twice). A new conversion is a
new model id: update the manifest, the constants in `asr_model.dart` and this table together.

### Ship gate (spec §6.8: ≥ 90 % word accuracy) — `tools/asr/eval/eval.py`

Measured 2026-11-14 on a Windows laptop (Intel, 2 threads, real-time factor 0.31 — phones are
slower; the app measures its own and falls back to «سمّع ثم تحقّق» above 0.8). Same model, same
decoding settings, transcripts aligned with a port of the app's `RecitationAligner`.

| Set | Words | Accuracy |
| --- | ---: | ---: |
| 4 reciters (QF catalogue: Alafasy, AbdulBaset murattal, Minshawi murattal, Husary) × 7 surahs (1, 67, 103, 108, 112–114), per-ayah cuts — **ours** (int8 embedding) | 1 776 | **95.5 %** (74 «تنبيه», 6 not heard) |
| Same, interim export (fp32 embedding) | 1 776 | 95.4 % |
| Same audio replayed as whole surahs the way the app judges live (segments cut by pauses, each decoded when it ends) | 1 776 | LIVE_RESULT |
| Users' own voices on phones (`--local`) | — | **not measured yet** |

- The int8 embedding costs nothing measurable (95.5 % vs 95.4 %) and saves ~60 MB.
- An earlier live design committed words two decodes agreed on and trimmed the buffer after them;
  this export has no token timestamps (sherpa needs `export-onnx-with-attention.py` for those), so
  the trims fell mid-word and the replay scored 69.3 %. The live loop now only *reveals* words while
  a phrase is said and judges whole phrases when a pause ends them.
- **Read with care.** Professional reciters in studio conditions — some of them possibly in the
  model's training data — score higher than ordinary users reciting from memory on a phone, with
  hesitations, restarts and room noise. Whisper also normalises many vowel-mark differences, so the
  app checks the *words*, not tajweed or ḥarakāt, and says so.
- **Gate status: not passed for release.** The reciter number passes; the flag `recite` stays off
  until a set of ordinary users' recordings (consented, kept off the repository, deleted after the
  run) also scores ≥ 90 %: `eval.py --model-dir build/asr --local <folder>`.
