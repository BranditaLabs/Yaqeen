#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات يقين» (v7).

Matched to the character of high-end app sounds — iPhone (Note, Rebound), Apple Pay / Revolut
success sounds, Headspace / Calm warmth, Tarteel / Nusuk restraint:

  * Very short (0.45–1.1 s). Nothing rings on.
  * A round «pop» at the touch: each tone starts a few percent sharp and settles in ~12 ms,
    with a fast-fading 2nd harmonic for shape, the octave below for warmth and 1 ms of air.
  * A quick, confident gesture: notes 60–120 ms apart.
  * A whisper of room only; band-limited for phone speakers; levelled by true peak
    (−1 dBTP prayer … −9 dBTP offers).
  * Signature: F♯ rising a fourth to B — short then long like «يَ‑قين».
  * Owner's halal line: soft tones are fine; no instrument timbres, no bells, no melodies —
    three notes at most. The adhan is NOT generated — it stays a licensed recording (spec §10).

Outputs (run from repo root):  python3 packages/brand/sounds/generate_sounds.py
  packages/brand/sounds/master/<name>.wav               48 kHz / 24-bit stereo masters
  apps/mobile/android/app/src/main/res/raw/<name>.ogg   Android (Vorbis, stereo)
  apps/mobile/ios/Runner/Sounds/<name>.caf              iOS (16-bit PCM CAF, stereo, < 30 s)
  apps/mobile/assets/sounds/<name>.ogg                  in-app UI sounds (ui_*)

Requires: numpy, scipy, soundfile, pyloudnorm (report only), pedalboard, ffmpeg (libvorbis).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from pedalboard import Pedalboard, Reverb
from scipy.signal import butter, resample_poly, sosfilt

SR = 48_000
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SEED = 2026

# The signature: F♯ rising a perfect fourth to B.
Fs5, B5, Fs6, B6, Fs4, B4 = 739.99, 987.77, 1479.98, 1975.53, 369.99, 493.88


def n_of(sec: float) -> int:
    return int(round(sec * SR))


# ----------------------------------------------------------------------------- the voice
#   The DNA shared by iPhone (Note, Rebound), Apple Pay / Revolut success sounds, Headspace and
#   Tarteel: very short, a round «pop» at the touch, almost no reverb, a quick confident gesture,
#   warmth underneath. Nothing rings on — that's what separates them from a desktop chime.


class Engine:
    def __init__(self, seed: int):
        self.rng = np.random.default_rng(seed)

    def pop(self, f: float, *, decay: float = 0.16, vel: float = 1.0, blip: float = 0.035,
            attack: float = 0.0018, warmth: float = 0.12, air: float = 0.25, pos: float = 0.0) -> np.ndarray:
        """One round, tactile tone. `blip`: the pitch starts a few % sharp and settles in ~12 ms —
        the «pop». A quieter 2nd harmonic that fades fast gives it shape; the octave below gives
        warmth; a 1 ms touch of air gives it a surface."""
        sec = min(1.6, decay * 7)
        t = np.arange(n_of(sec)) / SR
        pitch = f * (1 + blip * np.exp(-t / 0.012))
        ph = 2 * np.pi * np.cumsum(pitch) / SR
        body = np.sin(ph) * np.exp(-t / decay)
        body += 0.22 * np.sin(2 * ph + 0.6) * np.exp(-t / (decay * 0.35))
        body += warmth * np.sin(0.5 * ph) * np.exp(-t / (decay * 1.2))
        a = n_of(attack)
        body[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
        touch = sosfilt(butter(2, [2 * f, min(8 * f, 15_000)], "bandpass", fs=SR, output="sos"),
                        self.rng.standard_normal(len(t))) * np.exp(-t / 0.0009) * 0.06 * air
        sig = (body + touch) * vel
        sig[-n_of(0.01):] *= np.linspace(1, 0, n_of(0.01))
        g = (pos + 1) * np.pi / 4
        return np.stack([sig * np.cos(g), sig * np.sin(g)], axis=1)


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_of(at)
    k = min(len(sig), len(buf) - i)
    if k > 0:
        buf[i : i + k] += gain * sig[:k]


def canvas(sec: float) -> np.ndarray:
    return np.zeros((n_of(sec), 2))


def finish(x: np.ndarray, peak_db: float, total: float, room: float = 0.14, wet: float = 0.06) -> np.ndarray:
    """A whisper of room (polish, not echo) → band-limit for phones → set by true peak."""
    x = Pedalboard([Reverb(room_size=room, damping=0.7, wet_level=wet, dry_level=1.0, width=0.8)])(
        x.T.astype(np.float32), SR).T.astype(np.float64)
    n = n_of(total)
    x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros((n - len(x), 2))])
    x = sosfilt(butter(2, 260, "highpass", fs=SR, output="sos"), x, axis=0)
    x = sosfilt(butter(2, 14_000, "lowpass", fs=SR, output="sos"), x, axis=0)
    fade = n_of(total * 0.4)  # long, curved taper: the tail melts into silence, never stops
    x[-fade:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fade)))[:, None] ** 1.5
    tp = np.max(np.abs(resample_poly(x, 4, 1, axis=0))) or 1.0
    return x * (10 ** (peak_db / 20) / tp)


# ----------------------------------------------------------------------------- the family
#   Signature: F♯ → B, a rising fourth, short then long like «يَ‑قين» — now a quick, tactile gesture.

Fs7 = 2959.96


def yq_prayer(e: Engine) -> np.ndarray:
    """Prayer time (alert «تنبيه»): the signature, crisp and clear — two pops, the second rings a little."""
    x = canvas(0.8)
    place(x, e.pop(Fs6, decay=0.07, pos=-0.12), 0.0, 0.8)
    place(x, e.pop(B6, decay=0.2, pos=0.12), 0.085, 1.0)
    return finish(x, -1.0, 0.8)


def yq_prayer_soon(e: Engine) -> np.ndarray:
    """Before the prayer: the first note alone, a gentle heads-up."""
    x = canvas(0.6)
    place(x, e.pop(Fs6, decay=0.17, blip=0.025), 0.0)
    return finish(x, -4.0, 0.6)


def yq_azkar(e: Engine) -> np.ndarray:
    """Azkar & dhikr: three quick counts — tap, tap, taaap."""
    x = canvas(0.7)
    for at, d, v, p in [(0.0, 0.05, 0.75, -0.15), (0.075, 0.05, 0.72, 0.15), (0.15, 0.16, 0.95, 0.0)]:
        place(x, e.pop(B6, decay=d, pos=p), at, v)
    return finish(x, -3.5, 0.7)


def yq_quran(e: Engine) -> np.ndarray:
    """Wird, khatma, al-Kahf: the signature an octave lower and softer — the Headspace warmth."""
    x = canvas(1.0)
    place(x, e.pop(Fs5, decay=0.12, blip=0.012, attack=0.006, warmth=0.2, pos=-0.12), 0.0, 0.8)
    place(x, e.pop(B5, decay=0.32, blip=0.012, attack=0.006, warmth=0.2, pos=0.12), 0.12, 1.0)
    return finish(x, -3.0, 1.0, room=0.2, wet=0.08)


def yq_hifz(e: Engine) -> np.ndarray:
    """Hifz review: the signature turned around — B back home to F♯."""
    x = canvas(0.8)
    place(x, e.pop(B6, decay=0.07, pos=0.12), 0.0, 0.8)
    place(x, e.pop(Fs6, decay=0.2, pos=-0.12), 0.09, 1.0)
    return finish(x, -3.0, 0.8)


def yq_suhoor(e: Engine) -> np.ndarray:
    """Suhoor: both notes together, softened and low — quiet enough for the night."""
    x = canvas(1.1)
    place(x, e.pop(Fs5, decay=0.38, blip=0.0, attack=0.014, warmth=0.22, air=0, pos=-0.2), 0.0, 0.85)
    place(x, e.pop(B5, decay=0.36, blip=0.0, attack=0.014, warmth=0.22, air=0, pos=0.2), 0.012, 0.7)
    return finish(x, -6.0, 1.1, room=0.22, wet=0.09)


def yq_iftar(e: Engine) -> np.ndarray:
    """Iftar: the signature and its octave in one bright run — the evening opening up."""
    x = canvas(0.9)
    place(x, e.pop(Fs6, decay=0.06, pos=-0.2), 0.0, 0.75)
    place(x, e.pop(B6, decay=0.07, pos=0.0), 0.075, 0.8)
    place(x, e.pop(Fs7, decay=0.2, pos=0.2), 0.15, 0.8)
    return finish(x, -2.5, 0.9)


def yq_challenge(e: Engine) -> np.ndarray:
    """Challenge, streaks, a reward is ready: the Revolut/Apple Pay moment — quick, bright, sure."""
    x = canvas(0.7)
    place(x, e.pop(B6, decay=0.05, blip=0.05, pos=-0.12), 0.0, 0.8)
    place(x, e.pop(Fs7, decay=0.16, blip=0.05, pos=0.12), 0.065, 1.0)
    return finish(x, -3.0, 0.7)


def yq_offers(e: Engine) -> np.ndarray:
    """Store offers (consented): one soft pop — the quietest sound in the set."""
    x = canvas(0.45)
    place(x, e.pop(B6, decay=0.09, blip=0.02, attack=0.003), 0.0)
    return finish(x, -9.0, 0.45)


def ui_bead(e: Engine) -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): a tiny tick, fine at 10 taps a second."""
    x = canvas(0.06)
    place(x, e.pop(B6, decay=0.012, blip=0.04, warmth=0), 0.0)
    return finish(x, -14.0, 0.06, wet=0.0)


def ui_bead_round(e: Engine) -> np.ndarray:
    """A completed round («تقبّل الله»): the signature in miniature."""
    x = canvas(0.5)
    place(x, e.pop(Fs6, decay=0.04, pos=-0.12), 0.0, 0.7)
    place(x, e.pop(B6, decay=0.12, pos=0.12), 0.06, 0.9)
    return finish(x, -9.0, 0.5)


def ui_complete(e: Engine) -> np.ndarray:
    """A task ticked / Qibla aligned: one bright pop."""
    x = canvas(0.4)
    place(x, e.pop(B6, decay=0.09, blip=0.05), 0.0)
    return finish(x, -10.0, 0.4)


NOTIFICATION_SOUNDS = {
    "yq_prayer": yq_prayer,
    "yq_prayer_soon": yq_prayer_soon,
    "yq_azkar": yq_azkar,
    "yq_quran": yq_quran,
    "yq_hifz": yq_hifz,
    "yq_suhoor": yq_suhoor,
    "yq_iftar": yq_iftar,
    "yq_challenge": yq_challenge,
    "yq_offers": yq_offers,
}
UI_SOUNDS = {"ui_bead": ui_bead, "ui_bead_round": ui_bead_round, "ui_complete": ui_complete}


# ----------------------------------------------------------------------------- output


def ffmpeg(*args: str) -> None:
    # bitexact: no random Ogg serials or encoder tags, so re-running gives identical files
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args[:-1],
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", args[-1]], check=True)


def main() -> int:
    if not shutil.which("ffmpeg"):
        print("ffmpeg is required", file=sys.stderr)
        return 1
    dirs = {
        "master": HERE / "master",
        "raw": ROOT / "apps/mobile/android/app/src/main/res/raw",
        "ios": ROOT / "apps/mobile/ios/Runner/Sounds",
        "assets": ROOT / "apps/mobile/assets/sounds",
    }
    for d in dirs.values():
        d.mkdir(parents=True, exist_ok=True)

    for i, (name, fn) in enumerate({**NOTIFICATION_SOUNDS, **UI_SOUNDS}.items()):
        x = fn(Engine(SEED + i))  # each sound has its own fixed seed → stable when others change
        wav = dirs["master"] / f"{name}.wav"
        sf.write(wav, x, SR, subtype="PCM_24")
        if name.startswith("yq_"):
            ffmpeg("-i", str(wav), "-c:a", "libvorbis", "-q:a", "7", str(dirs["raw"] / f"{name}.ogg"))
            ffmpeg("-i", str(wav), "-ar", "44100", "-c:a", "pcm_s16le", "-f", "caf", str(dirs["ios"] / f"{name}.caf"))
        else:
            ffmpeg("-i", str(wav), "-c:a", "libvorbis", "-q:a", "7", str(dirs["assets"] / f"{name}.ogg"))
        dur = len(x) / SR
        lufs = pyln.Meter(SR, block_size=min(0.4, dur * 0.8)).integrated_loudness(x)
        tp = 20 * np.log10(np.max(np.abs(resample_poly(x, 4, 1, axis=0))))
        print(f"{name:16s} {dur:4.2f} s  {lufs:6.1f} LUFS  true peak {tp:5.1f} dBTP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
