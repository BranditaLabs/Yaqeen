"""faster-whisper (CTranslate2, int8, CPU) with the Quran-tuned Whisper baked into the image.

Model: tarteel-ai/whisper-base-ar-quran (Apache-2.0, fine-tuned from openai/whisper-base), revision
pinned in the Dockerfile and converted to CTranslate2 int8 at image build time (README › Model).
Decoding uses PyAV (FFmpeg libraries bundled in its wheel) through faster_whisper.decode_audio; speech
is measured with faster-whisper's bundled Silero VAD. Nothing is written to disk or logged.
"""

from __future__ import annotations

import io
import os

SAMPLE_RATE = 16_000


class FasterWhisperTranscriber:
    def __init__(self, model_dir: str, threads: int) -> None:
        from faster_whisper import WhisperModel

        self.model = WhisperModel(model_dir, device="cpu", compute_type="int8", cpu_threads=threads, num_workers=1)

    @classmethod
    def from_env(cls) -> "FasterWhisperTranscriber":
        return cls(os.environ.get("ASR_MODEL_DIR", "/model"), int(os.environ.get("ASR_THREADS", str(os.cpu_count() or 1))))

    def decode(self, data: bytes):
        from faster_whisper import decode_audio

        try:
            audio = decode_audio(io.BytesIO(data), sampling_rate=SAMPLE_RATE)
        except Exception as err:  # PyAV raises its own error types for corrupt input
            raise ValueError("undecodable") from err
        if audio is None or len(audio) == 0:
            raise ValueError("undecodable")
        return audio

    def duration_s(self, audio) -> float:
        return len(audio) / SAMPLE_RATE

    def speech_ms(self, audio) -> int:
        from faster_whisper.vad import VadOptions, get_speech_timestamps

        spans = get_speech_timestamps(audio, VadOptions(min_silence_duration_ms=300))
        return int(sum(s["end"] - s["start"] for s in spans) * 1000 / SAMPLE_RATE)

    def transcribe(self, audio) -> tuple[str, list[dict]]:
        segments, _info = self.model.transcribe(
            audio,
            language="ar",
            task="transcribe",
            beam_size=1,
            best_of=1,
            temperature=0.0,
            condition_on_previous_text=False,
            vad_filter=True,
            word_timestamps=True,
        )
        words: list[dict] = []
        texts: list[str] = []
        for seg in segments:
            texts.append(seg.text.strip())
            for w in seg.words or []:
                t = w.word.strip()
                if t:
                    words.append({"text": t, "startMs": int(round(w.start * 1000)), "endMs": int(round(w.end * 1000))})
        return " ".join(t for t in texts if t), words
