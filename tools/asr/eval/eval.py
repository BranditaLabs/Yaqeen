#!/usr/bin/env python3
"""Ship-gate evaluation for on-device «تسميع» (spec §6.8: ≥ 90 % word accuracy before the `recite`
flag may be switched on).

    py -3.13 tools/asr/eval/eval.py --model-dir build/asr --out tools/asr/eval/report.md
    ... --local path/to/voices     # optional: your own recordings, <surah>_<from>[-<to>].wav

What it does:
  * Downloads a few surahs from the reciter catalogue the app already uses (Quran Foundation,
    per-ayah timings) into a local cache — dev-only evaluation data, never shipped, never committed.
  * Cuts each ayah by its timing and recognises it with the *same* model and decoding settings as
    the app (sherpa-onnx OfflineRecognizer, Whisper int8, language "ar", task "transcribe", greedy).
  * Aligns the transcript against the bundled mushaf text with a line-for-line port of the app's
    `RecitationAligner` (aligner.py) and reports word accuracy = words marked ok / words expected.
  * Optional `--live`: replays each whole surah the way the app judges it live — speech segments cut
    by pauses (≤ 25 s), each decoded when it ends — instead of per-ayah cuts.

Read the number with care: professional reciters in a studio (and possibly in the model's training
data) score higher than ordinary users on a phone. The gate needs real users' voices (`--local`).
"""

from __future__ import annotations

import argparse
import json
import platform
import sys
import time
from datetime import date
from pathlib import Path

import numpy as np
import requests
import soundfile as sf
from scipy.signal import resample_poly

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aligner  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
QURAN_JSON = ROOT / "apps/mobile/assets/quran/quran.json"
QF = "https://api.quran.com/api/v4/chapter_recitations/{rec}/{surah}?segments=true"
SR = 16000

# Murattal recitations from the catalogue (QF ids): Alafasy, AbdulBaset (murattal), Minshawi
# (murattal), Husary.
DEFAULT_RECITATIONS = [7, 2, 9, 6]
# Al-Fatiha + the end of Juz ʿAmma (what hifz plans start with) + al-Mulk's opening.
DEFAULT_SURAHS = [1, 112, 113, 114, 103, 108, 67]


def load_text() -> list[list[str]]:
    return json.loads(QURAN_JSON.read_text(encoding="utf-8"))["ayat"]


def recognizer(model_dir: Path):
    import sherpa_onnx

    m = json.loads((model_dir / "manifest.json").read_text(encoding="utf-8"))
    f = {x["role"]: model_dir / x["name"] for x in m["files"]}
    rec = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(f["encoder"]),
        decoder=str(f["decoder"]),
        tokens=str(f["tokens"]),
        language="ar",
        task="transcribe",
        num_threads=2,
    )
    return rec, m


def decode(rec, samples: np.ndarray) -> str:
    s = rec.create_stream()
    s.accept_waveform(SR, samples.astype(np.float32))
    rec.decode_stream(s)
    return s.result.text.strip()


def read_audio(path: Path) -> np.ndarray:
    data, rate = sf.read(str(path), dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    if rate != SR:
        g = np.gcd(rate, SR)
        mono = resample_poly(mono, SR // g, rate // g).astype(np.float32)
    return mono


def fetch_surah(rec_id: int, surah: int, cache: Path) -> tuple[np.ndarray, list[dict]]:
    meta_path = cache / f"{rec_id}" / f"{surah}.json"
    if meta_path.exists():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    else:
        meta = requests.get(QF.format(rec=rec_id, surah=surah), timeout=30).json()["audio_file"]
        meta_path.parent.mkdir(parents=True, exist_ok=True)
        meta_path.write_text(json.dumps(meta), encoding="utf-8")
    audio_path = cache / f"{rec_id}" / f"{surah}.{meta.get('format', 'mp3')}"
    if not audio_path.exists():
        r = requests.get(meta["audio_url"], timeout=120)
        r.raise_for_status()
        audio_path.write_bytes(r.content)
    return read_audio(audio_path), meta["timestamps"]


def chunks(samples: np.ndarray, start_ms: int, end_ms: int, segments: list) -> list[np.ndarray]:
    """The ayah, cut at word boundaries into pieces Whisper can read (≤ 25 s)."""
    a, b = max(0, int(start_ms) - 80), int(end_ms) + 80
    if b - a <= 28_000 or not segments:
        return [samples[a * SR // 1000 : b * SR // 1000]]
    out, piece_start = [], a
    for seg in segments:
        if len(seg) < 3:
            continue
        s0, s1 = int(seg[1]), int(seg[2])
        if s1 - piece_start > 25_000:
            out.append(samples[piece_start * SR // 1000 : s0 * SR // 1000])
            piece_start = s0
    out.append(samples[piece_start * SR // 1000 : b * SR // 1000])
    return out


class Tally:
    def __init__(self) -> None:
        self.ok = self.warn = self.skipped = 0
        self.audio = 0.0
        self.cpu = 0.0

    def add(self, marks: list[str]) -> None:
        self.ok += marks.count(aligner.OK)
        self.warn += marks.count(aligner.WARN)
        self.skipped += marks.count(aligner.SKIPPED)

    @property
    def total(self) -> int:
        return self.ok + self.warn + self.skipped

    @property
    def accuracy(self) -> float:
        return self.ok / self.total if self.total else 0.0

    def merge(self, o: "Tally") -> None:
        self.ok += o.ok
        self.warn += o.warn
        self.skipped += o.skipped
        self.audio += o.audio
        self.cpu += o.cpu


def live_replay(rec, samples: np.ndarray, silence_s=0.6, max_s=25.0, thr=0.02) -> list[str]:
    """What the app's LiveTranscriber judges on: whole speech segments (a pause of 0.6 s ends one, a
    stretch is cut at 25 s), each decoded once when it ends. The live tentative words only reveal on
    the page and are not judged, so they are not replayed. Energy gate here; Silero VAD on the phone."""
    committed: list[str] = []
    hop = int(0.1 * SR)
    seg: list[np.ndarray] | None = None
    length = quiet = 0

    def final():
        nonlocal seg, length
        if seg is not None and length > SR // 4:
            committed.extend(decode(rec, np.concatenate(seg)).split())
        seg, length = None, 0

    for i in range(0, len(samples), hop):
        chunk = samples[i : i + hop]
        speaking = len(chunk) > 0 and float(np.max(np.abs(chunk))) >= thr
        if seg is None:
            if speaking:
                seg, length, quiet = [chunk], len(chunk), 0
            continue
        seg.append(chunk)
        length += len(chunk)
        quiet = 0 if speaking else quiet + len(chunk)
        if quiet >= silence_s * SR or length >= max_s * SR:
            final()
    final()
    return committed


# The report's shape (what `main` writes), kept here as the committed template: `--template` prints it.
TEMPLATE = """# «تسميع» ship-gate evaluation

- Date: YYYY-MM-DD
- Model: `<id>` — <upstream repo>@<revision> (<licence>)
- Files: <name> <MB>, …
- Decoding: sherpa-onnx OfflineRecognizer, Whisper int8, language `ar`, task `transcribe`, greedy (as in the app)
- Machine: <platform>, 2 threads — RTF <x.xx> (phones are slower)
- Alignment: tools/asr/eval/aligner.py (port of `RecitationAligner`); accuracy = words ok / words expected

## Reciters (Quran Foundation catalogue, per-ayah cuts)

| Recitation | Surah | Words | ok | تنبيه | not heard | Accuracy |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| <QF id> | <surah> | … | … | … | … | …% |
| **All** | | **…** | **…** | **…** | **…** | **…%** |

Live loop replay (whole surahs cut by pauses, energy gate): **…%** of … words.   (with --live)

## Your voices (`--local`)

| File | Words | ok | Accuracy |
| --- | ---: | ---: | ---: |
| <surah>_<from>-<to>.wav | … | … | …% |

## Ship gate (spec §6.8: ≥ 90 %)

- Reciters: pass / FAIL (…%)
- Users' voices: pass / FAIL (…%) — required before the flag goes on

## Sample of ayat with a note

- <surah:ayah> (rec <id>): <what was heard>
"""


def main() -> None:
    if "--template" in sys.argv:
        print(TEMPLATE)
        return
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model-dir", type=Path, required=True, help="convert.py output (manifest.json + files)")
    ap.add_argument("--recitations", default=",".join(map(str, DEFAULT_RECITATIONS)))
    ap.add_argument("--surahs", default=",".join(map(str, DEFAULT_SURAHS)))
    ap.add_argument("--local", type=Path, help="folder of <surah>_<from>[-<to>].wav user recordings")
    ap.add_argument("--live", action="store_true", help="also replay through the live loop")
    ap.add_argument("--cache", type=Path, default=ROOT / "tools/asr/.cache/eval")
    ap.add_argument("--out", type=Path, default=ROOT / "tools/asr/eval/report.md")
    args = ap.parse_args()

    text = load_text()
    rec, manifest = recognizer(args.model_dir)
    recitations = [int(x) for x in args.recitations.split(",") if x]
    surahs = [int(x) for x in args.surahs.split(",") if x]

    rows, overall, live_total = [], Tally(), Tally()
    worst: list[tuple[str, str, str]] = []
    for rid in recitations:
        for s in surahs:
            samples, stamps = fetch_surah(rid, s, args.cache)
            t = Tally()
            for st in stamps:
                surah, ayah = map(int, st["verse_key"].split(":"))
                expected = aligner.words(text[surah - 1][ayah - 1])
                t0 = time.perf_counter()
                heard = " ".join(decode(rec, c) for c in chunks(samples, st["timestamp_from"], st["timestamp_to"], st.get("segments") or []))
                t.cpu += time.perf_counter() - t0
                t.audio += (st["timestamp_to"] - st["timestamp_from"]) / 1000
                marks = aligner.align(expected, aligner.words(heard))
                t.add(marks)
                if marks.count(aligner.OK) < len(marks) and len(worst) < 40:
                    worst.append((st["verse_key"], f"{rid}", heard))
            rows.append((rid, s, t))
            overall.merge(t)
            if args.live:
                expected_all = [w for st in stamps for w in aligner.words(text[s - 1][int(st["verse_key"].split(":")[1]) - 1])]
                start = max(0, stamps[0]["timestamp_from"] - 200) * SR // 1000
                lt = Tally()
                lt.add(aligner.align(expected_all, live_replay(rec, samples[start:])))
                live_total.merge(lt)
            print(f"rec {rid} surah {s}: {t.ok}/{t.total} = {t.accuracy:.1%}", flush=True)

    local_total = Tally()
    local_rows = []
    if args.local:
        for wav in sorted(args.local.glob("*.wav")):
            stem = wav.stem
            surah, rng = stem.split("_", 1)
            a, _, b = rng.partition("-")
            refs = [(int(surah), x) for x in range(int(a), int(b or a) + 1)]
            expected = [w for (su, ay) in refs for w in aligner.words(text[su - 1][ay - 1])]
            samples = read_audio(wav)
            heard = " ".join(decode(rec, samples[i : i + 25 * SR]) for i in range(0, len(samples), 25 * SR))
            t = Tally()
            t.add(aligner.align(expected, aligner.words(heard)))
            local_rows.append((wav.name, t))
            local_total.merge(t)

    rtf = overall.cpu / overall.audio if overall.audio else 0
    lines = [
        "# «تسميع» ship-gate evaluation",
        "",
        f"- Date: {date.today().isoformat()}",
        f"- Model: `{manifest['id']}` — {manifest['upstream']['repo']}@{manifest['upstream']['revision'][:12]} ({manifest['upstream']['licence']})",
        f"- Files: " + ", ".join(f"`{f['name']}` {f['bytes'] / 1e6:.1f} MB" for f in manifest["files"]),
        "- Decoding: sherpa-onnx OfflineRecognizer, Whisper int8, language `ar`, task `transcribe`, greedy (as in the app)",
        f"- Machine: {platform.platform()} ({platform.processor() or 'cpu'}), 2 threads — RTF {rtf:.2f} (phones are slower)",
        "- Alignment: tools/asr/eval/aligner.py (port of `RecitationAligner`); accuracy = words ok / words expected",
        "",
        "## Reciters (Quran Foundation catalogue, per-ayah cuts)",
        "",
        "| Recitation | Surah | Words | ok | تنبيه | not heard | Accuracy |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for rid, s, t in rows:
        lines.append(f"| {rid} | {s} | {t.total} | {t.ok} | {t.warn} | {t.skipped} | {t.accuracy:.1%} |")
    lines += [
        f"| **All** | | **{overall.total}** | **{overall.ok}** | **{overall.warn}** | **{overall.skipped}** | **{overall.accuracy:.1%}** |",
        "",
    ]
    if args.live:
        lines += [f"Live loop replay (whole surahs cut by pauses, energy gate): **{live_total.accuracy:.1%}** of {live_total.total} words.", ""]
    lines += ["## Your voices (`--local`)", ""]
    if local_rows:
        lines += ["| File | Words | ok | Accuracy |", "| --- | ---: | ---: | ---: |"]
        lines += [f"| {n} | {t.total} | {t.ok} | {t.accuracy:.1%} |" for n, t in local_rows]
        lines += [f"| **All** | **{local_total.total}** | **{local_total.ok}** | **{local_total.accuracy:.1%}** |", ""]
    else:
        lines += ["Not run yet — the gate needs ordinary users' recordings on phones (see README).", ""]
    gate = local_total if local_rows else overall
    lines += [
        "## Ship gate (spec §6.8: ≥ 90 %)",
        "",
        f"- Reciters: {'pass' if overall.accuracy >= 0.9 else 'FAIL'} ({overall.accuracy:.1%})",
        f"- Users' voices: {('pass' if local_total.accuracy >= 0.9 else 'FAIL') + f' ({local_total.accuracy:.1%})' if local_rows else 'not measured — required before the flag goes on'}",
        "",
        "Professional reciters in studio conditions overestimate what ordinary users get on a phone (and",
        "the model may have seen some of these recitations in training). Keep `recite` off until users'",
        "voices pass too.",
        "",
        "## Sample of ayat with a note",
        "",
    ]
    lines += [f"- {k} (rec {r}): {h}" for k, r, h in worst[:20]]
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"overall {overall.accuracy:.1%} ({overall.ok}/{overall.total}); gate source: {'local' if local_rows else 'reciters'} {gate.accuracy:.1%}")
    print(f"report → {args.out}")


if __name__ == "__main__":
    main()
