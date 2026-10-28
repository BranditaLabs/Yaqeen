#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات يقين».

A sonic identity, synthesised from scratch (no samples, no third-party audio): ours, reproducible,
licence-free.

  * One signature voice, «صوت يقين»: soft, glassy, harmonic partials only, each fading at its own
    rate (bright at the touch, dark as it rests), a breath of air at the onset, a quiet sub-octave
    and two detuned layers for width.
  * One signature interval is the brand: D opening to A. Every sound is that signature, a part of
    it, or it turned around — so users know it's Yaqeen before they read the screen.
  * Kept halal-conscious: no instrument timbres, no bells, no melodies. Three tones at most.
  * One space: a warm hall whose highs fade faster than its lows, a subtle ping-pong echo, stereo.
  * Product-grade mastering: phone low-cut, gentle EQ and compression, loudness by role
    (≈ −17 LUFS prayer … −22 LUFS offers), true peak ≤ −1 dBTP. Nothing over 3 s.
  * The adhan itself is NOT generated — it stays a licensed human recording (spec §10).

Outputs (run from repo root):  python3 packages/brand/sounds/generate_sounds.py
  packages/brand/sounds/master/<name>.wav               48 kHz / 24-bit stereo masters
  apps/mobile/android/app/src/main/res/raw/<name>.ogg   Android (Vorbis, stereo)
  apps/mobile/ios/Runner/Sounds/<name>.caf              iOS (16-bit PCM CAF, stereo, < 30 s)
  apps/mobile/assets/sounds/<name>.ogg                  in-app UI sounds (ui_*)

Requires: numpy, scipy, soundfile, pyloudnorm, ffmpeg (with libvorbis).
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
from scipy.signal import butter, fftconvolve, lfilter, resample_poly, sosfilt

SR = 48_000
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
warnings.filterwarnings("ignore", message="Possible clipped samples")  # the limiter handles peaks
RNG = np.random.default_rng(1448)  # fixed seed → identical files on every run

# ----------------------------------------------------------------------------- helpers


def n_of(sec: float) -> int:
    return int(round(sec * SR))


def t_axis(sec: float) -> np.ndarray:
    return np.arange(n_of(sec)) / SR


def stereo_silence(sec: float) -> np.ndarray:
    return np.zeros((n_of(sec), 2))


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_of(at)
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
    return sosfilt(sos, x, axis=0)


def raised(n: int, a: int, r: int) -> np.ndarray:
    env = np.ones(n)
    if a > 0:
        env[: min(a, n)] = (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a)))[: min(a, n)]
    if r > 0:
        r = min(r, n)
        env[-r:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return env


def pan(mono: np.ndarray, p: float) -> np.ndarray:
    """Equal-power pan, p in [-1, 1]."""
    a = (p + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def biquad(x: np.ndarray, kind: str, f0: float, gain_db: float = 0.0, q: float = 0.707) -> np.ndarray:
    """RBJ cookbook peaking / shelving filters."""
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / SR
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / (2 * q)
    if kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "highshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)]
        a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa]
    else:
        raise ValueError(kind)
    b, a = np.array(b) / a[0], np.array(a) / a[0]
    return lfilter(b, a, x, axis=0)


# ----------------------------------------------------------------------------- the space


def hall(x: np.ndarray, rt: float = 2.2, wet: float = 0.3, pre: float = 0.018) -> np.ndarray:
    """Warm stone hall: frequency-dependent decay (highs fade faster), diffuse build-up, early
    reflections, decorrelated stereo. Wet path is low-cut and high-cut so the tail stays clean."""
    n = n_of(rt * 1.1)
    t = np.arange(n) / SR
    edges = [20, 250, 500, 1000, 2000, 4000, 8000, 20_000]
    rts = [1.15, 1.0, 0.95, 0.85, 0.7, 0.5, 0.33]
    ir = np.zeros((n, 2))
    for (lo, hi), k in zip(zip(edges[:-1], edges[1:]), rts):
        nb = band(RNG.standard_normal((n, 2)), lo, hi, 2)
        ir += nb * np.exp(-6.9 * t / (rt * k))[:, None]
    ir *= (1 - np.exp(-t / 0.035))[:, None]  # diffusion builds up instead of a hard click
    for ch in range(2):
        for _ in range(7):
            d = RNG.uniform(0.006, 0.045)
            ir[n_of(d), ch] += RNG.uniform(0.15, 0.45) * (1 - d / 0.05)
    ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
    ir = np.concatenate([np.zeros((n_of(pre), 2)), ir])
    wet_sig = np.stack([fftconvolve(x[:, 0], ir[:, 0]) + 0.25 * fftconvolve(x[:, 1], ir[:, 0]),
                        fftconvolve(x[:, 1], ir[:, 1]) + 0.25 * fftconvolve(x[:, 0], ir[:, 1])], axis=1)
    wet_sig = band(band(wet_sig, 180, None, 2), None, 9000, 2)
    dry = np.concatenate([x, np.zeros((len(wet_sig) - len(x), 2))])
    return dry * (1 - wet * 0.5) + wet_sig * wet * 0.55


# ----------------------------------------------------------------------------- mastering


def compress(x: np.ndarray, thresh_db: float = -22, ratio: float = 2.0, att: float = 0.008, rel: float = 0.16) -> np.ndarray:
    level = np.max(np.abs(x), axis=1)
    env = np.zeros_like(level)
    a_att, a_rel = np.exp(-1 / (att * SR)), np.exp(-1 / (rel * SR))
    e = 0.0
    for i, v in enumerate(level):
        e = a_att * e + (1 - a_att) * v if v > e else a_rel * e + (1 - a_rel) * v
        env[i] = e
    db = 20 * np.log10(np.maximum(env, 1e-9))
    over = np.maximum(0, db - thresh_db)
    gain = 10 ** (-(over - over / ratio) / 20)
    return x * gain[:, None]


def limit(x: np.ndarray, ceiling_db: float = -1.0) -> np.ndarray:
    """Look-ahead limiter on the 4× oversampled peak (≈ true peak)."""
    ceiling = 10 ** (ceiling_db / 20)
    up = resample_poly(x, 4, 1, axis=0)
    peak = np.max(np.abs(up).reshape(-1, 4, 2), axis=(1, 2))[: len(x)]
    need = np.minimum(1.0, ceiling / np.maximum(peak, 1e-9))
    look = n_of(0.004)
    # gain must already be down when the peak arrives: running min over the look-ahead window, smoothed
    padded = np.concatenate([need, np.ones(look)])
    g = np.array([padded[i : i + look].min() for i in range(len(need))])
    k = np.hanning(2 * look + 1)
    g = np.convolve(np.concatenate([np.ones(look), g, np.ones(look)]), k / k.sum(), mode="valid")[: len(x)]
    y = x * g[:, None]
    tp = np.max(np.abs(resample_poly(y, 4, 1, axis=0)))
    return y * min(1.0, ceiling / tp)


def master(x: np.ndarray, lufs: float, total: float, squeeze: bool = False) -> np.ndarray:
    n = n_of(total)
    x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros((n - len(x), 2))])
    x = band(x, 110, None, 2)                # phone speakers can't play below this; keeps it clean
    x = biquad(x, "peak", 340, -2.0, 0.9)    # less box
    x = biquad(x, "peak", 3200, -1.0, 1.2)   # less edge
    x = biquad(x, "highshelf", 10_000, 1.5)  # air
    if squeeze:  # only for transient-heavy material; tonal sounds keep their natural decay
        x = compress(x)
        x = np.tanh(x * 1.5) / np.tanh(1.5)
    x -= np.mean(x, axis=0)
    x *= raised(n, n_of(0.002), n_of(min(0.3, total / 4)))[:, None]
    meter = pyln.Meter(SR, block_size=min(0.4, total * 0.9))
    x = pyln.normalize.loudness(x, meter.integrated_loudness(x), lufs)
    return limit(x)


# ----------------------------------------------------------------------------- the signature voice
#   «صوت يقين»: one voice for the whole family. Harmonic partials only (never a bell's
#   inharmonic ring), each fading at its own rate — bright at the touch, dark as it rests — a
#   breath of air at the onset, a quiet sub-octave for warmth, two layers detuned for width.

D4, A4, D5, A5, D6, A6 = 293.66, 440.00, 587.33, 880.00, 1174.66, 1760.00


def voice(f: float, sec: float, *, vel: float = 1.0, bright: float = 0.72, tau: float = 0.8,
          attack: float = 0.008, air: float = 0.10, warmth: float = 0.18, width: float = 0.3,
          pos: float = 0.0) -> np.ndarray:
    t = t_axis(sec)
    n = len(t)
    out = np.zeros((n, 2))
    for detune, side in [(-1.8, -width), (1.8, width)]:
        ratio = 2 ** (detune / 1200)
        mono = np.zeros(n)
        for k in range(1, 9):
            fk = f * k * ratio
            if fk > 15_000:
                break
            amp = (1 / k ** 1.7) * (bright ** (k - 1)) * (1.0 if k % 2 else 0.7)
            tk = tau / (1 + 0.7 * (k - 1))
            ak = max(0.002, attack / (1 + 0.3 * (k - 1)))
            mono += amp * np.sin(2 * np.pi * fk * t + RNG.uniform(0, 2 * np.pi)) * np.exp(-t / tk) * raised(n, n_of(ak), 0)
        if warmth:
            mono += warmth * np.sin(2 * np.pi * (f / 2) * ratio * t) * np.exp(-t / (tau * 0.9)) * raised(n, n_of(attack * 3), 0)
        out += pan(mono, side + pos) * 0.5
    if air:
        breath = band(RNG.standard_normal(n), 1.5 * f, min(6 * f, 14_000), 2)
        breath *= np.exp(-t / 0.018) * raised(n, n_of(0.003), 0)
        out += pan(breath, pos) * air
    out *= raised(n, 0, n_of(min(0.15, sec / 3)))[:, None]
    return out * vel


def halo(f: float, sec: float, gain: float = 0.08) -> np.ndarray:
    """A faint octave of light that swells in after the touch and fades — the 'premium' lift."""
    t = t_axis(sec)
    n = len(t)
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t + 1.1)
    env = raised(n, n_of(sec * 0.35), n_of(sec * 0.6))
    return np.stack([s * env, np.roll(s, n_of(0.004)) * env], axis=1) * gain


def echo(x: np.ndarray, gain: float = 0.12) -> np.ndarray:
    """Ping-pong echo, darkened — the polish you hear in system sounds, kept subtle."""
    out = np.concatenate([x, np.zeros((n_of(0.6), 2))])
    for d, ch, g in [(0.17, 1, gain), (0.34, 0, gain * 0.55), (0.51, 1, gain * 0.3)]:
        src = band(x.mean(axis=1), 400, 5000, 2)
        i = n_of(d)
        out[i : i + len(src), ch] += src * g
    return out


# ----------------------------------------------------------------------------- the family
#   One interval is the brand: D opening to A. Every sound is that signature, a part of it, or it
#   turned around. Never more than three tones, never a tune.


def yq_prayer() -> np.ndarray:
    """Prayer time (alert «تنبيه»): the full signature, warm and wide."""
    x = stereo_silence(2.8)
    place(x, voice(D5, 2.6, tau=0.68, pos=-0.15), 0.0, 0.85)
    place(x, voice(A5, 2.5, tau=0.62, pos=0.15), 0.16, 0.75)
    place(x, voice(D4, 2.6, tau=0.81, bright=0.5, air=0, warmth=0, attack=0.03), 0.0, 0.32)
    place(x, halo(D6, 2.0, 0.05), 0.25)
    return master(hall(echo(x, 0.1), 1.9, 0.22), -17.0, 2.8)


def yq_prayer_soon() -> np.ndarray:
    """Before the prayer: the signature's first tone alone — an invitation, not an alarm."""
    x = stereo_silence(1.8)
    place(x, voice(D5, 1.7, tau=0.56), 0.0, 0.85)
    place(x, halo(D6, 1.4, 0.04), 0.1)
    return master(hall(echo(x, 0.09), 1.6, 0.21), -18.5, 1.8)


def yq_azkar() -> np.ndarray:
    """Azkar & dhikr: three soft taps of the signature's second tone, like counting."""
    x = stereo_silence(1.6)
    for at, vel, p in [(0.0, 0.62, -0.2), (0.17, 0.62, 0.2), (0.34, 0.85, 0.0)]:
        place(x, voice(A5, 1.2, tau=0.20, bright=0.66, air=0.07, pos=p), at, vel)
    place(x, halo(A6, 1.0, 0.03), 0.38)
    return master(hall(x, 1.4, 0.21), -18.5, 1.6)


def yq_quran() -> np.ndarray:
    """Wird, khatma, al-Kahf: the signature an octave down, slow to open — calm, dignified."""
    x = stereo_silence(2.4)
    place(x, voice(D4, 2.3, tau=0.81, bright=0.6, attack=0.05, air=0.04, pos=-0.1), 0.0, 0.9)
    place(x, voice(A4, 2.1, tau=0.74, bright=0.58, attack=0.05, air=0.03, pos=0.1), 0.22, 0.62)
    return master(hall(x, 1.9, 0.23), -18.5, 2.4)


def yq_hifz() -> np.ndarray:
    """Hifz review: the signature turned around (A back to D) — something returning."""
    x = stereo_silence(1.8)
    place(x, voice(A5, 1.6, tau=0.43, pos=0.15), 0.0, 0.75)
    place(x, voice(D5, 1.5, tau=0.50, pos=-0.15), 0.18, 0.8)
    return master(hall(echo(x, 0.08), 1.6, 0.21), -18.5, 1.8)


def yq_suhoor() -> np.ndarray:
    """Suhoor: both tones together, swelling slowly out of the night, dark and wide."""
    x = stereo_silence(2.6)
    place(x, voice(D4, 2.5, tau=0.99, bright=0.5, attack=0.22, air=0, pos=-0.25), 0.0, 0.8)
    place(x, voice(A4, 2.4, tau=0.93, bright=0.5, attack=0.24, air=0, pos=0.25), 0.05, 0.6)
    place(x, halo(D6, 1.8, 0.025), 0.6)
    return master(hall(x, 2.2, 0.25), -19.5, 2.6)


def yq_iftar() -> np.ndarray:
    """Iftar: the signature, then its octave — opening up, warm."""
    x = stereo_silence(2.2)
    for i, (f, p, g) in enumerate([(D5, -0.25, 0.75), (A5, 0.05, 0.68), (D6, 0.3, 0.5)]):
        place(x, voice(f, 2.0 - 0.1 * i, tau=0.59 - 0.1 * i, pos=p), 0.075 * i, g)
    return master(hall(echo(x, 0.08), 1.8, 0.22), -18.0, 2.2)


def yq_challenge() -> np.ndarray:
    """Challenge, streaks, a reward is ready: the signature quick and bright, an octave up."""
    x = stereo_silence(1.6)
    place(x, voice(A5, 1.4, tau=0.34, bright=0.75, air=0.12, pos=-0.2), 0.0, 0.72)
    place(x, voice(D6, 1.4, tau=0.37, bright=0.72, air=0.12, pos=0.2), 0.055, 0.68)
    place(x, halo(A6, 1.1, 0.035), 0.1)
    return master(hall(echo(x, 0.11), 1.5, 0.22), -18.0, 1.6)


def yq_offers() -> np.ndarray:
    """Store offers (consented): one muted tone — the quietest sound in the set."""
    x = stereo_silence(1.0)
    place(x, voice(A5, 0.95, tau=0.22, bright=0.45, air=0.05), 0.0, 0.8)
    return master(hall(x, 1.1, 0.18), -22.0, 1.0)


# In-app UI sounds


def ui_bead() -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): a tiny, soft tap — fine at 10 taps a second."""
    x = stereo_silence(0.09)
    place(x, voice(A6, 0.09, tau=0.01, bright=0.4, attack=0.0015, air=0.05, warmth=0, width=0.1), 0.0)
    return master(x, -25.0, 0.09)


def ui_bead_round() -> np.ndarray:
    """A completed round («تقبّل الله»): the signature in miniature."""
    x = stereo_silence(1.0)
    place(x, voice(D6, 0.9, tau=0.22, bright=0.6, pos=-0.15), 0.0, 0.7)
    place(x, voice(A6, 0.9, tau=0.22, bright=0.55, pos=0.15), 0.06, 0.55)
    return master(hall(x, 1.1, 0.18), -22.0, 1.0)


def ui_complete() -> np.ndarray:
    """A challenge task ticked / Qibla aligned: one bright touch."""
    x = stereo_silence(0.8)
    place(x, voice(D6, 0.75, tau=0.19, bright=0.62), 0.0, 0.75)
    return master(hall(x, 1.0, 0.17), -23.0, 0.8)


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
        lufs = pyln.Meter(SR, block_size=min(0.4, dur * 0.9)).integrated_loudness(x)
        tp = 20 * np.log10(np.max(np.abs(resample_poly(x, 4, 1, axis=0))))
        print(f"{name:16s} {dur:4.2f} s  {lufs:6.1f} LUFS  true peak {tp:5.1f} dBTP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
