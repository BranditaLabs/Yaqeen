"""Yaqeen ASR — the internal speech check behind «تلاواتي» (users' own recorded recitations).

POST /verify   raw .m4a body (≤ 256 KB), header X-ASR-Token
               → {durationMs, speechMs, transcript, words: [{text, startMs, endMs}]}
GET  /health   liveness (the model is loaded at start-up)

Privacy: nothing is stored and nothing about the audio or the transcript is logged (access log off,
no request logging). The API only sends the audio bytes — no user id. Internal ingress only.
"""

from __future__ import annotations

import hmac
import os
import threading
from contextlib import asynccontextmanager
from typing import Protocol

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

SAMPLE_RATE = 16_000
#: Recordings are capped at 30 s by the API; anything over 31 s is refused here too.
MAX_SECONDS = 31.0
MAX_BYTES = 256 * 1024


class Transcriber(Protocol):
    """Decodes and transcribes one recording. `decode` raises ValueError for undecodable audio."""

    def decode(self, data: bytes) -> "object": ...

    def duration_s(self, audio: "object") -> float: ...

    def speech_ms(self, audio: "object") -> int: ...

    def transcribe(self, audio: "object") -> tuple[str, list[dict]]: ...


def _error(status: int, code: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"code": code}})


def create_app(transcriber: Transcriber | None = None, token: str | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        # Load the model at start-up so the first request after a cold start doesn't pay twice.
        if transcriber is None and os.environ.get("ASR_LAZY") != "1":  # pragma: no cover - exercised in the image
            get_transcriber()
        yield

    app = FastAPI(title="yaqeen-asr", docs_url=None, redoc_url=None, openapi_url=None, lifespan=lifespan)
    secret = token if token is not None else os.environ.get("ASR_TOKEN", "")
    state: dict[str, Transcriber | None] = {"t": transcriber}
    # One recording at a time: the service runs on one vCPU and scales to zero between uses.
    lock = threading.Lock()

    def get_transcriber() -> Transcriber:
        if state["t"] is None:
            from .transcriber import FasterWhisperTranscriber

            state["t"] = FasterWhisperTranscriber.from_env()
        return state["t"]  # type: ignore[return-value]

    @app.get("/health")
    def health() -> dict:
        return {"ok": True}

    @app.post("/verify")
    async def verify(request: Request):
        if not secret:
            return _error(503, "not_configured")
        given = request.headers.get("x-asr-token", "")
        if not hmac.compare_digest(given.encode(), secret.encode()):
            return _error(401, "unauthorized")
        length = request.headers.get("content-length")
        if length is not None and length.isdigit() and int(length) > MAX_BYTES:
            return _error(413, "too_large")
        data = await request.body()
        if len(data) > MAX_BYTES:
            return _error(413, "too_large")
        if not data:
            return _error(422, "undecodable")
        t = get_transcriber()

        def run():
            with lock:
                try:
                    audio = t.decode(data)
                except ValueError:
                    return _error(422, "undecodable")
                seconds = t.duration_s(audio)
                if seconds <= 0:
                    return _error(422, "undecodable")
                if seconds > MAX_SECONDS:
                    return _error(413, "too_long")
                speech = t.speech_ms(audio)
                transcript, words = t.transcribe(audio) if speech > 0 else ("", [])
                return {
                    "durationMs": int(round(seconds * 1000)),
                    "speechMs": int(speech),
                    "transcript": transcript,
                    "words": [
                        {"text": w["text"].strip(), "startMs": max(0, int(w["startMs"])), "endMs": max(0, int(w["endMs"]))}
                        for w in words
                        if str(w.get("text", "")).strip()
                    ],
                }

        from starlette.concurrency import run_in_threadpool

        return await run_in_threadpool(run)

    return app


#: `uvicorn app.main:app` — the model loads at start-up (baked into the image at /model).
app = create_app()
