#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات يقين»: the logo, as sound.

The mark is an abstracted «ن» — two navy wings and a gold diamond — and the splash animates it:
the wings spread, the diamond settles, a glint crosses. Every sound performs that same gesture:

  * «الجناحان» the wings: a warm resonance coloured like the ghunnah of «ن» (nasal murmur, closed-
    mouth anti-resonance), starting as one point in the centre and opening to full stereo width.
  * «الماسة» the diamond: a crystal point in the centre (harmonic partials only, never a bell) that
    strikes D and lifts a neutral third (350 cents) — an Arabic-mode colour, not a Western chord,
    and the part no other app sounds like.
  * «اللمعة» the glint: a thin shimmer crossing right → left, the Arabic reading direction.

Each sound is the gesture, part of it, or reversed. Owner's halal line: soft tones are fine; no
instrument timbres, no bells, no melodies — three tones at most. Synthesised from scratch (no
samples, no licences), warm hall + subtle ping-pong echo, mastered to matched loudness
(≈ −17 LUFS prayer … −22 LUFS offers, true peak ≤ −1 dBTP), all under 3 s. On a mono phone
speaker the timbre and gesture remain; on headphones and stereo iPhones the wings open.
The adhan itself is NOT generated — it stays a licensed human recording (spec §10).

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


# ----------------------------------------------------------------------------- the logo, as sound
#   The mark is an abstracted «ن»: two navy wings and a gold diamond. The splash animates it —
#   wings spread, the diamond settles, a glint crosses. Every Yaqeen sound performs the same gesture.

NEUTRAL_THIRD = 2 ** (350 / 1200)  # between minor and major: the colour of Arabic modes, not a Western chord
D3, D4, D5, D6 = 146.83, 293.66, 587.33, 1174.66
N4, N5, N6 = D4 * NEUTRAL_THIRD, D5 * NEUTRAL_THIRD, D6 * NEUTRAL_THIRD  # the diamond's lift


def _nun_formant(f: np.ndarray) -> np.ndarray:
    """Spectral envelope of a held «ن» (ghunnah): strong nasal murmur near 250 Hz, an anti-resonance
    around 1 kHz (the closed mouth), soft nasal formants near 2.2 and 3 kHz."""
    g = lambda c, w: np.exp(-0.5 * ((f - c) / w) ** 2)
    env = 1.0 * g(260, 90) + 0.32 * g(2250, 260) + 0.18 * g(3000, 320) + 0.06
    env *= 1 - 0.85 * g(1050, 230)
    return env


def wings(f0: float, sec: float, *, open_at: float = 0.05, open_for: float = 0.9, attack: float = 0.18,
          tau: float = 1.2, gain: float = 1.0, air: float = 0.25) -> np.ndarray:
    """«الجناحان»: a warm ghunnah-coloured resonance on f0 that starts as one point in the centre and
    opens out to full stereo width — the wings spreading. Additive harmonics shaped by the «ن»
    envelope, a slow living vibrato, and breath through the same formants."""
    t = t_axis(sec)
    n = len(t)
    vib = 1 + (7 / 1200) * np.log(2) * np.sin(2 * np.pi * 4.6 * t) * raised(n, n_of(0.5), 0)
    sides = []
    phases = RNG.uniform(0, 2 * np.pi, 40)  # shared by both sides → the wings never cancel on a mono speaker
    for detune in (-2.0, 2.0):
        r = 2 ** (detune / 1200)
        sig = np.zeros(n)
        for k in range(1, 40):
            fk = f0 * k * r
            if fk > 5000:
                break
            amp = _nun_formant(np.array([fk]))[0] / k ** 0.75
            sig += amp * np.sin(2 * np.pi * np.cumsum(fk * vib) / SR + phases[k])
        noise = RNG.standard_normal(n)
        spec = np.fft.rfft(noise)
        spec *= _nun_formant(np.fft.rfftfreq(n, 1 / SR))
        sig += air * np.fft.irfft(spec, n) * 1.2
        sides.append(sig)
    a, b = sides
    mid, side = (a + b) / 2, (a - b) / 2
    k = np.clip((t - open_at) / open_for, 0, 1)
    w = 0.5 - 0.5 * np.cos(np.pi * k)  # 0 = a single point, 1 = wings fully open
    env = raised(n, n_of(attack), n_of(min(0.4, sec / 2.5))) * np.exp(-np.maximum(0, t - attack) / tau)
    out = np.stack([mid + w * side, mid - w * side], axis=1) * env[:, None]
    return out / (np.max(np.abs(out)) + 1e-9) * gain


def diamond(f: float, sec: float = 1.2, *, vel: float = 1.0, tau: float = 0.45, pos: float = 0.0) -> np.ndarray:
    """«الماسة»: a crystal point in the centre — the signature voice, narrow and clear."""
    return voice(f, sec, vel=vel, tau=tau, bright=0.7, attack=0.004, air=0.08, warmth=0.08, width=0.06, pos=pos)


def glint(sec: float = 0.5, *, gain: float = 1.0, direction: float = -1.0) -> np.ndarray:
    """«اللمعة»: a thin shimmer that crosses the sound right → left, like light over the mark."""
    t = t_axis(sec)
    n = len(t)
    out = np.zeros((n, 2))
    for i in range(6):
        f_start = RNG.uniform(5200, 6800)
        f = f_start * (1 + 0.35 * t / sec)
        s = np.sin(2 * np.pi * np.cumsum(f) / SR + RNG.uniform(0, 6.28))
        out += pan(s, 0) * RNG.uniform(0.5, 1.0)
    p = np.clip(-direction * 0.8 + direction * 1.6 * (t / sec), -1, 1)
    a = (p + 1) * np.pi / 4
    mono = out[:, 0] * np.sin(np.pi * np.clip(t / sec, 0, 1)) ** 2
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1) * gain / 6


# ----------------------------------------------------------------------------- the family
#   Signature: wings open on D, the diamond strikes D and lifts a neutral third, the glint crosses.
#   Each sound is that gesture, a part of it, or it reversed. Never more than three tones.


def yq_prayer() -> np.ndarray:
    """Prayer time (alert «تنبيه»): the whole mark — wings open, diamond strikes and lifts, glint."""
    x = stereo_silence(2.9)
    place(x, wings(D3, 2.8, open_at=0.05, open_for=1.0, tau=1.4), 0.0, 0.5)
    place(x, diamond(D5, 2.2, tau=0.55), 0.32, 0.75)
    place(x, diamond(N5, 2.0, tau=0.6), 0.5, 0.65)
    place(x, glint(0.55), 0.78, 0.05)
    return master(hall(echo(x, 0.08), 2.0, 0.24), -17.0, 2.9)


def yq_prayer_soon() -> np.ndarray:
    """Before the prayer: the wings begin to open, one diamond strike — an invitation."""
    x = stereo_silence(1.9)
    place(x, wings(D3, 1.8, open_at=0.0, open_for=0.8, tau=0.9, attack=0.12), 0.0, 0.42)
    place(x, diamond(D5, 1.5, tau=0.5), 0.24, 0.75)
    return master(hall(echo(x, 0.07), 1.7, 0.22), -18.5, 1.9)


def yq_azkar() -> np.ndarray:
    """Azkar & dhikr: three diamond counts that move out from the centre, right to left — the
    count spreading like the wings."""
    x = stereo_silence(1.6)
    for at, p, v in [(0.0, 0.0, 0.62), (0.17, 0.35, 0.6), (0.34, -0.35, 0.82)]:
        place(x, diamond(D5, 1.1, tau=0.2, pos=p), at, v)
    place(x, wings(D3, 1.2, open_at=0.3, open_for=0.6, tau=0.5, attack=0.1), 0.32, 0.22)
    return master(hall(x, 1.5, 0.22), -18.5, 1.6)


def yq_quran() -> np.ndarray:
    """Wird, khatma, al-Kahf: the ghunnah alone, low and slow — the wings opening like breath
    before recitation, the diamond only a soft light at the end."""
    x = stereo_silence(2.5)
    place(x, wings(D3, 2.4, open_at=0.1, open_for=1.4, attack=0.35, tau=1.6, air=0.18), 0.0, 0.8)
    place(x, diamond(D4, 1.6, tau=0.6), 0.75, 0.38)
    return master(hall(x, 2.0, 0.24), -18.5, 2.5)


def yq_hifz() -> np.ndarray:
    """Hifz review: the diamond's lift reversed (high → home) as the wings fold in — what was
    kept, returning."""
    x = stereo_silence(1.9)
    place(x, diamond(N5, 1.5, tau=0.45, pos=0.2), 0.0, 0.68)
    place(x, diamond(D5, 1.6, tau=0.55, pos=-0.1), 0.18, 0.75)
    folding = wings(D3, 1.6, open_at=0.0, open_for=0.01, tau=0.8, attack=0.08)
    w = np.linspace(1, 0.15, len(folding))[:, None]
    mid = folding.mean(axis=1, keepdims=True)
    place(x, mid + (folding - mid) * w, 0.12, 0.35)
    return master(hall(echo(x, 0.07), 1.6, 0.22), -18.5, 1.9)


def yq_suhoor() -> np.ndarray:
    """Suhoor: dark, wide wings out of the night, and a far glint like the last star."""
    x = stereo_silence(2.7)
    place(x, wings(D3, 2.6, open_at=0.2, open_for=1.6, attack=0.5, tau=1.8, air=0.2), 0.0, 0.85)
    place(x, diamond(N5, 1.4, vel=0.6, tau=0.5, pos=0.3), 1.2, 0.22)
    place(x, glint(0.7, direction=1.0), 1.25, 0.03)
    return master(hall(x, 2.4, 0.3), -19.5, 2.7)


def yq_iftar() -> np.ndarray:
    """Iftar: the wings open quickly and the diamond climbs home, lift, octave — release."""
    x = stereo_silence(2.3)
    place(x, wings(D3, 2.2, open_at=0.0, open_for=0.45, attack=0.08, tau=1.1), 0.0, 0.45)
    for i, (f, v) in enumerate([(D5, 0.7), (N5, 0.62), (D6, 0.5)]):
        place(x, diamond(f, 1.8 - 0.2 * i, tau=0.55 - 0.05 * i, pos=(-0.2, 0.0, 0.2)[i]), 0.16 + 0.085 * i, v)
    place(x, glint(0.5), 0.45, 0.04)
    return master(hall(echo(x, 0.08), 1.8, 0.24), -18.0, 2.3)


def yq_challenge() -> np.ndarray:
    """Challenge, streaks, a reward is ready: the gold first — glint, then the diamond's lift an
    octave up, quick and bright."""
    x = stereo_silence(1.7)
    place(x, glint(0.35), 0.0, 0.06)
    place(x, diamond(D6, 1.3, tau=0.35, pos=-0.15), 0.12, 0.62)
    place(x, diamond(N6, 1.3, tau=0.4, pos=0.15), 0.19, 0.6)
    place(x, wings(D4, 1.3, open_at=0.12, open_for=0.4, attack=0.06, tau=0.6), 0.1, 0.25)
    return master(hall(echo(x, 0.1), 1.6, 0.24), -18.0, 1.7)


def yq_offers() -> np.ndarray:
    """Store offers (consented): the diamond alone, muted, closed wings — the quietest sound."""
    x = stereo_silence(1.0)
    place(x, voice(N5, 0.95, tau=0.28, bright=0.45, air=0.05, width=0.05), 0.0, 0.8)
    return master(hall(x, 1.1, 0.18), -22.0, 1.0)


# In-app UI sounds


def ui_bead() -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): a pinpoint of the diamond, fine at 10 taps a second."""
    x = stereo_silence(0.09)
    place(x, voice(D6, 0.09, tau=0.02, bright=0.45, attack=0.0015, air=0.05, warmth=0, width=0.05), 0.0)
    return master(x, -25.0, 0.09)


def ui_bead_round() -> np.ndarray:
    """A completed round («تقبّل الله»): the diamond's lift in miniature as the wings open."""
    x = stereo_silence(1.1)
    place(x, wings(D4, 1.0, open_at=0.0, open_for=0.4, attack=0.05, tau=0.5), 0.0, 0.3)
    place(x, diamond(D6, 0.9, tau=0.3), 0.03, 0.6)
    place(x, diamond(N6, 0.9, tau=0.3), 0.1, 0.5)
    return master(hall(x, 1.2, 0.2), -22.0, 1.1)


def ui_complete() -> np.ndarray:
    """A task ticked / Qibla aligned: one glint across one diamond."""
    x = stereo_silence(0.8)
    place(x, diamond(N6, 0.75, tau=0.25), 0.0, 0.7)
    place(x, glint(0.3), 0.04, 0.04)
    return master(hall(x, 1.0, 0.2), -23.0, 0.8)


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
