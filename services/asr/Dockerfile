# Yaqeen ASR — internal speech check for «تلاواتي». Build from the repo root:
#   docker build -f services/asr/Dockerfile -t yaqeen-asr .
# Stage 1 converts the pinned Quran-tuned Whisper to CTranslate2 int8 (torch only lives here);
# stage 2 is the small runtime with the converted model baked in at /model.

# Bookworm (glibc 2.36), not the floating slim tag: ctranslate2 4.5.0's library asks for an executable
# stack, which glibc ≥ 2.41 (Debian trixie, today's python:3.12-slim) refuses at import.
FROM python:3.12-slim-bookworm AS convert
ARG MODEL_ID=tarteel-ai/whisper-base-ar-quran
# Pinned revision (licence: Apache-2.0 — see services/asr/README.md › Model).
ARG MODEL_REVISION=5c3c53fdf9272c4f6ee0bee09a1e5a4a615ee25c
ENV PIP_NO_CACHE_DIR=1 HF_HUB_DISABLE_TELEMETRY=1
RUN pip install --index-url https://download.pytorch.org/whl/cpu torch==2.5.1 \
 && pip install ctranslate2==4.5.0 transformers==4.47.1 huggingface_hub==0.27.1
RUN ct2-transformers-converter --model "$MODEL_ID" --revision "$MODEL_REVISION" --output_dir /model \
      --quantization int8 --copy_files preprocessor_config.json \
 # faster-whisper reads tokenizer.json: write the model's own tokenizer (same vocab) as a fast tokenizer.
 && python -c "import sys; from transformers import WhisperTokenizerFast as T; T.from_pretrained(sys.argv[1], revision=sys.argv[2]).save_pretrained('/tok')" "$MODEL_ID" "$MODEL_REVISION" \
 && cp /tok/tokenizer.json /model/tokenizer.json \
 && printf '%s@%s\n' "$MODEL_ID" "$MODEL_REVISION" > /model/MODEL_REVISION

FROM python:3.12-slim-bookworm AS runtime
ENV PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    ASR_MODEL_DIR=/model HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
WORKDIR /srv
COPY services/asr/requirements.txt .
# PyAV's wheel bundles the FFmpeg libraries it decodes with: no system ffmpeg needed.
RUN pip install -r requirements.txt && useradd --system --uid 10001 asr
COPY --from=convert /model /model
COPY services/asr/app ./app
USER asr
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)" || exit 1
# No access log: requests carry voice recordings; nothing about them is logged.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--no-access-log"]
