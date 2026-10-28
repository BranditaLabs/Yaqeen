#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات السكينة».

Every sound is synthesised from scratch here (no samples, no third-party audio), so the set is
ours, reproducible and licence-free. Design rules (see README.md):

  * No bells, no melodies, no musical instruments. Sounds are built from the world of the app:
    tasbih beads, water, a turning page, dawn air, night wind and the gold diamond's glint.
    Tones are sustained "glows" (one held chord-colour), never a tune.
  * Calm: soft attacks, no sharp transients above the bead clicks, nothing longer than 3 s.
  * The adhan itself is NOT generated — it stays a licensed human recording (spec §10).

Outputs (run from repo root):  python3 packages/brand/sounds/generate_sounds.py
  packages/brand/sounds/master/<name>.wav        48 kHz / 24-bit masters
  apps/mobile/android/app/src/main/res/raw/<name>.ogg   Android (Vorbis)
  apps/mobile/ios/Runner/Sounds/<name>.caf               iOS (16-bit PCM CAF, < 30 s)
  apps/mobile/assets/sounds/<name>.ogg                    in-app UI sounds (ui_*)

Requires: numpy, scipy, soundfile, pyloudnorm, ffmpeg (with libvorbis).
"""
from __future__ import annotations

import shutil
import warnings
import subprocess
import sys
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfilt

SR = 48_000
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
warnings.filterwarnings("ignore", message="Possible clipped samples")  # limiter below handles peaks
RNG = np.random.default_rng(1448)  # fixed seed → identical files on every run

# ----------------------------------------------------------------------------- primitives


def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def silence(dur: float) -> np.ndarray:
    return np.zeros(int(dur * SR))


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = int(at * SR)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i : i + n] += gain * sig[:n]


def band(x: np.ndarray, lo: float | None, hi: float | None, order: int = 4) -> np.ndarray:
    if lo and hi:
        sos = butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, btype="highpass", fs=SR, output="sos")
    else:
        sos = butter(order, hi, btype="lowpass", fs=SR, output="sos")
    return sosfilt(sos, x)


def noise(dur: float) -> np.ndarray:
    return RNG.standard_normal(int(dur * SR))


def swell(n: int, attack: float, release: float) -> np.ndarray:
    """Raised-cosine attack and release (seconds) — the 'breath' envelope used everywhere."""
    env = np.ones(n)
    a, r = int(attack * SR), int(release * SR)
    if a:
        env[:a] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    if r:
        env[-r:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return env


def glow(freqs: list[float], dur: float, attack: float, release: float, amps: list[float] | None = None) -> np.ndarray:
    """A held, warm tone-colour: each partial is a slightly detuned pair (slow beating = 'light')."""
    t = t_axis(dur)
    out = np.zeros_like(t)
    amps = amps or [1.0] * len(freqs)
    for f, a in zip(freqs, amps):
        ph = RNG.uniform(0, 2 * np.pi)
        out += a * (np.sin(2 * np.pi * f * t + ph) + np.sin(2 * np.pi * (f + 0.35) * t + ph * 0.7)) / 2
    return out * swell(len(t), attack, release)


def bead(f0: float = 1750.0, hardness: float = 1.0) -> np.ndarray:
    """One olive-wood tasbih bead knocking another: modal synthesis + a tiny noise exciter."""
    dur = 0.12
    t = t_axis(dur)
    ratios = [1.0, 2.63, 4.91, 7.38]
    amps = [1.0, 0.45, 0.2, 0.08]
    decays = [0.022, 0.011, 0.006, 0.004]  # short = wood, long = glass
    f0 *= RNG.uniform(0.97, 1.03)
    body = sum(a * np.exp(-t / d) * np.sin(2 * np.pi * f0 * r * t) for r, a, d in zip(ratios, amps, decays))
    exc = band(noise(dur), 2500, 9000) * np.exp(-t / 0.0015) * 0.6 * hardness
    knock = body + exc
    # beads are pairs — the second, softer contact a few ms later
    out = knock.copy()
    place(out, knock, 0.006 + RNG.uniform(0, 0.004), 0.35)
    return out


def drop(f_start: float = 700, f_end: float = 1650, dur: float = 0.09) -> np.ndarray:
    """Water drop: a bubble whose pitch rises as it closes."""
    t = t_axis(dur)
    f = f_start * (f_end / f_start) ** (t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t / 0.028) * swell(len(t), 0.002, 0.01)


def page_turn(dur: float = 0.42) -> np.ndarray:
    """A mushaf page: paper rustle that grows, flutters and lands with a soft flap."""
    t = t_axis(dur)
    rustle = band(noise(dur), 1200, 7500)
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    flutter = 0.65 + 0.35 * np.abs(np.sin(2 * np.pi * (14 + 22 * t / dur) * t))
    paper = rustle * shape * flutter * 0.5
    flap = band(noise(0.08), None, 420) * np.exp(-t_axis(0.08) / 0.02) * 1.4
    out = paper.copy()
    place(out, flap, dur - 0.09)
    return out


def sparkle(count: int, spread: float, base: float, dur: float = 1.2) -> np.ndarray:
    """The gold diamond's glint: high partials catching the light at slightly different moments."""
    out = silence(spread + dur)
    ratios = [4, 5, 6, 7.5, 8, 9, 10, 12]
    for i in range(count):
        f = base * RNG.choice(ratios) * RNG.uniform(0.996, 1.004)
        t = t_axis(dur)
        ping = np.sin(2 * np.pi * f * t) * np.exp(-t / RNG.uniform(0.18, 0.42)) * swell(len(t), 0.004, 0.05)
        place(out, ping, spread * (i / max(1, count - 1)) ** 1.3, RNG.uniform(0.25, 0.6))
    return out


def room(x: np.ndarray, rt60: float, wet: float, bright: float = 6000) -> np.ndarray:
    """Small stone room (a quiet mosque courtyard): synthetic IR, early taps + dense tail."""
    n = int(rt60 * SR)
    t = np.arange(n) / SR
    ir = band(RNG.standard_normal(n), None, bright) * np.exp(-6.9 * t / rt60)
    for delay, g in [(0.011, 0.5), (0.019, 0.35), (0.031, 0.25)]:
        ir[int(delay * SR)] += g
    ir /= np.sqrt(np.sum(ir**2))
    tail = fftconvolve(x, ir)
    dry = np.concatenate([x, np.zeros(len(tail) - len(x))])
    return (1 - wet) * dry + wet * tail * 0.9


def finish(x: np.ndarray, lufs: float, total: float | None = None) -> np.ndarray:
    """Trim, fade, loudness-normalise and keep the peak under −1.5 dBFS."""
    if total is not None:
        x = x[: int(total * SR)] if len(x) > total * SR else np.concatenate([x, silence(total - len(x) / SR)])
    x = x - np.mean(x)
    x *= swell(len(x), 0.002, min(0.25, len(x) / SR / 4))
    meter = pyln.Meter(SR, block_size=min(0.4, len(x) / SR * 0.9))
    x = pyln.normalize.loudness(x, meter.integrated_loudness(x), lufs)
    peak = np.max(np.abs(x))
    limit = 10 ** (-1.5 / 20)
    if peak > limit:
        x *= limit / peak
    return x


# ----------------------------------------------------------------------------- the family
#   Notes are named by pitch only to keep tones consonant and calm (D major colour: D, A, F#).

D3, A3, D4, Fs4, A4, D5 = 146.83, 220.0, 293.66, 369.99, 440.0, 587.33


def yq_prayer() -> np.ndarray:
    """Prayer time (alert = «تنبيه», not adhan). «الفجر يتنفس»: air rising into a wide, still glow."""
    dur = 3.0
    air = band(noise(dur), 300, 2200, 6) * swell(int(dur * SR), 1.1, 1.5) * 0.16
    body = glow([D3, A3, D4, A4], dur, 0.9, 1.6, [0.55, 0.75, 0.6, 0.3])
    halo = glow([D5 * 2, A4 * 3], dur, 1.4, 1.2, [0.05, 0.035])
    x = air + body + halo
    place(x, sparkle(5, 0.5, D4, 1.2) * 0.25, 1.0)
    return finish(room(x, 1.8, 0.35), -17, 3.0)


def yq_prayer_soon() -> np.ndarray:
    """Before the prayer. A shorter breath of the same dawn — a gentle «استعد»."""
    dur = 2.0
    air = band(noise(dur), 400, 2400, 6) * swell(int(dur * SR), 0.6, 1.0) * 0.13
    body = glow([A3, D4, Fs4], dur, 0.5, 1.2, [0.7, 0.6, 0.25])
    return finish(room(air + body, 1.4, 0.3), -18, 2.2)


def yq_azkar() -> np.ndarray:
    """Morning / evening azkar and dhikr. «السبحة»: three beads slide together, then the hand rests."""
    x = silence(1.6)
    for at, f, g in [(0.02, 1820, 0.9), (0.2, 1760, 0.8), (0.33, 1690, 1.0)]:
        place(x, bead(f), at, g)
    place(x, glow([D4, A4], 1.2, 0.25, 0.8, [0.5, 0.25]), 0.36, 0.22)
    return finish(room(x, 0.9, 0.25, 8000), -18, 1.6)


def yq_quran() -> np.ndarray:
    """Wird, khatma, Surat al-Kahf on Friday. «الصفحة»: a page turns and the room settles warm."""
    x = silence(2.4)
    place(x, page_turn(0.45), 0.0, 1.0)
    place(x, glow([D3, A3, D4], 1.9, 0.45, 1.1, [0.5, 0.7, 0.35]), 0.38, 0.55)
    return finish(room(x, 1.2, 0.25), -18, 2.4)


def yq_hifz() -> np.ndarray:
    """Hifz review due. «قطرتان»: two drops on still water — memory returning, then ripples."""
    x = silence(1.8)
    place(x, drop(720, 1700), 0.02, 1.0)
    place(x, drop(820, 1950, 0.08), 0.31, 0.75)
    place(x, glow([Fs4, A4 * 2], 1.2, 0.3, 0.8, [0.12, 0.05]), 0.35, 1.0)
    return finish(room(x, 1.6, 0.45, 7000), -19, 1.8)


def yq_suhoor() -> np.ndarray:
    """Suhoor. «سَحَر»: deep night air, a low glow, a few faint stars."""
    dur = 3.0
    wind = band(noise(dur), 120, 900) * swell(int(dur * SR), 1.0, 1.4)
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * 0.45 * t_axis(dur) + 1.0)
    x = wind * 0.25 + glow([D3, A3], dur, 1.0, 1.5, [0.7, 0.45])
    for at in (0.9, 1.35, 1.9):
        place(x, sparkle(1, 0.0, D4, 1.0), at, 0.12)
    return finish(room(x, 2.0, 0.35, 5000), -19, 3.0)


def yq_iftar() -> np.ndarray:
    """Iftar. «ماءٌ وتمرة»: water poured into a cup, then a warm, open glow."""
    x = silence(2.6)
    for i in range(7):
        at = 0.03 + i * 0.055 + RNG.uniform(0, 0.02)
        place(x, drop(500 + 70 * i, 1100 + 120 * i, 0.07), at, 0.55 - 0.04 * i)
    pour = band(noise(0.5), 600, 3500) * swell(int(0.5 * SR), 0.05, 0.3) * 0.12
    place(x, pour, 0.02)
    place(x, glow([D4, Fs4, A4], 1.9, 0.35, 1.2, [0.55, 0.35, 0.3]), 0.45, 0.6)
    return finish(room(x, 1.3, 0.3), -18, 2.6)


def yq_challenge() -> np.ndarray:
    """365 challenge, streaks, a reward is ready. «لمعة الماسة»: the gold diamond catches the light."""
    x = silence(1.8)
    place(x, sparkle(9, 0.32, D4, 1.3), 0.0, 0.8)
    place(x, glow([D4, A4, D5], 1.5, 0.08, 1.0, [0.45, 0.3, 0.12]), 0.05, 0.6)
    return finish(room(x, 1.4, 0.35, 9000), -18, 1.8)


def yq_offers() -> np.ndarray:
    """Store offers (consented). «حصاة»: one smooth pebble set down — the quietest sound in the set."""
    x = silence(0.9)
    place(x, bead(980, 0.5), 0.01, 1.0)
    place(x, glow([A4], 0.6, 0.02, 0.5, [0.2]), 0.01, 0.6)
    return finish(room(x, 0.7, 0.2), -21, 0.9)


# In-app UI sounds (played by the app, not by notifications)


def ui_bead() -> np.ndarray:
    """One azkar count (setting «صوت نقرة خفيف») — must be crisp and short at 10 taps/s."""
    x = silence(0.12)
    place(x, bead(1780), 0.0)
    return finish(x, -24, 0.12)


def ui_bead_round() -> np.ndarray:
    """A completed round / zikr («تقبّل الله»)."""
    x = silence(0.9)
    place(x, bead(1820), 0.0, 0.8)
    place(x, bead(1700), 0.09, 1.0)
    place(x, glow([D4, A4], 0.7, 0.08, 0.5, [0.4, 0.2]), 0.1, 0.35)
    return finish(room(x, 0.7, 0.2), -22, 0.9)


def ui_complete() -> np.ndarray:
    """A challenge task ticked / Qibla aligned: a small glint."""
    x = silence(0.8)
    place(x, sparkle(4, 0.12, D4, 0.6), 0.0, 0.7)
    place(x, glow([A4], 0.6, 0.02, 0.45, [0.25]), 0.0)
    return finish(room(x, 0.8, 0.25, 9000), -23, 0.8)


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
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args[:-1], "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", args[-1]], check=True)


def main() -> int:
    if not shutil.which("ffmpeg"):
        print("ffmpeg is required", file=sys.stderr)
        return 1
    master = HERE / "master"
    raw = ROOT / "apps/mobile/android/app/src/main/res/raw"
    ios = ROOT / "apps/mobile/ios/Runner/Sounds"
    assets = ROOT / "apps/mobile/assets/sounds"
    for d in (master, raw, ios, assets):
        d.mkdir(parents=True, exist_ok=True)

    meter = pyln.Meter(SR, block_size=0.1)
    for name, fn in {**NOTIFICATION_SOUNDS, **UI_SOUNDS}.items():
        x = fn()
        wav = master / f"{name}.wav"
        sf.write(wav, x, SR, subtype="PCM_24")
        if name.startswith("yq_"):
            ffmpeg("-i", str(wav), "-ac", "1", "-c:a", "libvorbis", "-q:a", "6", str(raw / f"{name}.ogg"))
            ffmpeg("-i", str(wav), "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", "-f", "caf", str(ios / f"{name}.caf"))
        else:
            ffmpeg("-i", str(wav), "-ac", "1", "-c:a", "libvorbis", "-q:a", "6", str(assets / f"{name}.ogg"))
        lufs = meter.integrated_loudness(x) if len(x) / SR > 0.15 else float("nan")
        peak = 20 * np.log10(np.max(np.abs(x)))
        print(f"{name:16s} {len(x) / SR:4.2f} s  {lufs:6.1f} LUFS  peak {peak:5.1f} dBFS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
