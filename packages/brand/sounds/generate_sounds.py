#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات يقين» (v5).

Built to the rules premium system sounds follow:

  * Short (0.5–1.4 s), clean, at most two elements. Restraint is the luxury.
  * Pitched where phone speakers are clear (≈ 900 Hz – 2.6 kHz fundamentals); body below that
    is a whisper, so nothing turns to mud on a phone.
  * One voice: a soft FM tone. The brightness (modulation index) blooms at the touch and melts
    away within ~80 ms, leaving a pure, round decay — glassy without being a bell (harmonic 1:1
    ratio only) and without imitating any instrument.
  * One signature, the name itself: يَ‑قين is two syllables, short then long — a short tone rising
    a fifth into a long one. Every sound is that signature, part of it, or turned around.
  * A small, polished space (short plate, low mix). No saturation: tails decay pure.
  * Levelled by true peak like system sounds (−1 dBTP prayer … −8 dBTP offers).
  * Halal line (owner's decision): soft tones are fine; no instrument timbres, no bells, no
    melodies — three tones at most.
  * The adhan itself is NOT generated — it stays a licensed human recording (spec §10).

Outputs (run from repo root):  python3 packages/brand/sounds/generate_sounds.py
  packages/brand/sounds/master/<name>.wav               48 kHz / 24-bit stereo masters
  apps/mobile/android/app/src/main/res/raw/<name>.ogg   Android (Vorbis, stereo)
  apps/mobile/ios/Runner/Sounds/<name>.caf              iOS (16-bit PCM CAF, stereo, < 30 s)
  apps/mobile/assets/sounds/<name>.ogg                  in-app UI sounds (ui_*)

Requires: numpy, scipy, soundfile, pyloudnorm (report only), pedalboard, ffmpeg (with libvorbis).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import warnings
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from pedalboard import Pedalboard, Reverb
from scipy.signal import butter, resample_poly, sosfilt

SR = 48_000
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
warnings.filterwarnings("ignore", message="Possible clipped samples")
RNG = np.random.default_rng(1448)  # fixed seed → identical files on every run

# The signature lives on A and its fifth E — high enough to sing on a phone speaker.
A4, E5, A5, E6, A6, E7 = 440.00, 659.26, 880.00, 1318.51, 1760.00, 2637.02


# ----------------------------------------------------------------------------- the voice


def n_of(sec: float) -> int:
    return int(round(sec * SR))


def tone(f: float, sec: float, *, vel: float = 1.0, decay: float = 0.42, shine: float = 1.6,
         shine_decay: float = 0.07, attack: float = 0.003, body: float = 0.12, pos: float = 0.0) -> np.ndarray:
    """One soft FM tone. `shine` is the modulation index at the touch; it melts away over
    `shine_decay`, leaving a round, near-pure decay. `body` adds the octave below, very quietly."""
    t = np.arange(n_of(sec)) / SR
    index = shine * np.exp(-t / shine_decay)
    mod = np.sin(2 * np.pi * f * t)
    car = np.sin(2 * np.pi * f * t + index * mod)
    env = np.exp(-t / decay)
    a = n_of(attack)
    env[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    sig = car * env
    if body:
        sig += body * np.sin(2 * np.pi * f / 2 * t) * np.exp(-t / (decay * 0.8)) * np.minimum(1, t / 0.008)
    # a felt-soft touch: 2 ms of filtered air
    touch = sosfilt(butter(2, [2.5 * f, min(9 * f, 16_000)], "bandpass", fs=SR, output="sos"),
                    RNG.standard_normal(len(t))) * np.exp(-t / 0.0015) * 0.05
    sig = (sig + touch) * vel
    sig[-n_of(0.02):] *= np.linspace(1, 0, n_of(0.02))
    g = (pos + 1) * np.pi / 4
    return np.stack([sig * np.cos(g), sig * np.sin(g)], axis=1)


def silence(sec: float) -> np.ndarray:
    return np.zeros((n_of(sec), 2))


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_of(at)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i : i + n] += gain * sig[:n]


# ----------------------------------------------------------------------------- finish


def space(x: np.ndarray, size: float = 0.32, wet: float = 0.14) -> np.ndarray:
    """A small, bright-but-damped plate. Low mix: polish, not a cathedral."""
    board = Pedalboard([Reverb(room_size=size, damping=0.55, wet_level=wet, dry_level=1.0, width=0.85)])
    return board(x.T.astype(np.float32), SR).T.astype(np.float64)


def finish(x: np.ndarray, peak_db: float, total: float) -> np.ndarray:
    """Clean band-limit and a soft tail, then set by true peak (how system sounds are levelled):
    −1 dBTP for prayer, a few dB lower for gentler roles, much lower for offers."""
    n = n_of(total)
    x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros((n - len(x), 2))])
    x = sosfilt(butter(2, 220, "highpass", fs=SR, output="sos"), x, axis=0)   # nothing a phone can't play
    x = sosfilt(butter(2, 14_000, "lowpass", fs=SR, output="sos"), x, axis=0)  # no fizz
    fade = n_of(min(0.12, total / 4))
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    tp = np.max(np.abs(resample_poly(x, 4, 1, axis=0))) or 1.0
    return x * (10 ** (peak_db / 20) / tp)


# ----------------------------------------------------------------------------- the family
#   Signature «يَ‑قين»: a short tone, then a long one a fifth above.


def yq_prayer() -> np.ndarray:
    """Prayer time (alert «تنبيه»): the full signature, short → long."""
    x = silence(1.4)
    place(x, tone(A5, 0.5, decay=0.12, pos=-0.12), 0.0, 0.78)
    place(x, tone(E6, 1.35, decay=0.48, pos=0.12), 0.115, 1.0)
    return finish(space(x), -1.0, 1.4)


def yq_prayer_soon() -> np.ndarray:
    """Before the prayer: the first syllable alone, held — an invitation, not an alarm."""
    x = silence(1.0)
    place(x, tone(A5, 1.0, decay=0.36, shine=1.3), 0.0)
    return finish(space(x), -3.0, 1.0)


def yq_azkar() -> np.ndarray:
    """Azkar & dhikr: three light counts on the long syllable's note."""
    x = silence(1.0)
    for at, v, p in [(0.0, 0.7, -0.15), (0.11, 0.66, 0.15), (0.22, 0.9, 0.0)]:
        place(x, tone(E6, 0.75, decay=0.2 if at < 0.2 else 0.34, shine=1.2, body=0.06, pos=p), at, v)
    return finish(space(x, 0.28, 0.12), -5.0, 1.0)


def yq_quran() -> np.ndarray:
    """Wird, khatma, al-Kahf: the signature an octave lower, softer and unhurried."""
    x = silence(1.7)
    place(x, tone(A4, 0.7, decay=0.2, shine=0.9, attack=0.012, body=0.0, pos=-0.1), 0.0, 0.8)
    place(x, tone(E5, 1.65, decay=0.62, shine=0.9, attack=0.012, body=0.0, pos=0.1), 0.19, 1.0)
    return finish(space(x, 0.4, 0.16), -3.0, 1.7)


def yq_hifz() -> np.ndarray:
    """Hifz review: the signature turned around — long note first, coming home."""
    x = silence(1.3)
    place(x, tone(E6, 0.6, decay=0.14, pos=0.12), 0.0, 0.8)
    place(x, tone(A5, 1.25, decay=0.45, pos=-0.12), 0.13, 1.0)
    return finish(space(x), -2.5, 1.3)


def yq_suhoor() -> np.ndarray:
    """Suhoor: both syllables at once, softly bloomed — quiet, for the night."""
    x = silence(1.6)
    place(x, tone(A4, 1.6, decay=0.6, shine=0.6, attack=0.04, body=0.0, pos=-0.2), 0.0, 0.85)
    place(x, tone(E5, 1.6, decay=0.55, shine=0.6, attack=0.04, body=0.0, pos=0.2), 0.02, 0.7)
    return finish(space(x, 0.45, 0.18), -5.0, 1.6)


def yq_iftar() -> np.ndarray:
    """Iftar: the signature, then its octave — opening up."""
    x = silence(1.5)
    place(x, tone(A5, 0.5, decay=0.12, pos=-0.2), 0.0, 0.75)
    place(x, tone(E6, 0.7, decay=0.2, pos=0.0), 0.1, 0.85)
    place(x, tone(A6, 1.3, decay=0.45, shine=1.3, body=0.08, pos=0.2), 0.2, 0.9)
    return finish(space(x), -3.5, 1.5)


def yq_challenge() -> np.ndarray:
    """Challenge, streaks, a reward is ready: the signature an octave up, quick and bright."""
    x = silence(1.1)
    place(x, tone(E6, 0.4, decay=0.09, shine=1.9, pos=-0.15), 0.0, 0.7)
    place(x, tone(A6, 1.05, decay=0.36, shine=1.9, body=0.08, pos=0.15), 0.075, 1.0)
    return finish(space(x, 0.3, 0.14), -4.0, 1.1)


def yq_offers() -> np.ndarray:
    """Store offers (consented): one soft tone — the quietest sound in the set."""
    x = silence(0.65)
    place(x, tone(E6, 0.65, decay=0.18, shine=0.8, attack=0.006, body=0.05), 0.0)
    return finish(space(x, 0.25, 0.1), -8.0, 0.65)


# In-app UI sounds


def ui_bead() -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): a pinpoint, fine at 10 taps a second."""
    x = silence(0.07)
    place(x, tone(E7, 0.07, decay=0.018, shine=0.7, attack=0.0015, body=0.0), 0.0)
    return finish(x, -14.0, 0.07)


def ui_bead_round() -> np.ndarray:
    """A completed round («تقبّل الله»): the signature in miniature."""
    x = silence(0.7)
    place(x, tone(E6, 0.3, decay=0.07, pos=-0.15), 0.0, 0.7)
    place(x, tone(A6, 0.65, decay=0.22, pos=0.15), 0.06, 0.9)
    return finish(space(x, 0.25, 0.1), -9.0, 0.7)


def ui_complete() -> np.ndarray:
    """A task ticked / Qibla aligned: one bright touch."""
    x = silence(0.5)
    place(x, tone(A6, 0.5, decay=0.15, shine=1.4, body=0.0), 0.0)
    return finish(space(x, 0.22, 0.1), -10.0, 0.5)


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


def ffmpeg(*args: str) -> None:
    # bitexact: no random Ogg serials or encoder tags, so re-running gives identical files
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args[:-1],
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", args[-1]], check=True)


def main() -> int:
    if not shutil.which("ffmpeg"):
        print("ffmpeg is required", file=sys.stderr)
        return 1
    master_dir = HERE / "master"
    raw = ROOT / "apps/mobile/android/app/src/main/res/raw"
    ios = ROOT / "apps/mobile/ios/Runner/Sounds"
    assets = ROOT / "apps/mobile/assets/sounds"
    for d in (master_dir, raw, ios, assets):
        d.mkdir(parents=True, exist_ok=True)

    for name, fn in {**NOTIFICATION_SOUNDS, **UI_SOUNDS}.items():
        x = fn()
        wav = master_dir / f"{name}.wav"
        sf.write(wav, x, SR, subtype="PCM_24")
        if name.startswith("yq_"):
            ffmpeg("-i", str(wav), "-c:a", "libvorbis", "-q:a", "7", str(raw / f"{name}.ogg"))
            ffmpeg("-i", str(wav), "-ar", "44100", "-c:a", "pcm_s16le", "-f", "caf", str(ios / f"{name}.caf"))
        else:
            ffmpeg("-i", str(wav), "-c:a", "libvorbis", "-q:a", "7", str(assets / f"{name}.ogg"))
        dur = len(x) / SR
        lufs = pyln.Meter(SR, block_size=min(0.4, dur * 0.8)).integrated_loudness(x)
        tp = 20 * np.log10(np.max(np.abs(resample_poly(x, 4, 1, axis=0))))
        print(f"{name:16s} {dur:4.2f} s  {lufs:6.1f} LUFS  true peak {tp:5.1f} dBTP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
