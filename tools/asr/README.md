# tools/asr — the on-device recitation model

Everything here is development tooling: nothing is bundled in the app, and **no model binary or
audio is ever committed** (`tools/asr/.cache/` and `build/` are git-ignored). See `docs/MODELS.md`
for the model card, licences and the ship-gate result.

## Set up (Python 3.13)

```bash
py -3.13 -m venv .venv            # macOS/Linux: python3.13 -m venv .venv
.venv/Scripts/pip install --only-binary=:all: --no-binary=openai-whisper -r tools/asr/requirements.txt
```

`openai-whisper` ships as a source package only; everything else installs from wheels.

## Build the model — `convert.py`

```bash
.venv/Scripts/python tools/asr/convert.py --out build/asr
```

Downloads `tarteel-ai/whisper-tiny-ar-quran` at its pinned revision (SHA-256 checked), maps it to
openai-whisper, exports it with sherpa-onnx's own exporter (pinned commit, SHA-256 checked), rewrites
the decoder's logits so the token embedding is quantised once (int8, shared with the token lookup —
checked equal to the export before quantising), adds Silero VAD, smoke-tests the result in the same
runtime as the app, and writes `build/asr/manifest.json`. The run is deterministic (fixed hash seed),
so `tools/asr/manifest.json` — the committed copy — must match a re-run byte for byte.

Then:

1. Upload the four files from `build/asr/` to the CDN folder the app reads (`ASR_MODEL_BASE_URL`).
2. Check `AsrModelManifest.yaqeen` in `apps/mobile/lib/core/platform/asr/asr_model.dart` carries
   the same names, sizes and SHA-256s as `tools/asr/manifest.json`.
3. Build the app with `--dart-define=ASR_MODEL_BASE_URL=https://…/asr/yaqeen-asr-v1/`.

Without `ASR_MODEL_BASE_URL` the app downloads the interim pinned upstream export
(`AsrModelManifest.interim`, ~104 MB) — for development only.

## The ship gate — `eval/eval.py`

```bash
.venv/Scripts/python tools/asr/eval/eval.py --model-dir build/asr --out tools/asr/eval/report.md
.venv/Scripts/python tools/asr/eval/eval.py --model-dir build/asr --live                 # + the live loop
.venv/Scripts/python tools/asr/eval/eval.py --model-dir build/asr --local path/to/voices  # users' voices
```

- Reciter audio (Quran Foundation catalogue, the same the app streams) is downloaded into
  `tools/asr/.cache/eval/` for evaluation only — never shipped, never committed.
- Each ayah is cut by its timing and recognised with the app's exact settings; the transcript is
  aligned with `eval/aligner.py`, a line-for-line port of the app's `RecitationAligner`
  (`eval/test_aligner.py` keeps them in step).
- **Users' voices** (`--local`): 16-bit WAV files named `<surah>_<from>[-<to>].wav` (e.g.
  `112_1-4.wav`), recorded on phones by ordinary reciters with their consent. These recordings are
  personal data: keep them off the repository and delete them after the run.
- `eval.py --template` prints the report's shape (the template lives in `eval.py`); the latest
  numbers go in `docs/MODELS.md`.

Professional reciters in a studio (and possibly in the model's training data) score higher than
ordinary users on a phone. The `recite` flag stays off until users' voices pass ≥ 90 % too.
