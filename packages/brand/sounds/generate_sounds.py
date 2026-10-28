#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات يقين» (v9: «سكينة», rest and quiet — each sound acts out its activity).

  * No strike, no pop, no edge: every tone breathes in (60–650 ms), glows, and breathes out on a
    long cosine curve. Almost pure tones (2nd/3rd harmonics a whisper), two layers ±1.2 cents
    apart so they move very slowly, gently low-passed.
  * Notes arrive while the one before still glows, so they blend into a soft chord, never step.
  * A warm, dark room (high damping, no shimmer); band-limited for phone speakers; quiet by
    design (−3 dBTP prayer … −12 dBTP offers).
  * Signature: F♯ → B, a rising fourth, the second note joining the first.
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
#   «سكينة»: rest and quiet. No strike, no pop, no edge. Each tone breathes in, glows, and
#   breathes out; notes arrive while the one before is still there, so they blend, never step.


class Engine:
    def __init__(self, seed: int):
        self.rng = np.random.default_rng(seed)

    def glow(self, f: float, sec: float, *, attack: float = 0.16, vel: float = 1.0, warm: float = 1.0,
             pos: float = 0.0, drift: float | None = None) -> np.ndarray:
        """A soft, dark, held tone: almost pure (2nd/3rd harmonics a whisper), two layers ±1.2 cents
        apart so it moves very slowly, a raised-cosine breath in and a long cosine breath out."""
        t = np.arange(n_of(sec)) / SR
        n = len(t)
        sig = np.zeros(n)
        for det in (-1.2, 1.2):
            r = 2 ** (det / 1200)
            ph = self.rng.uniform(0, 2 * np.pi)
            sig += np.sin(2 * np.pi * f * r * t + ph)
            sig += 0.14 * warm * np.sin(2 * np.pi * 2 * f * r * t + ph * 1.3) * np.exp(-t / (sec * 0.35))
            sig += 0.04 * warm * np.sin(2 * np.pi * 3 * f * r * t + ph * 0.7) * np.exp(-t / (sec * 0.2))
        sig /= 2
        a = n_of(attack)
        env = np.ones(n)
        env[:a] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
        rest = n - a
        env[a:] = (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, rest))) ** 1.4  # long breath out
        sig = sosfilt(butter(2, min(4.5 * f, 6000), "lowpass", fs=SR, output="sos"), sig * env) * vel
        p = np.linspace(pos, pos if drift is None else drift, n)  # slow stereo drift
        g = (p + 1) * np.pi / 4
        return np.stack([sig * np.cos(g), sig * np.sin(g)], axis=1)

    def halo(self, f: float, sec: float, *, vel: float = 1.0) -> np.ndarray:
        """A faint light far above: an almost-pure tone that swells in late and fades — 'something
        opening'. Two decorrelated sides so it sits wide, behind everything."""
        t = np.arange(n_of(sec)) / SR
        env = np.sin(np.pi * np.clip(t / sec, 0, 1)) ** 2.2
        l = np.sin(2 * np.pi * f * t + self.rng.uniform(0, 6.3)) * env
        r = np.sin(2 * np.pi * f * 1.0008 * t + self.rng.uniform(0, 6.3)) * env
        return np.stack([l, r], axis=1) * vel

    def ground(self, f: float, sec: float, *, attack: float = 0.5, vel: float = 1.0) -> np.ndarray:
        """A low, wide foundation entering slowly underneath (kept above phone-speaker cut-off)."""
        return self.glow(f, sec, attack=attack, warm=1.6, pos=-0.4, drift=0.4, vel=vel)


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_of(at)
    k = min(len(sig), len(buf) - i)
    if k > 0:
        buf[i : i + k] += gain * sig[:k]


def canvas(sec: float) -> np.ndarray:
    return np.zeros((n_of(sec), 2))


def finish(x: np.ndarray, peak_db: float, total: float, room: float = 0.62, wet: float = 0.24) -> np.ndarray:
    """A warm, dark room (high damping: no shimmer) → band-limit → level by true peak."""
    x = Pedalboard([Reverb(room_size=room, damping=0.85, wet_level=wet, dry_level=1.0, width=1.0)])(
        x.T.astype(np.float32), SR).T.astype(np.float64)
    n = n_of(total)
    x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros((n - len(x), 2))])
    x = sosfilt(butter(2, 260, "highpass", fs=SR, output="sos"), x, axis=0)
    x = sosfilt(butter(2, 7000, "lowpass", fs=SR, output="sos"), x, axis=0)
    fade = n_of(total * 0.35)
    x[-fade:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fade)))[:, None] ** 1.5
    tp = np.max(np.abs(resample_poly(x, 4, 1, axis=0))) or 1.0
    return x * (10 ** (peak_db / 20) / tp)


# ----------------------------------------------------------------------------- the family
#   Signature: F♯ → B. Each sound acts out what it calls you to — softly.

D5_, Cs6, E6 = 587.33, 1108.73, 1318.51


def yq_prayer(e: Engine) -> np.ndarray:
    """Prayer time — «الاصطفاف»: the row forming. F♯ comes in, B stands beside it, then a low
    foundation settles underneath and a faint light opens above: a space filling, calm and sure."""
    x = canvas(2.8)
    place(x, e.glow(Fs5, 2.5, attack=0.16, pos=-0.3, drift=-0.15), 0.0, 0.8)
    place(x, e.glow(B5, 2.3, attack=0.2, pos=0.3, drift=0.15), 0.3, 0.76)
    place(x, e.ground(B4, 2.2, attack=0.55), 0.55, 0.42)
    place(x, e.halo(Fs6 * 2, 1.9), 0.75, 0.035)
    return finish(x, -3.0, 2.8, room=0.7, wet=0.27)


def yq_prayer_soon(e: Engine) -> np.ndarray:
    """Before the prayer — «تهيّؤ»: getting ready. One tone breathes twice, the second breath
    fuller, like a gentle «it's almost time»."""
    x = canvas(2.0)
    place(x, e.glow(Fs5, 0.9, attack=0.18, pos=-0.1), 0.0, 0.6)
    place(x, e.glow(Fs5, 1.5, attack=0.22, pos=0.1), 0.5, 0.85)
    return finish(x, -6.0, 2.0)


def yq_azkar(e: Engine) -> np.ndarray:
    """Azkar & dhikr — «التسبيح»: a slow, even count. Four soft breaths on B, moving bead by bead
    from right to left, the last one left to rest — the hand pausing on the misbaha."""
    x = canvas(2.3)
    for i, (at, p) in enumerate([(0.0, 0.45), (0.28, 0.15), (0.56, -0.15), (0.84, -0.45)]):
        last = i == 3
        place(x, e.glow(B5, 1.4 if last else 0.75, attack=0.05, warm=0.8, pos=p), at, 0.85 if last else 0.62)
    return finish(x, -5.5, 2.3)


def yq_quran(e: Engine) -> np.ndarray:
    """Wird, khatma, al-Kahf — «التدبّر»: settling in to read. A warm low tone holds like a breath
    before recitation; F♯ and B enter slowly above it and stay — unhurried, contemplative."""
    x = canvas(3.0)
    place(x, e.ground(B4, 2.9, attack=0.45), 0.0, 0.55)
    place(x, e.glow(Fs5, 2.4, attack=0.35, warm=1.2, pos=-0.2, drift=-0.05), 0.35, 0.62)
    place(x, e.glow(B5, 2.1, attack=0.4, warm=1.2, pos=0.2, drift=0.05), 0.8, 0.55)
    return finish(x, -4.5, 3.0, room=0.72, wet=0.27)


def yq_hifz(e: Engine) -> np.ndarray:
    """Hifz review — «التكرار»: how memorising sounds. The signature once, then again softer,
    a little further away — said, then repeated to hold it."""
    x = canvas(2.6)
    place(x, e.glow(Fs5, 1.1, attack=0.1, pos=-0.15), 0.0, 0.8)
    place(x, e.glow(B5, 1.2, attack=0.12, pos=0.15), 0.2, 0.75)
    place(x, e.glow(Fs5, 1.1, attack=0.1, pos=-0.35), 0.85, 0.45)
    place(x, e.glow(B5, 1.5, attack=0.12, pos=0.35), 1.05, 0.42)
    return finish(x, -5.0, 2.6)


def yq_suhoor(e: Engine) -> np.ndarray:
    """Suhoor — «السَّحَر»: the last dark hour. A low, wide hush rises very slowly; far above, one
    faint point of light appears and fades, like the last star before Fajr."""
    x = canvas(3.0)
    place(x, e.ground(Fs4, 2.9, attack=0.8), 0.0, 0.7)
    place(x, e.glow(B4, 2.6, attack=0.75, warm=1.3, pos=0.3, drift=-0.1), 0.15, 0.5)
    place(x, e.halo(B6, 1.3), 1.1, 0.045)
    return finish(x, -9.0, 3.0, room=0.78, wet=0.3)


def yq_iftar(e: Engine) -> np.ndarray:
    """Iftar — «الفرحة»: the fast is broken. Three notes open quickly into a warm, bright chord and
    linger — relief and gratitude, still gentle."""
    x = canvas(2.6)
    place(x, e.glow(Fs5, 2.3, attack=0.08, pos=-0.3), 0.0, 0.66)
    place(x, e.glow(B5, 2.15, attack=0.09, pos=0.0), 0.13, 0.66)
    place(x, e.glow(Fs6, 2.0, attack=0.1, warm=0.6, pos=0.3), 0.26, 0.5)
    place(x, e.halo(B6, 1.6), 0.4, 0.03)
    return finish(x, -5.0, 2.6)


def yq_challenge(e: Engine) -> np.ndarray:
    """Challenge, streaks, a reward — «الخطوة»: one more step on the journey. Three soft steps
    upward (F♯, B, F♯ above), each landing gently, the top one resting."""
    x = canvas(2.2)
    place(x, e.glow(Fs5, 0.8, attack=0.05, pos=-0.3), 0.0, 0.6)
    place(x, e.glow(B5, 0.9, attack=0.05, pos=0.0), 0.2, 0.66)
    place(x, e.glow(Fs6, 1.7, attack=0.06, warm=0.6, pos=0.3), 0.4, 0.72)
    return finish(x, -5.0, 2.2)


def yq_offers(e: Engine) -> np.ndarray:
    """Store offers — «هدية»: a small gift. One soft tone with a faint glint of light on top."""
    x = canvas(1.5)
    place(x, e.glow(B5, 1.3, attack=0.1, warm=0.6), 0.0)
    place(x, e.halo(B6 * 1.5, 0.9), 0.12, 0.05)
    return finish(x, -12.0, 1.5, room=0.5, wet=0.2)


def ui_bead(e: Engine) -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): the softest touch, fine at 10 taps a second."""
    x = canvas(0.09)
    place(x, e.glow(B6, 0.09, attack=0.006, warm=0.4), 0.0)
    return finish(x, -18.0, 0.09, wet=0.0)


def ui_bead_round(e: Engine) -> np.ndarray:
    """A completed round («تقبّل الله»): the count resolving — B, then F♯ above, resting."""
    x = canvas(1.3)
    place(x, e.glow(B5, 1.0, attack=0.04, warm=0.6, pos=-0.15), 0.0, 0.75)
    place(x, e.glow(Fs6, 1.1, attack=0.06, warm=0.5, pos=0.15), 0.16, 0.7)
    return finish(x, -12.0, 1.3, room=0.5, wet=0.2)


def ui_complete(e: Engine) -> np.ndarray:
    """A task ticked / Qibla aligned: one soft glow with light above it."""
    x = canvas(1.0)
    place(x, e.glow(B6, 0.85, attack=0.04, warm=0.5), 0.0)
    place(x, e.halo(B6 * 2, 0.6), 0.08, 0.03)
    return finish(x, -13.0, 1.0, room=0.45, wet=0.18)


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
