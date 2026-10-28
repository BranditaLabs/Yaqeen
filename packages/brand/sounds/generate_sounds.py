#!/usr/bin/env python3
"""
Yaqeen notification sounds — «أصوات السكينة».

Synthesised from scratch (physical models, no samples, no third-party audio): ours, reproducible,
licence-free — and halal by design:

  * No musical instruments, no bells, no melodies, no chords, no tuned tones. Every sound is a
    physical, natural event from the app's world: wudu water in a stone basin, drops, tasbih beads
    on their cord, a mushaf page turned right to left, pre-dawn air, a stone set down, amber beads.
  * Premium through realism and craft rather than music: physically modelled bubbles (Minnaert),
    inharmonic wood and stone modes that differ on every knock, fibre crackle in the page, a stone
    courtyard acoustic whose highs fade faster than its lows, stereo movement, and product-grade
    mastering (phone low-cut, gentle EQ/compression, matched loudness, −1 dBTP true peak).
  * Calm: nothing over 3 s; loudness by role (≈ −17 LUFS prayer … −22 LUFS store offers).
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


def master(x: np.ndarray, lufs: float, total: float) -> np.ndarray:
    n = n_of(total)
    x = x[:n] if len(x) >= n else np.concatenate([x, np.zeros((n - len(x), 2))])
    x = band(x, 110, None, 2)                # phone speakers can't play below this; keeps it clean
    x = biquad(x, "peak", 340, -2.0, 0.9)    # less box
    x = biquad(x, "peak", 3200, -1.0, 1.2)   # less edge
    x = biquad(x, "highshelf", 10_000, 1.5)  # air
    x = compress(x)
    x = np.tanh(x * 1.5) / np.tanh(1.5) if np.max(np.abs(x)) > 0 else x  # gentle warmth
    x -= np.mean(x, axis=0)
    x *= raised(n, n_of(0.002), n_of(min(0.3, total / 4)))[:, None]
    meter = pyln.Meter(SR, block_size=min(0.4, total * 0.9))
    x = pyln.normalize.loudness(x, meter.integrated_loudness(x), lufs)
    return limit(x)


# ----------------------------------------------------------------------------- natural sources
#   Physical models only. A water bubble or a wooden bead has a resonance, but nothing here is
#   tuned to a scale, layered into a chord, or sequenced into a tune.


def bubble(radius_mm: float, rise: float = 0.1, gain: float = 1.0) -> np.ndarray:
    """One air bubble ringing in water (Minnaert resonance, van den Doel's model): pitch rises
    as it reaches the surface; damping grows with frequency. Small radius = bright drop."""
    f0 = 3260.0 / radius_mm
    damp = 0.043 * f0 + 0.0014 * f0 ** 1.5
    sec = min(0.25, 7.0 / damp)
    t = t_axis(sec)
    f = f0 * (1 + rise * (1 - np.exp(-t * damp / 2.5)))  # `rise` = total climb, e.g. 0.6 = +60 %
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-damp * t)
    sig *= raised(len(t), n_of(0.0006), n_of(0.004))
    return sig * gain * (radius_mm ** 0.3)


def drop_into(radius_mm: float, pos: float = 0.0, gain: float = 1.0) -> np.ndarray:
    """A drop hitting still water: a tiny splash transient, then its strongly rising bubble."""
    b = bubble(radius_mm, rise=RNG.uniform(0.5, 0.85))
    splash = band(RNG.standard_normal(n_of(0.012)), 3000, 12_000, 2) * np.exp(-t_axis(0.012) / 0.0018) * 0.12
    out = np.zeros(max(len(b), len(splash)) + n_of(0.002))
    out[: len(splash)] += splash
    out[n_of(0.002) : n_of(0.002) + len(b)] += b
    return pan(out, pos) * gain


def stream(sec: float, rate: float, r_lo: float, r_hi: float, *, rise: float = 0.25, fill: float = 0.0,
           pan_from: float = 0.0, pan_to: float = 0.0, flow: float = 0.08, shape: np.ndarray | None = None) -> np.ndarray:
    """Running water: a Poisson cloud of bubbles over a soft flow noise. `fill` > 0 makes the
    bubbles shrink over time — the rising sound of a cup filling."""
    n = n_of(sec)
    out = np.zeros((n, 2))
    t = 0.0
    while t < sec:
        t += RNG.exponential(1 / rate)
        if t >= sec:
            break
        k = t / sec
        lo, hi = r_lo * (1 - fill * k), r_hi * (1 - fill * k)
        r = np.exp(RNG.uniform(np.log(lo), np.log(hi)))
        p = pan_from + (pan_to - pan_from) * k + RNG.uniform(-0.25, 0.25)
        b = pan(bubble(r, rise=rise * RNG.uniform(0.6, 1.4)), np.clip(p, -1, 1))
        w = 1.0 if shape is None else shape[min(len(shape) - 1, n_of(t))]
        place(out, b, t, RNG.uniform(0.25, 1.0) * w)
    rush = band(RNG.standard_normal((n, 2)), 300, 2600, 2) * flow
    env = raised(n, n_of(min(0.3, sec / 3)), n_of(min(0.5, sec / 2.5)))
    if shape is not None:
        env = env * shape[:n]
    return (out + rush) * env[:, None]


def wood(gain: float = 1.0, size: float = 1.0, pos: float = 0.0) -> np.ndarray:
    """An olive-wood tasbih bead knocking another: 8 inharmonic, heavily damped modes and a
    felt-soft contact. Every knock is a little different (no two beads are the same)."""
    sec = 0.09
    t = t_axis(sec)
    base = 1350 / size * RNG.uniform(0.93, 1.07)
    ratios = [1.0, 1.58, 2.31, 2.97, 3.82, 4.66, 5.71, 6.93]
    sig = np.zeros(len(t))
    for i, r in enumerate(ratios):
        d = 0.0065 / (1 + 0.6 * i) * RNG.uniform(0.8, 1.2)  # wood is heavily damped
        sig += (0.72 ** i) * RNG.uniform(0.6, 1.0) * np.exp(-t / d) * np.sin(2 * np.pi * base * r * t + RNG.uniform(0, 6.28))
    contact = band(RNG.standard_normal(len(t)), 1200, 7000, 2) * np.exp(-t / 0.0009) * 0.45
    body = band(RNG.standard_normal(len(t)), 300, 1600, 2) * np.exp(-t / 0.003) * 0.5
    sig = (sig + contact + body) * raised(len(t), n_of(0.0004), n_of(0.01))
    return pan(sig, pos) * gain


def bead_pair(at_gain: float = 1.0, pos: float = 0.0) -> np.ndarray:
    """Two beads meet: the main knock, then the softer second contact a few ms later."""
    out = np.zeros((n_of(0.12), 2))
    place(out, wood(1.0, pos=pos), 0.0)
    place(out, wood(0.38, size=1.05, pos=pos + 0.05), RNG.uniform(0.007, 0.013))
    return out * at_gain


def thread_slide(sec: float, pos_from: float, pos_to: float) -> np.ndarray:
    """The silk cord sliding through the bead: a short, soft friction."""
    n = n_of(sec)
    x = band(RNG.standard_normal(n), 2500, 8000, 2) * raised(n, n_of(sec * 0.4), n_of(sec * 0.5)) * 0.05
    p = np.linspace(pos_from, pos_to, n)
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def stone(gain: float = 1.0, pos: float = 0.0, size: float = 1.0) -> np.ndarray:
    """A smooth river stone set on a stone surface: denser, longer modes than wood."""
    sec = 0.22
    t = t_axis(sec)
    base = 2600 / size * RNG.uniform(0.95, 1.05)
    sig = np.zeros(len(t))
    for i, r in enumerate([1.0, 1.73, 2.41, 3.37, 4.12, 5.29, 6.6]):
        d = 0.011 / (1 + 0.6 * i)
        sig += (0.7 ** i) * np.exp(-t / d) * np.sin(2 * np.pi * base * r * t + RNG.uniform(0, 6.28))
    thud = band(RNG.standard_normal(len(t)), 120, 900, 2) * np.exp(-t / 0.006) * 0.8
    contact = band(RNG.standard_normal(len(t)), 2000, 10_000, 2) * np.exp(-t / 0.0007) * 0.35
    sig = (0.45 * sig + thud + contact) * raised(len(t), n_of(0.0004), n_of(0.03))
    return pan(sig, pos) * gain


def page_turn(sec: float = 0.7) -> np.ndarray:
    """A mushaf page turned right-to-left (the Arabic direction): fibres crackle as it lifts,
    air moves as it travels across, and it settles with a soft brush."""
    n = n_of(sec)
    t = np.arange(n) / SR
    k = t / sec
    # travel: right → left
    p = 0.55 - 1.1 * np.clip((k - 0.1) / 0.8, 0, 1)
    a = (p + 1) * np.pi / 4
    # fibre crackle: sparse micro-impulses, densest while the page bends
    crackle = np.zeros(n)
    density = np.sin(np.pi * np.clip(k / 0.75, 0, 1)) ** 1.5
    for i in np.nonzero(RNG.random(n) < density * 900 / SR)[0]:
        L = min(n - i, n_of(0.003))
        crackle[i : i + L] += RNG.uniform(-1, 1) * np.exp(-np.arange(L) / (SR * 0.0004))
    crackle = band(crackle, 2000, 7000, 2) * 0.16
    friction = band(RNG.standard_normal(n), 700, 3800, 2) * (np.sin(np.pi * np.clip(k / 0.85, 0, 1)) ** 2) * 0.05
    swoosh = band(RNG.standard_normal(n), 140, 800, 2) * (np.sin(np.pi * np.clip((k - 0.2) / 0.65, 0, 1)) ** 2) * 0.3
    settle = np.zeros(n)
    i0 = n_of(sec * 0.84)
    L = n - i0
    settle[i0:] = band(RNG.standard_normal(L), 300, 3000, 2) * np.exp(-np.arange(L) / (SR * 0.025)) * 0.25
    mono = band(crackle + friction + swoosh + settle, None, 8000, 2)
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def breeze(sec: float, lo: float, hi: float, gust_rate: float = 0.4, leaves: float = 0.0) -> np.ndarray:
    """Night air: band-limited wind with slow, irregular gusts; optional palm-frond rustle."""
    n = n_of(sec)
    mod = band(RNG.standard_normal(n), None, gust_rate * 3, 1)
    mod = 0.55 + 0.45 * (mod / (np.max(np.abs(mod)) + 1e-9))
    wind = band(RNG.standard_normal((n, 2)), lo, hi, 2) * mod[:, None]
    if leaves:
        rustle = np.zeros((n, 2))
        for i in np.nonzero(RNG.random(n) < (mod ** 3) * 2500 / SR)[0]:
            L = min(n - i, n_of(0.004))
            ch = RNG.integers(0, 2)
            rustle[i : i + L, ch] += RNG.uniform(-1, 1) * np.exp(-np.arange(L) / (SR * 0.0006))
        wind += band(rustle, 2000, 9000, 2) * leaves
    return wind * raised(n, n_of(sec * 0.35), n_of(sec * 0.4))[:, None]


def amber_pour(sec: float, count: int, spread: float) -> np.ndarray:
    """Amber beads poured onto a wooden tray: a bright cascade that thins out."""
    out = np.zeros((n_of(sec), 2))
    for i in range(count):
        at = spread * (RNG.random() ** 1.8)
        size = RNG.uniform(0.55, 0.85)
        place(out, wood(RNG.uniform(0.25, 0.8) * (1 - 0.6 * at / spread), size=size, pos=RNG.uniform(-0.7, 0.7)), at)
    return out


# ----------------------------------------------------------------------------- the family


def yq_prayer() -> np.ndarray:
    """Prayer time (alert «تنبيه»). «ماء الوضوء»: water running into a stone basin in a mosque
    courtyard — it starts, flows, and eases off."""
    sec = 3.0
    shape = raised(n_of(sec), n_of(0.25), n_of(1.2))
    x = stream(sec, 34, 1.2, 4.5, flow=0.05, pan_from=0.2, pan_to=-0.1, shape=shape)
    place(x, drop_into(2.2, 0.15), 2.15, 0.45)
    return master(hall(x, 1.8, 0.28), -17.0, 3.0)


def yq_prayer_soon() -> np.ndarray:
    """Before the prayer. «قطرات»: the first drops of wudu falling into the basin."""
    x = stereo_silence(2.0)
    for at, r, p, g in [(0.0, 2.4, 0.25, 0.9), (0.27, 1.9, -0.2, 0.75), (0.47, 2.8, 0.05, 0.85)]:
        place(x, drop_into(r, p), at, g)
    return master(hall(x, 1.3, 0.26), -18.5, 2.0)


def yq_azkar() -> np.ndarray:
    """Azkar & dhikr. «السبحة»: three beads drawn along the cord, right to left, then the hand
    rests."""
    x = stereo_silence(1.6)
    for at, p, g in [(0.0, 0.35, 0.8), (0.19, 0.05, 0.72), (0.36, -0.25, 1.0)]:
        place(x, thread_slide(0.12, p + 0.25, p), max(0.0, at - 0.08))
        place(x, bead_pair(1.0, p), at, g)
    return master(hall(x, 1.4, 0.24), -19.0, 1.6)


def yq_quran() -> np.ndarray:
    """Wird, khatma, al-Kahf on Friday. «الصفحة»: a mushaf page turned right to left."""
    x = stereo_silence(1.6)
    place(x, page_turn(0.75), 0.02)
    return master(hall(x, 1.3, 0.22), -19.0, 1.6)


def yq_hifz() -> np.ndarray:
    """Hifz review due. «قطرتان»: two drops in a stone well — what was kept, returning."""
    x = stereo_silence(2.2)
    place(x, drop_into(2.0, -0.2), 0.0, 1.0)
    place(x, drop_into(1.7, 0.25), 0.31, 0.8)
    return master(hall(x, 1.6, 0.3), -19.0, 2.2)


def yq_suhoor() -> np.ndarray:
    """Suhoor. «سَحَر»: pre-dawn air through palm fronds, and one drop in the dark."""
    x = breeze(2.8, 160, 1400, 0.5, leaves=0.25)
    place(x, drop_into(2.6, 0.3), 1.35, 0.45)
    return master(hall(x, 2.4, 0.32), -20.0, 2.8)


def yq_iftar() -> np.ndarray:
    """Iftar. «ماءٌ وتمرة»: water poured into a clay cup — you hear it fill — then the last drop."""
    sec = 2.4
    shape = raised(n_of(sec), n_of(0.08), n_of(0.5))
    shape[n_of(1.7):] *= np.linspace(1, 0, n_of(sec) - n_of(1.7)) ** 2
    x = stream(sec, 120, 1.8, 5.5, rise=0.08, fill=0.6, flow=0.07, shape=shape)
    place(x, drop_into(1.5, -0.15), 2.0, 0.55)
    return master(hall(x, 1.3, 0.22), -18.5, 2.4)


def yq_challenge() -> np.ndarray:
    """Challenge, streaks, a reward is ready. «حبات الكهرمان»: a handful of amber beads poured
    onto a wooden tray — something gathered, counted, kept."""
    x = amber_pour(1.4, 38, 0.65)
    return master(hall(x, 1.6, 0.26), -18.5, 1.4)


def yq_offers() -> np.ndarray:
    """Store offers (consented). «حصاة»: one smooth stone set down — the quietest sound in the set."""
    x = stereo_silence(0.9)
    place(x, stone(1.0, 0.0), 0.0)
    place(x, stone(0.18, 0.1, size=1.1), 0.075)
    return master(hall(x, 0.8, 0.16), -22.0, 0.9)


# In-app UI sounds


def ui_bead() -> np.ndarray:
    """One azkar count («صوت نقرة خفيف»): one bead, crisp enough for 10 taps a second."""
    x = stereo_silence(0.12)
    place(x, bead_pair(1.0, 0.0), 0.0)
    return master(x, -24.0, 0.12)


def ui_bead_round() -> np.ndarray:
    """A completed round («تقبّل الله»): the beads gathered together in the palm."""
    x = amber_pour(0.8, 12, 0.18)
    return master(hall(x, 1.0, 0.2), -22.0, 0.8)


def ui_complete() -> np.ndarray:
    """A challenge task ticked / Qibla aligned: one clear drop."""
    x = stereo_silence(0.9)
    place(x, drop_into(1.6, 0.0), 0.0)
    return master(hall(x, 1.0, 0.22), -23.0, 0.9)


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
