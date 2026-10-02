"""生成 Pactick 宣传短片的原创电子配乐；仅依赖 Python 与 numpy。"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import wave

import numpy as np


SAMPLE_RATE = 48_000
BPM = 120
BEAT = 60 / BPM
CHAPTERS = (0, 8, 16, 24, 34, 42, 50, 56, 60)


def hz(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def envelope(length: int, attack: float, release: float) -> np.ndarray:
    env = np.ones(length, dtype=np.float64)
    a = min(length, max(2, round(attack * SAMPLE_RATE)))
    r = min(length, max(2, round(release * SAMPLE_RATE)))
    env[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    env[-r:] *= np.sin(np.linspace(np.pi / 2, 0, r)) ** 2
    return env


def pluck(note: float, length: float = 1.0) -> np.ndarray:
    t = np.arange(round(length * SAMPLE_RATE)) / SAMPLE_RATE
    f = hz(note)
    signal = (
        np.sin(2 * np.pi * f * t)
        + 0.30 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 7)
        + 0.12 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t * 11)
    )
    return signal * np.exp(-t * 4.7) * envelope(len(t), 0.005, 0.10)


def bass(note: float, length: float) -> np.ndarray:
    t = np.arange(round(length * SAMPLE_RATE)) / SAMPLE_RATE
    f = hz(note)
    signal = np.sin(2 * np.pi * f * t) + 0.17 * np.sin(2 * np.pi * 2 * f * t)
    return signal * np.exp(-t * 1.8) * envelope(len(t), 0.018, 0.09)


def pad(notes: tuple[int, ...], length: float) -> np.ndarray:
    t = np.arange(round(length * SAMPLE_RATE)) / SAMPLE_RATE
    signal = np.zeros(len(t))
    for i, note in enumerate(notes):
        f = hz(note)
        signal += (
            np.sin(2 * np.pi * f * t + i * 0.3)
            + 0.17 * np.sin(2 * np.pi * f * 2 * t)
            + 0.15 * np.sin(2 * np.pi * f * 1.0015 * t + 0.6)
        )
    signal /= len(notes)
    return signal * envelope(len(t), 0.32, 0.70)


def kick() -> np.ndarray:
    t = np.arange(round(0.38 * SAMPLE_RATE)) / SAMPLE_RATE
    phase = 2 * np.pi * (46 * t + (115 - 46) * 0.021 * (1 - np.exp(-t / 0.021)))
    body = np.sin(phase) * np.exp(-t * 11)
    return body * envelope(len(t), 0.0015, 0.025)


def noise_hit(rng: np.random.Generator, length: float, decay: float, bright: bool) -> np.ndarray:
    t = np.arange(round(length * SAMPLE_RATE)) / SAMPLE_RATE
    noise = rng.normal(0, 1, len(t))
    if bright:
        noise = np.concatenate(([0], np.diff(noise))) * 0.45
    else:
        noise = (noise + np.roll(noise, 1) + np.roll(noise, 2)) / 3
    return noise * np.exp(-t * decay) * envelope(len(t), 0.001, 0.025)


def ui_click(note: float, length: float = 0.12) -> np.ndarray:
    t = np.arange(round(length * SAMPLE_RATE)) / SAMPLE_RATE
    signal = np.sin(2 * np.pi * hz(note) * t) + 0.20 * np.sin(2 * np.pi * hz(note) * 2 * t)
    return signal * np.exp(-t * 42) * envelope(len(t), 0.0015, 0.018)


def transition(rng: np.random.Generator) -> np.ndarray:
    length = round(0.50 * SAMPLE_RATE)
    t = np.arange(length) / SAMPLE_RATE
    raw = rng.normal(0, 1, length)
    spectrum = np.fft.rfft(raw)
    frequency = np.fft.rfftfreq(length, 1 / SAMPLE_RATE)
    spectrum *= np.exp(-((frequency - 1800) / 1600) ** 2)
    noise = np.fft.irfft(spectrum, n=length)
    signal = noise * np.sin(np.pi * t / 0.50) ** 2
    return signal * envelope(length, 0.03, 0.06)


def synthesize(duration: float) -> np.ndarray:
    samples = round(duration * SAMPLE_RATE)
    mix = np.zeros((samples, 2), dtype=np.float64)
    rng = np.random.default_rng(20261002)
    boundaries = np.array(CHAPTERS, dtype=float) * duration / 60
    ending = boundaries[-2]

    def put(signal: np.ndarray, start: float, level: float, pan: float = 0, echo: bool = False) -> None:
        offset = round(start * SAMPLE_RATE)
        if offset >= samples or offset + len(signal) <= 0:
            return
        skip = max(0, -offset)
        offset = max(0, offset)
        count = min(len(signal) - skip, samples - offset)
        gains = np.array([math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)])
        mix[offset : offset + count] += signal[skip : skip + count, None] * (level * gains)
        if echo:
            put(signal, start + BEAT * 0.75, level * 0.18, -pan)
            put(signal, start + BEAT * 1.50, level * 0.07, pan)

    # F 大调的四和弦音序，每四秒换和弦，章节切换保留同一拍速。
    chords = ((53, 57, 60, 64, 67), (50, 53, 57, 60, 64), (58, 62, 65, 69, 72), (48, 55, 60, 64, 67))
    roots = (41, 38, 46, 36)
    motif = (0, 2, 4, 2, 1, 2, 3, 1)

    for bar, start in enumerate(np.arange(0, ending, 4.0)):
        chord = chords[bar % 4]
        chapter = int(np.searchsorted(boundaries, start, side="right") - 1)
        put(pad(chord, 4.8), float(start), 0.14 if chapter != 3 else 0.18, -0.18)
        put(pad(tuple(n + 12 for n in chord[:3]), 4.8), float(start) + 0.025, 0.045, 0.30)

    for beat_index, start in enumerate(np.arange(0, ending, BEAT)):
        chapter = int(np.searchsorted(boundaries, start, side="right") - 1)
        chord_index = int(start // 4) % 4
        local_beat = beat_index % 4
        groove = chapter in (1, 2, 4, 6)
        if groove or (chapter in (3, 5) and local_beat in (0, 2)) or (chapter == 0 and beat_index % 4 == 0 and start >= 2):
            put(kick(), float(start), 0.42 if groove else 0.27)
        if groove and local_beat in (1, 3):
            put(noise_hit(rng, 0.19, 24, False), float(start), 0.075, 0.08)
            put(ui_click(79, 0.075), float(start), 0.025, -0.1)
        if chapter != 0 and (groove or local_beat in (0, 2)):
            put(noise_hit(rng, 0.09, 55, True), float(start), 0.033, -0.27)
        if chapter in (2, 4, 6):
            put(noise_hit(rng, 0.07, 65, True), float(start) + BEAT / 2, 0.024, 0.34)
        if chapter >= 1 and (local_beat == 0 or (groove and local_beat == 2)):
            put(bass(roots[chord_index], 0.72), float(start), 0.19 if groove else 0.12)

        melody_active = (chapter == 0 and beat_index % 4 in (1, 3)) or (chapter in (1, 2, 4, 6) and local_beat != 3) or (chapter in (3, 5) and local_beat in (1, 2))
        if melody_active:
            chord = chords[chord_index]
            note = chord[motif[beat_index % len(motif)]] + 12
            put(pluck(note, 1.35), float(start), 0.135 if chapter in (2, 4, 6) else 0.105, (-0.28, 0.2, 0.05)[beat_index % 3], True)
            if chapter in (2, 6) and local_beat == 2:
                put(pluck(chord[2] + 12, 0.80), float(start) + BEAT / 2, 0.065, 0.40, True)

    for chapter, start in enumerate(boundaries[:-1]):
        put(ui_click(84 if chapter % 2 == 0 else 79), float(start), 0.07, 0.1)
        if chapter:
            put(transition(rng), float(start) - 0.32, 0.06, -0.08)
            put(pluck(77, 0.6), float(start) + 0.125, 0.055, 0.3)

    # 末章停止循环，依次落到 F 大调和弦；总线淡出使最后一个采样归零。
    coda_length = max(0.01, duration - ending)
    put(kick(), float(ending), 0.30)
    put(bass(41, min(1.8, coda_length)), float(ending), 0.20)
    put(pad((53, 57, 60, 64, 67), coda_length), float(ending), 0.22)
    for offset, note in ((0, 81), (0.5, 79), (1, 76), (1.5, 72), (2, 69), (2.5, 65)):
        if offset < coda_length - 0.15:
            put(pluck(note, min(1.6, coda_length - offset)), float(ending) + offset, 0.115, 0.1 if offset % 1 else -0.15, True)

    mix *= envelope(samples, min(0.04, duration / 8), min(1.0, duration / 8))[:, None]
    peak = float(np.max(np.abs(mix)))
    if peak > 0:
        mix *= 10 ** (-1.2 / 20) / peak
    return mix


def main() -> None:
    parser = argparse.ArgumentParser(description="以 120 BPM 生成原创的 Pactick 电子配乐。")
    parser.add_argument("--output", type=Path, default=Path("output/pactick-promo-swiss/soundtrack.wav"))
    parser.add_argument("--duration", type=float, default=60.0, help="秒数，默认 60；章节比例随时长调整，拍速保持 120 BPM。")
    args = parser.parse_args()
    if not math.isfinite(args.duration) or args.duration < 1 or args.duration > 600:
        parser.error("--duration 必须是 1 至 600 之间的有限数值。")

    signal = synthesize(args.duration)
    pcm = np.rint(np.clip(signal, -1, 1) * 32767).astype("<i2")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(pcm.tobytes())
    measured = pcm.astype(np.float64) / 32768
    peak = float(np.max(np.abs(measured)))
    rms = float(np.sqrt(np.mean(measured ** 2)))
    print(f"{args.output.resolve()}")
    print(f"48 kHz stereo, {len(pcm)} frames, {len(pcm) / SAMPLE_RATE:.3f} s, 120 BPM")
    print(f"peak={20 * math.log10(peak):.2f} dBFS; RMS={20 * math.log10(rms):.2f} dBFS")


if __name__ == "__main__":
    main()
