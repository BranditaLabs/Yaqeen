"""HTTP contract of the ASR service with a stub transcriber (no model needed), plus a real-model test
that runs only when ASR_MODEL_DIR points at a converted model (the image build sets it)."""

from __future__ import annotations

import io
import math
import os
import struct
import wave

import pytest
from fastapi.testclient import TestClient

from app.main import create_app

TOKEN = "test-token-not-secret"


def tone_wav(seconds: float, freq: float = 220.0, rate: int = 16_000) -> bytes:
    """A tiny generated audio fixture (mono 16-bit PCM WAV)."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = int(seconds * rate)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * freq * i / rate))) for i in range(frames)))
    return buf.getvalue()


class StubTranscriber:
    """Decodes WAV with the standard library; 'transcribes' to fixed words."""

    def __init__(self) -> None:
        self.calls = 0

    def decode(self, data: bytes):
        try:
            with wave.open(io.BytesIO(data)) as w:
                return [0.0] * w.getnframes()
        except Exception as err:
            raise ValueError("undecodable") from err

    def duration_s(self, audio) -> float:
        return len(audio) / 16_000

    def speech_ms(self, audio) -> int:
        return int(len(audio) / 16 * 0.8)

    def transcribe(self, audio):
        self.calls += 1
        return "قل هو الله احد", [
            {"text": "قل", "startMs": 100, "endMs": 400},
            {"text": "هو", "startMs": 450, "endMs": 700},
            {"text": "الله", "startMs": 750, "endMs": 1100},
            {"text": "احد", "startMs": 1150, "endMs": 1600},
            {"text": " ", "startMs": 1600, "endMs": 1700},
        ]


@pytest.fixture()
def stub():
    return StubTranscriber()


@pytest.fixture()
def client(stub):
    return TestClient(create_app(transcriber=stub, token=TOKEN))


def post(client, body: bytes, token: str | None = TOKEN):
    headers = {"content-type": "audio/mp4"}
    if token is not None:
        headers["x-asr-token"] = token
    return client.post("/verify", content=body, headers=headers)


def test_health(client):
    assert client.get("/health").json() == {"ok": True}


def test_verify_contract(client, stub):
    r = post(client, tone_wav(2.0))
    assert r.status_code == 200
    body = r.json()
    assert body["durationMs"] == 2000
    assert body["speechMs"] == 1600
    assert body["transcript"] == "قل هو الله احد"
    assert body["words"][0] == {"text": "قل", "startMs": 100, "endMs": 400}
    assert len(body["words"]) == 4  # blank words dropped
    assert stub.calls == 1


def test_token_required(client):
    assert post(client, tone_wav(1.0), token=None).status_code == 401
    assert post(client, tone_wav(1.0), token="wrong").status_code == 401


def test_not_configured_without_a_token(stub):
    c = TestClient(create_app(transcriber=stub, token=""))
    assert post(c, tone_wav(1.0), token="").json() == {"error": {"code": "not_configured"}}


def test_rejects_long_and_large_and_undecodable(client, stub):
    r = post(client, tone_wav(31.5))
    # 31.5 s of 16-bit mono is ~1 MB: refused for size before decoding.
    assert r.status_code == 413
    assert r.json()["error"]["code"] == "too_large"
    long_light = tone_wav(32.0, rate=4_000)  # small file, long duration
    stub_rate = StubTranscriber()
    stub_rate.duration_s = lambda audio: 32.0  # type: ignore[method-assign]
    c = TestClient(create_app(transcriber=stub_rate, token=TOKEN))
    r = post(c, long_light)
    assert r.status_code == 413 and r.json()["error"]["code"] == "too_long"
    assert stub_rate.calls == 0
    assert post(client, b"not audio").status_code == 422
    assert post(client, b"").status_code == 422


def test_silence_is_not_transcribed(stub):
    stub.speech_ms = lambda audio: 0  # type: ignore[method-assign]
    c = TestClient(create_app(transcriber=stub, token=TOKEN))
    r = post(c, tone_wav(1.0))
    assert r.json() == {"durationMs": 1000, "speechMs": 0, "transcript": "", "words": []}
    assert stub.calls == 0


@pytest.mark.skipif(not os.environ.get("ASR_MODEL_DIR"), reason="needs the converted model (ASR_MODEL_DIR)")
def test_real_model_decodes_and_answers():
    from app.transcriber import FasterWhisperTranscriber

    c = TestClient(create_app(transcriber=FasterWhisperTranscriber.from_env(), token=TOKEN))
    r = post(c, tone_wav(1.5))
    assert r.status_code == 200
    body = r.json()
    assert body["durationMs"] == 1500
    assert isinstance(body["words"], list)
