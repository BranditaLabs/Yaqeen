#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات يقين» (v6, new engine).

Every note is one *material* — «بلّور في الهواء», crystal in air — built from three layers that move
together:

  1. Strike  — a soft mallet on cut crystal: near-harmonic modes (never a bell's ring), the
               mallet's contact time decides how bright the touch is.
  2. Bloom   — a cloud of tiny grains on the note's own partials that swells up out of the strike
               and drifts in stereo: the "light" that makes it feel alive rather than synthetic.
  3. Air     — tuned breath (4th-order resonant noise on the note) underneath, so the tone has
               breath instead of a bare oscillator edge.

The signature is a rising perfect fourth, F♯ → B: a calling interval, short then long like the
two syllables of «يَ‑قين». Every sound is the signature, part of it, or turned around.
Owner's halal line: soft tones are fine; no instrument timbres, no bells, no melodies — three
notes at most. The adhan itself is NOT generated — it stays a licensed recording (spec §10).

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
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from pedalboard import Pedalboard, Reverb
from scipy.signal import butter, lfilter, resample_poly, sosfilt

SR = 48_000
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SEED = 2026

# The signature: F♯ rising a perfect fourth to B.
Fs5, B5, Fs6, B6, Fs4, B4 = 739.99, 987.77, 1479.98, 1975.53, 369.99, 493.88


def n_of(sec: float) -> int:
    return int(round(sec * SR))


# ----------------------------------------------------------------------------- the material


@dataclass(frozen=True)
class Material:
    """How a note feels. One family-wide default; each sound only nudges it."""
    hardness: float = 0.4   # mallet: 0 = felt-soft, 1 = crisp
    ring: float = 0.7       # strike decay (s) of the fundamental
    bloom: float = 0.55     # grain-cloud level
    air: float = 0.22       # breath level
    width: float = 0.7      # stereo spread of the bloom


SOFT = Material()


class Engine:
    def __init__(self, seed: int):
        self.rng = np.random.default_rng(seed)

    # -- layers -------------------------------------------------------------------------------

    def strike(self, f: float, sec: float, m: Material) -> np.ndarray:
        t = np.arange(n_of(sec)) / SR
        contact = 0.00015 + 0.0005 * (1 - m.hardness)  # 0.15–0.65 ms: soft mallet rolls off the highs, never the note
        out = np.zeros(len(t))
        for ratio, amp, life in [(1.0, 1.0, 1.0), (2.003, 0.3, 0.5), (3.008, 0.12, 0.28), (4.02, 0.05, 0.16)]:
            fk = f * ratio
            if fk > 16_000:
                continue
            mallet = 1 / (1 + (2 * fk * contact) ** 2)
            out += amp * mallet * np.exp(-t / (m.ring * life)) * np.sin(2 * np.pi * fk * t + self.rng.uniform(0, 6.3))
        touch = sosfilt(butter(2, [1800, 7000], "bandpass", fs=SR, output="sos"), self.rng.standard_normal(len(t)))
        out += touch * np.exp(-t / 0.001) * 0.03 * m.hardness
        return out * np.minimum(1, t / 0.0012)

    def bloom(self, f: float, sec: float, m: Material) -> np.ndarray:
        n = n_of(sec)
        out = np.zeros((n, 2))
        count = int(420 * sec)
        for _ in range(count):
            at = 0.01 + self.rng.gamma(1.6, sec * 0.09)
            if at >= sec * 0.9:
                continue
            fk = f * self.rng.choice([1, 1, 1, 2, 2, 3]) * 2 ** (self.rng.normal(0, 0.0025))
            if fk > 14_000:
                continue
            L = n_of(self.rng.uniform(0.02, 0.07))
            tt = np.arange(L) / SR
            g = np.sin(2 * np.pi * fk * tt) * np.hanning(L) * self.rng.uniform(0.3, 1.0)
            g *= np.exp(-at / (sec * 0.4))
            p = self.rng.uniform(-m.width, m.width)
            a = (p + 1) * np.pi / 4
            i = n_of(at)
            k = min(L, n - i)
            out[i : i + k, 0] += g[:k] * np.cos(a)
            out[i : i + k, 1] += g[:k] * np.sin(a)
        return out / max(1.0, np.max(np.abs(out)))

    def air(self, f: float, sec: float) -> np.ndarray:
        n = n_of(sec)
        t = np.arange(n) / SR
        x = self.rng.standard_normal(n)
        q = 70
        w = 2 * np.pi * f / SR
        al = np.sin(w) / (2 * q)
        b, a = np.array([al, 0, -al]), np.array([1 + al, -2 * np.cos(w), 1 - al])
        y = lfilter(b / a[0], a / a[0], lfilter(b / a[0], a / a[0], x))
        y /= np.max(np.abs(y)) + 1e-9
        return y * np.minimum(1, t / 0.05) ** 2 * np.exp(-t / (sec * 0.35))

    # -- one note -----------------------------------------------------------------------------

    def note(self, f: float, sec: float, *, vel: float = 1.0, pos: float = 0.0, m: Material = SOFT) -> np.ndarray:
        s = self.strike(f, sec, m)
        a = self.air(f, sec) * m.air
        ang = (pos + 1) * np.pi / 4
        core = np.stack([(s + a) * np.cos(ang), (s + a) * np.sin(ang)], axis=1)
        out = core + self.bloom(f, sec, m) * m.bloom * 0.28  # the light sits under the strike, never over it
        end = np.minimum(1, (sec - np.arange(len(out)) / SR) / min(0.25, sec / 3)) ** 2
        return out * end[:, None] * vel


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_of(at)
    k = min(len(sig), len(buf) - i)
    if k > 0:
        buf[i : i + k] += gain * sig[:k]


def canvas(sec: float) -> np.ndarray:
    return np.zeros((n_of(sec), 2))


def finish(x: np.ndarray, peak_db: float, total: float, room: float = 0.42, wet: float = 0.18) -> np.ndarray:
    """Small, damped plate → band-limit for phone speakers → soft tail → set by true peak."""
    x = Pedalboard([Reverb(room_size=room, damping=0.5, wet_level=wet, dry_level=1.0, width=1.0)])(
        x.T.astype(np.float32), SR).T.astype(np.float64)
    n = n_of(total)
    x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros((n - len(x), 2))])
    x = sosfilt(butter(2, 240, "highpass", fs=SR, output="sos"), x, axis=0)
    x = sosfilt(butter(2, 13_000, "lowpass", fs=SR, output="sos"), x, axis=0)
    fade = n_of(min(0.18, total / 4))
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    tp = np.max(np.abs(resample_poly(x, 4, 1, axis=0))) or 1.0
    return x * (10 ** (peak_db / 20) / tp)


# ----------------------------------------------------------------------------- the family


def yq_prayer(e: Engine) -> np.ndarray:
    """Prayer time (alert «تنبيه»): the full signature F♯ → B, short then long."""
    x = canvas(1.8)
    place(x, e.note(Fs5, 0.6, pos=-0.15), 0.0, 0.72)
    place(x, e.note(B5, 1.7, pos=0.15), 0.13, 1.0)
    return finish(x, -1.0, 1.8)


def yq_prayer_soon(e: Engine) -> np.ndarray:
    """Before the prayer: the first note alone, held — it waits for its answer."""
    x = canvas(1.3)
    place(x, e.note(Fs5, 1.3, m=Material(hardness=0.3)), 0.0)
    return finish(x, -5.5, 1.3)


def yq_azkar(e: Engine) -> np.ndarray:
    """Azkar & dhikr: three light counts on B, the last one left to ring."""
    x = canvas(1.3)
    tap = Material(hardness=0.5, ring=0.25, bloom=0.3, air=0.12)
    for at, v, p in [(0.0, 0.62, -0.2), (0.12, 0.6, 0.2)]:
        place(x, e.note(B5, 0.5, pos=p, m=tap), at, v)
    place(x, e.note(B5, 1.05, m=Material(hardness=0.5, ring=0.5)), 0.24, 0.85)
    return finish(x, -5.0, 1.3, room=0.36, wet=0.15)


def yq_quran(e: Engine) -> np.ndarray:
    """Wird, khatma, al-Kahf: the signature an octave lower, softer mallet, more air — unhurried."""
    x = canvas(2.1)
    deep = Material(hardness=0.15, ring=1.0, bloom=0.45, air=0.35)
    place(x, e.note(Fs4, 0.9, pos=-0.12, m=deep), 0.0, 0.8)
    place(x, e.note(B4, 2.0, pos=0.12, m=deep), 0.22, 1.0)
    return finish(x, -3.0, 2.1, room=0.5, wet=0.2)


def yq_hifz(e: Engine) -> np.ndarray:
    """Hifz review: the signature turned around (B → F♯) — returning to where it began."""
    x = canvas(1.6)
    place(x, e.note(B5, 0.6, pos=0.15), 0.0, 0.75)
    place(x, e.note(Fs5, 1.5, pos=-0.15), 0.14, 1.0)
    return finish(x, -3.5, 1.6)


def yq_suhoor(e: Engine) -> np.ndarray:
    """Suhoor: both notes together, low and slow to bloom — gentle for the night."""
    x = canvas(2.2)
    night = Material(hardness=0.05, ring=1.1, bloom=0.65, air=0.4, width=0.9)
    place(x, e.note(Fs4, 2.1, pos=-0.25, m=night), 0.0, 0.85)
    place(x, e.note(B4, 2.1, pos=0.25, m=night), 0.03, 0.7)
    return finish(x, -5.0, 2.2, room=0.55, wet=0.22)


def yq_iftar(e: Engine) -> np.ndarray:
    """Iftar: the signature, then its octave — the evening opening up."""
    x = canvas(1.9)
    place(x, e.note(Fs5, 0.55, pos=-0.2), 0.0, 0.7)
    place(x, e.note(B5, 0.8, pos=0.0), 0.11, 0.8)
    place(x, e.note(Fs6, 1.6, pos=0.2, m=Material(bloom=0.7)), 0.23, 0.8)
    return finish(x, -3.0, 1.9)


def yq_challenge(e: Engine) -> np.ndarray:
    """Challenge, streaks, a reward is ready: the signature an octave up, crisp and quick."""
    x = canvas(1.4)
    bright = Material(hardness=0.7, ring=0.5, bloom=0.7, air=0.15)
    place(x, e.note(Fs6, 0.45, pos=-0.15, m=bright), 0.0, 0.7)
    place(x, e.note(B6, 1.3, pos=0.15, m=bright), 0.08, 1.0)
    return finish(x, -3.5, 1.4, room=0.38)


def yq_offers(e: Engine) -> np.ndarray:
    """Store offers (consented): one soft B, mostly air — the quietest sound in the set."""
    x = canvas(0.9)
    place(x, e.note(B5, 0.9, m=Material(hardness=0.2, ring=0.35, bloom=0.3, air=0.3)), 0.0)
    return finish(x, -8.0, 0.9, room=0.3, wet=0.12)


def ui_bead(e: Engine) -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): a pinpoint touch of the crystal — fine at 10 taps a second."""
    x = canvas(0.08)
    place(x, e.note(B6, 0.08, m=Material(hardness=0.6, ring=0.02, bloom=0.0, air=0.0)), 0.0)
    return finish(x, -14.0, 0.08, room=0.1, wet=0.0)


def ui_bead_round(e: Engine) -> np.ndarray:
    """A completed round («تقبّل الله»): the signature in miniature."""
    x = canvas(0.9)
    m = Material(hardness=0.55, ring=0.3, bloom=0.5)
    place(x, e.note(Fs6, 0.35, pos=-0.15, m=m), 0.0, 0.7)
    place(x, e.note(B6, 0.85, pos=0.15, m=m), 0.07, 0.9)
    return finish(x, -9.0, 0.9, room=0.32, wet=0.14)


def ui_complete(e: Engine) -> np.ndarray:
    """A task ticked / Qibla aligned: one bright B with its bloom."""
    x = canvas(0.7)
    place(x, e.note(B6, 0.7, m=Material(hardness=0.6, ring=0.3, bloom=0.6)), 0.0)
    return finish(x, -10.0, 0.7, room=0.3, wet=0.14)


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
