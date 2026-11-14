# services/asr — the «تلاواتي» speech check

A tiny internal service that transcribes a user's own recorded recitation (≤ 30 s) so the API can check
it recites the verses the user chose (`services/api/src/domain/recitation-match.ts`). Self-hosted in our
own Azure region (UAE North): voice never leaves our infrastructure, no third-party speech API, no
per-call fee.

```
POST /verify      body: the .m4a bytes (≤ 256 KB) · header X-ASR-Token: <shared secret>
                  200 {durationMs, speechMs, transcript, words: [{text, startMs, endMs}]}
                  401 unauthorized · 413 too_large | too_long (> 31 s) · 422 undecodable · 503 not_configured
GET  /health      {"ok": true}
```

- **Engine:** [faster-whisper](https://github.com/SYSTRAN/faster-whisper) 1.1.1 (MIT) — CTranslate2,
  int8, CPU, greedy decoding (`beam_size=1`), `language=ar`, Silero VAD filter, word timestamps.
  Decoding through PyAV (FFmpeg libraries bundled in its wheel, LGPL), so the image needs no system ffmpeg.
- **Privacy:** stateless. Nothing is written to disk; no access log (`--no-access-log`), no request or
  transcript logging. The API sends only the audio bytes — no user id, no handle. Internal ingress only.
- **Concurrency:** one recording at a time (a lock), one vCPU. The API's queue is also concurrency 1.

## Model

| | |
| --- | --- |
| Model | [`tarteel-ai/whisper-base-ar-quran`](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) — Whisper base fine-tuned on Quran recitation |
| Licence | **Apache-2.0** (model card metadata, checked 2026-11-14) |
| Base model | `openai/whisper-base` (Apache-2.0 on the Hub; the Whisper code and weights are MIT-licensed upstream) |
| Revision | `5c3c53fdf9272c4f6ee0bee09a1e5a4a615ee25c` (pinned in the Dockerfile, written to `/model/MODEL_REVISION`) |
| Conversion | `ct2-transformers-converter --quantization int8` at image build time; `tokenizer.json` saved from the model's own tokenizer |
| Size | ≈ 75 MB int8 |

Also recorded in `docs/CONTENT_SOURCES.md` › Models. Changing the model or revision is a decision for
the owner (the licence must stay permissive) and needs the shared recitation-match vectors re-checked.

## Cost

Azure Container App `yaqeen-asr`: internal ingress, **min replicas 0**, max 1, 1 vCPU / 2 GiB. It runs
only while verifying: a 30-second clip takes a few vCPU-seconds with whisper-base int8 (plus a cold start
of ~10–20 s when it has scaled to zero). The Container Apps monthly free grant (180,000 vCPU-seconds,
360,000 GiB-seconds) covers thousands of recordings a month; private recordings never reach it.

## Develop and test

```bash
cd services/asr
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q                      # HTTP contract with a stub transcriber (no model)
# Real model (inside the image, where /model exists):
docker build -f services/asr/Dockerfile -t yaqeen-asr .
docker run --rm -e ASR_TOKEN=dev -p 8080:8080 yaqeen-asr
curl -s -H 'X-ASR-Token: dev' --data-binary @sample.m4a localhost:8080/verify
```

Point the API at it with `ASR_URL=http://localhost:8080 ASR_TOKEN=dev`. Without `ASR_URL` the API
sends shared recordings straight to the human review queue (never auto-approved).
