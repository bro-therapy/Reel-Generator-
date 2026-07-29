#!/usr/bin/env python3
"""Synthesise the placeholder sound set from guide §14.

    ./tools/make_placeholder_audio.py

Writes 16-bit WAVs to assets/audio/{sfx,music}/ and a manifest to
docs/generated/audio_slots.json.

Why synthesised rather than silent
----------------------------------
Guide §14 allows "silent or synthesised placeholders". Silence is cheaper and
much worse: you cannot tell a missing hook from a working one, you cannot mix,
and you cannot feel whether a hit lands. Every sound here is generated from
scratch with numpy — no samples, no downloads, nothing licensed — so the first
playtest has something to listen to and every slot is provably wired.

These are placeholders and they sound like placeholders. The point is that the
*slots* are real: drop a finished file over the same filename, reimport, and
nothing in the game changes. Slot names come straight from the guide's SFX
families so a real audio pass has an unambiguous shopping list.

Nothing here is a musical judgement worth defending. The synthesis choices are
just the cheapest way to make each family distinguishable by ear:
bells get inharmonic partials because that is what makes a bell sound like a
bell, plucked strings get Karplus-Strong, impacts get noise with a fast decay.
"""

from __future__ import annotations

import json
import struct
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
MUSIC_DIR = ROOT / "assets" / "audio" / "music"
MANIFEST = ROOT / "docs" / "generated" / "audio_slots.json"

RATE = 44100
rng = np.random.default_rng(20260729)  # fixed, so a rebuild is byte-identical


# ------------------------------------------------------------------ primitives

def t(seconds: float) -> np.ndarray:
    return np.linspace(0.0, seconds, int(RATE * seconds), endpoint=False)


def env(n: int, attack: float, decay: float, curve: float = 2.0) -> np.ndarray:
    """Attack-decay envelope. `curve` above 1 makes the tail snappier."""
    a = max(1, int(n * attack))
    d = max(1, n - a)
    return np.concatenate([
        np.linspace(0.0, 1.0, a),
        (1.0 - np.linspace(0.0, 1.0, d)) ** curve,
    ])[:n]


def noise(seconds: float) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, int(RATE * seconds))


def lowpass(x: np.ndarray, cutoff: float, poles: int = 4) -> np.ndarray:
    """Cascaded one-pole lowpass, `poles` stages deep.

    One pole rolls off at 6 dB/octave, which is far too gentle to be worth
    calling a filter: at one pole a growl "lowpassed" to 420 Hz still had its
    spectral centre of mass at 5.2 kHz, and a slam meant to be felt in the chest
    sat at 2.5 kHz. Four stages give 24 dB/octave and the sounds land where their
    description says they should.
    """
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    out = x
    for _ in range(max(1, poles)):
        acc = 0.0
        stage = np.empty_like(out)
        for i in range(out.size):
            acc = (1.0 - a) * out[i] + a * acc
            stage[i] = acc
        out = stage
    # Each stage loses amplitude; restore it so callers can reason about level.
    peak = float(np.max(np.abs(out)))
    src = float(np.max(np.abs(x)))
    return out * (src / peak) if peak > 1e-9 else out


def highpass(x: np.ndarray, cutoff: float, poles: int = 4) -> np.ndarray:
    return x - lowpass(x, cutoff, poles)


def sweep(seconds: float, f0: float, f1: float, shape: str = "sine") -> np.ndarray:
    """Frequency sweep. Phase is integrated so there are no discontinuities."""
    tt = t(seconds)
    freq = np.linspace(f0, f1, tt.size)
    phase = 2.0 * np.pi * np.cumsum(freq) / RATE
    if shape == "saw":
        return 2.0 * ((phase / (2.0 * np.pi)) % 1.0) - 1.0
    if shape == "square":
        return np.sign(np.sin(phase))
    return np.sin(phase)


def bell(seconds: float, base: float, gain: float = 1.0) -> np.ndarray:
    """Inharmonic partials with per-partial decay.

    A bell is not a harmonic series — the stretched, slightly detuned ratios are
    the whole reason it reads as a bell rather than an organ.
    """
    ratios = [1.0, 2.02, 2.99, 4.12, 5.43, 6.79, 8.21]
    decays = [1.0, 0.82, 0.66, 0.5, 0.38, 0.28, 0.2]
    tt = t(seconds)
    out = np.zeros_like(tt)
    for r, d in zip(ratios, decays):
        out += (np.sin(2.0 * np.pi * base * r * tt)
                * np.exp(-tt / (seconds * d * 0.42)) / r)
    return out * gain


def pluck(seconds: float, freq: float, damping: float = 0.996) -> np.ndarray:
    """Karplus-Strong. A noise burst in a delay line, averaged as it recirculates."""
    n = int(RATE * seconds)
    length = max(2, int(RATE / freq))
    buf = rng.uniform(-1.0, 1.0, length)
    out = np.empty(n)
    for i in range(n):
        out[i] = buf[i % length]
        nxt = (i + 1) % length
        buf[i % length] = damping * 0.5 * (buf[i % length] + buf[nxt])
    return out


def normalise(x: np.ndarray, peak: float = 0.86) -> np.ndarray:
    m = float(np.max(np.abs(x)))
    return x * (peak / m) if m > 1e-9 else x


def pad_to(x: np.ndarray, seconds: float) -> np.ndarray:
    n = int(RATE * seconds)
    return np.pad(x, (0, max(0, n - x.size)))[:n]


def mix(*layers: np.ndarray) -> np.ndarray:
    n = max(layer.size for layer in layers)
    out = np.zeros(n)
    for layer in layers:
        out[:layer.size] += layer
    return out


def write(path: Path, samples: np.ndarray, stereo: bool = False) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = normalise(samples)
    pcm = np.clip(data, -1.0, 1.0)
    ints = (pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        if stereo:
            w.writeframes(np.repeat(ints, 2).tobytes())
        else:
            w.writeframes(ints.tobytes())
    return path.stat().st_size


# ------------------------------------------------------------------- roster

ENEMY_DIR = ROOT / "data" / "enemies"


def enemy_species() -> list[tuple[str, float]]:
    """Every enemy id in data/enemies/, with a base pitch.

    Read from the resources rather than listed here so a slot cannot exist for an
    enemy that does not, or — the bug this replaced — an enemy exist with no slot
    of its own. `*_frames.tres` are SpriteFrames, not enemy data, so they are
    skipped.

    The pitch is derived from the id rather than chosen per enemy: it only has to
    make the species tell apart by ear, and a hash keeps that stable across runs
    without a table to maintain.
    """
    ids: list[str] = []
    if ENEMY_DIR.is_dir():
        for path in sorted(ENEMY_DIR.glob("*.tres")):
            if path.stem.endswith("_frames"):
                continue
            for line in path.read_text().splitlines():
                if line.startswith("id = &"):
                    ids.append(line.split('"')[1])
                    break
    if not ids:
        raise SystemExit(
            "no enemy ids found in %s — cannot name the enemy sound slots" % ENEMY_DIR)

    # Spread the species over two and a half octaves, biggest-sounding lowest, so
    # a brute and a mite are never confusable.
    out = []
    for i, eid in enumerate(ids):
        out.append((eid, 140.0 * (1.18 ** i)))
    return out


# ----------------------------------------------------------------------- sfx

def sfx_bank() -> dict:
    """One entry per slot in guide §14's SFX families.

    `bus` and `priority` matter more than the waveform: they are what the mixer
    reads, and priority is the guide's mix order, where 1 must always be audible.
    """
    b = {}

    def add(name, samples, bus, priority, note):
        b[name] = {"samples": samples, "bus": bus, "priority": priority, "note": note}

    # --- Hero -----------------------------------------------------------------
    add("hero_step", pad_to(highpass(noise(0.09), 900) * env(int(RATE * 0.09), 0.02, 0.98, 3.0), 0.12),
        "sfx", 6, "Footfall. Band-limited noise, short.")
    add("hero_dash", pad_to(mix(
            lowpass(noise(0.28), 2600) * env(int(RATE * 0.28), 0.06, 0.94, 1.6),
            sweep(0.28, 180, 620) * env(int(RATE * 0.28), 0.05, 0.95) * 0.35), 0.32),
        "sfx", 5, "Whoosh. Noise body plus a rising tone so it reads as motion, not wind.")
    add("hero_hurt", pad_to(mix(
            sweep(0.34, 420, 110, "saw") * env(int(RATE * 0.34), 0.01, 0.99, 1.4),
            highpass(noise(0.14), 1800) * env(int(RATE * 0.14), 0.005, 0.995, 2.5) * 0.5), 0.4),
        "sfx", 1, "Player damage. Priority 1 — must be audible through everything.")
    add("hero_low_health", pad_to(mix(
            bell(1.1, 196.0, 0.7),
            sweep(1.1, 88, 84) * env(int(RATE * 1.1), 0.1, 0.9) * 0.4), 1.2),
        "sfx", 1, "Damage warning loop. Also priority 1.")
    add("staff_shot", pad_to(mix(
            sweep(0.16, 1500, 520) * env(int(RATE * 0.16), 0.01, 0.99, 2.2),
            highpass(noise(0.05), 3200) * env(int(RATE * 0.05), 0.004, 0.996, 3.0) * 0.4), 0.2),
        "sfx", 5, "Focus Weapon. Descending chirp with a transient click.")
    add("staff_impact", pad_to(mix(
            lowpass(noise(0.12), 1400) * env(int(RATE * 0.12), 0.004, 0.996, 2.6),
            sweep(0.12, 700, 240) * env(int(RATE * 0.12), 0.004, 0.996) * 0.5), 0.16),
        "sfx", 5, "Hit confirm.")
    add("rally_mark", pad_to(mix(bell(0.7, 587.33, 0.8), bell(0.7, 880.0, 0.4)), 0.8),
        "sfx", 3, "Rally target marked. Bright, friendly interval.")
    add("convergence_start", pad_to(mix(
            sweep(0.9, 220, 1320) * env(int(RATE * 0.9), 0.25, 0.75, 0.8),
            bell(0.9, 440.0, 0.6), bell(0.9, 659.25, 0.45)), 1.0),
        "sfx", 3, "Convergence trigger. Rising, chordal.")
    add("convergence_end", pad_to(mix(
            sweep(0.6, 880, 220) * env(int(RATE * 0.6), 0.05, 0.95),
            bell(0.6, 329.63, 0.5)), 0.7),
        "sfx", 3, "Convergence over. The start, inverted.")

    # --- Summons: each species gets its own timbre family ----------------------
    add("rune_hound_growl", pad_to(lowpass(noise(0.5), 420)
            * (0.6 + 0.4 * np.sin(2 * np.pi * 22 * t(0.5)))
            * env(int(RATE * 0.5), 0.15, 0.85, 1.2), 0.55),
        "sfx", 4, "Low noise with amplitude modulation — a growl is a rough low sound.")
    add("rune_hound_lunge", pad_to(sweep(0.22, 260, 700, "saw")
            * env(int(RATE * 0.22), 0.04, 0.96, 1.5), 0.26),
        "sfx", 4, "Rising saw.")
    add("rune_hound_bite", pad_to(mix(
            highpass(noise(0.07), 2400) * env(int(RATE * 0.07), 0.003, 0.997, 3.5),
            sweep(0.07, 500, 160) * env(int(RATE * 0.07), 0.003, 0.997) * 0.6), 0.1),
        "sfx", 4, "Sharp snap.")
    add("rune_hound_crescent", pad_to(mix(
            sweep(0.3, 900, 380) * env(int(RATE * 0.3), 0.02, 0.98, 1.8),
            highpass(noise(0.3), 2000) * env(int(RATE * 0.3), 0.02, 0.98, 2.0) * 0.35), 0.34),
        "sfx", 4, "Evolved arc attack.")

    add("sword_wisp_hover", pad_to(mix(
            sweep(0.8, 640, 660) * env(int(RATE * 0.8), 0.3, 0.7, 0.6) * 0.5,
            sweep(0.8, 963, 987) * env(int(RATE * 0.8), 0.3, 0.7, 0.6) * 0.25), 0.85),
        "sfx", 6, "Sustained near-unison pair — the beating is the shimmer.")
    add("sword_wisp_lunge", pad_to(sweep(0.18, 500, 1400)
            * env(int(RATE * 0.18), 0.03, 0.97, 1.6), 0.22),
        "sfx", 4, "Darting rise.")
    add("sword_wisp_slash", pad_to(mix(
            highpass(noise(0.16), 3000) * env(int(RATE * 0.16), 0.006, 0.994, 2.8),
            sweep(0.16, 2200, 800) * env(int(RATE * 0.16), 0.006, 0.994) * 0.45), 0.2),
        "sfx", 4, "Bright metallic cut.")
    add("sword_wisp_return", pad_to(sweep(0.24, 1200, 620)
            * env(int(RATE * 0.24), 0.06, 0.94), 0.28),
        "sfx", 6, "Falling — the lunge run backwards.")

    add("gun_construct_servo", pad_to(mix(
            sweep(0.3, 120, 190, "square") * env(int(RATE * 0.3), 0.1, 0.9, 1.0) * 0.35,
            lowpass(noise(0.3), 900) * env(int(RATE * 0.3), 0.1, 0.9) * 0.3), 0.34),
        "sfx", 6, "Mechanical. Square wave for the motor whine.")
    add("gun_construct_aim", pad_to(mix(bell(0.22, 1174.66, 0.5),
            highpass(noise(0.05), 4000) * env(int(RATE * 0.05), 0.01, 0.99, 3.0) * 0.3), 0.26),
        "sfx", 6, "Lock-on tick.")
    add("gun_construct_shot", pad_to(mix(
            lowpass(noise(0.1), 2200) * env(int(RATE * 0.1), 0.002, 0.998, 3.2),
            sweep(0.1, 340, 90, "square") * env(int(RATE * 0.1), 0.002, 0.998) * 0.5), 0.14),
        "sfx", 5, "Percussive report.")
    add("gun_construct_burst", pad_to(mix(*[
            np.pad(mix(lowpass(noise(0.08), 2200) * env(int(RATE * 0.08), 0.002, 0.998, 3.2),
                       sweep(0.08, 340, 90, "square") * env(int(RATE * 0.08), 0.002, 0.998) * 0.5),
                   (int(RATE * 0.075 * k), 0)) for k in range(3)]), 0.4),
        "sfx", 5, "Three shots, 75 ms apart.")

    # --- Enemies: one shared family, retuned per species ----------------------
    #
    # Species come from data/enemies/*.tres, not from a list typed here. The first
    # version of this file invented six role names out of the guide's prose
    # ("windups, attacks, hits, deaths") and five of the seven actual enemies fell
    # through to the crawler's sound — every check passed, because the fallback and
    # the correct answer happened to agree for the one enemy under test.
    for species, pitch in enemy_species():
        add("enemy_%s_windup" % species, pad_to(mix(
                sweep(0.5, pitch * 0.6, pitch * 1.35) * env(int(RATE * 0.5), 0.55, 0.45, 0.7),
                lowpass(noise(0.5), pitch * 4) * env(int(RATE * 0.5), 0.55, 0.45) * 0.25), 0.55),
            "sfx", 2, "Telegraph. Priority 2 — the player has to hear a windup starting.")
        add("enemy_%s_attack" % species, pad_to(mix(
                sweep(0.14, pitch * 1.6, pitch * 0.5, "saw") * env(int(RATE * 0.14), 0.006, 0.994, 2.2),
                highpass(noise(0.1), pitch * 6) * env(int(RATE * 0.1), 0.004, 0.996, 2.8) * 0.4), 0.18),
            "sfx", 5, "Attack lands.")
        add("enemy_%s_hit" % species, pad_to(mix(
                lowpass(noise(0.09), pitch * 5) * env(int(RATE * 0.09), 0.003, 0.997, 3.0),
                sweep(0.09, pitch, pitch * 0.55) * env(int(RATE * 0.09), 0.003, 0.997) * 0.5), 0.12),
            "sfx", 5, "Took damage.")
        add("enemy_%s_death" % species, pad_to(mix(
                sweep(0.45, pitch * 1.2, pitch * 0.28, "saw") * env(int(RATE * 0.45), 0.02, 0.98, 1.3),
                lowpass(noise(0.45), pitch * 3) * env(int(RATE * 0.45), 0.02, 0.98, 1.8) * 0.4), 0.5),
            "sfx", 5, "Pitch collapse — the cheapest read for 'that thing is gone'.")

    # --- The First Bell. It is a bell, so it gets the bell. --------------------
    add("boss_slam", pad_to(mix(
            lowpass(noise(0.6), 260) * env(int(RATE * 0.6), 0.004, 0.996, 2.0),
            sweep(0.6, 90, 40) * env(int(RATE * 0.6), 0.004, 0.996) * 0.9,
            bell(0.6, 110.0, 0.35)), 0.7),
        "sfx", 2, "Heavy impact with sub weight.")
    add("boss_chain_sweep", pad_to(mix(
            highpass(noise(0.5), 1600) * env(int(RATE * 0.5), 0.2, 0.8, 1.4),
            sweep(0.5, 700, 300, "saw") * env(int(RATE * 0.5), 0.2, 0.8) * 0.4), 0.55),
        "sfx", 2, "Chain drag across stone.")
    add("boss_toll", pad_to(mix(bell(2.6, 82.41, 1.0), bell(2.6, 123.47, 0.45)), 2.8),
        "sfx", 2, "The toll. Long, low, inharmonic.")
    add("boss_stagger", pad_to(mix(
            bell(1.2, 146.83, 0.8),
            sweep(1.2, 400, 120) * env(int(RATE * 1.2), 0.03, 0.97, 1.2) * 0.5), 1.3),
        "sfx", 2, "Bell cracks open.")
    add("boss_core_break", pad_to(mix(
            highpass(noise(0.7), 2000) * env(int(RATE * 0.7), 0.006, 0.994, 2.2),
            bell(0.7, 233.08, 0.7), sweep(0.7, 1600, 200) * env(int(RATE * 0.7), 0.01, 0.99) * 0.5), 0.8),
        "sfx", 2, "Core exposed.")
    add("boss_defeat", pad_to(mix(
            bell(3.2, 65.41, 1.0), bell(3.2, 98.0, 0.5),
            sweep(3.2, 220, 55) * env(int(RATE * 3.2), 0.05, 0.95, 0.9) * 0.4), 3.4),
        "sfx", 3, "Defeat. The toll, lower and longer.")

    # --- Rewards and UI. Gold/teal territory, so bright and consonant. --------
    add("pickup", pad_to(mix(bell(0.3, 1046.5, 0.6), bell(0.3, 1318.5, 0.35)), 0.35),
        "ui", 5, "Currency or drop.")
    add("reward_card", pad_to(mix(
            pluck(0.5, 523.25) * env(int(RATE * 0.5), 0.01, 0.99, 1.0),
            pluck(0.5, 659.25) * env(int(RATE * 0.5), 0.02, 0.98, 1.0) * 0.7), 0.55),
        "ui", 4, "Card offered.")
    add("purchase", pad_to(mix(bell(0.5, 783.99, 0.7), bell(0.5, 1046.5, 0.4)), 0.55),
        "ui", 4, "Bought.")
    add("reroll", pad_to(mix(*[np.pad(bell(0.18, f, 0.5), (int(RATE * 0.06 * k), 0))
            for k, f in enumerate([659.25, 783.99, 987.77])]), 0.4),
        "ui", 4, "Rising three-note flick.")
    add("evolve", pad_to(mix(
            sweep(1.3, 261.63, 1046.5) * env(int(RATE * 1.3), 0.35, 0.65, 0.7) * 0.6,
            bell(1.3, 523.25, 0.7), bell(1.3, 659.25, 0.5), bell(1.3, 783.99, 0.4)), 1.4),
        "ui", 3, "Evolution. The biggest reward sound in the slice.")
    add("gate", pad_to(mix(
            lowpass(noise(0.8), 400) * env(int(RATE * 0.8), 0.25, 0.75, 1.2),
            sweep(0.8, 140, 70) * env(int(RATE * 0.8), 0.25, 0.75) * 0.6), 0.9),
        "sfx", 5, "Stone gate.")
    add("rift_entry", pad_to(mix(
            sweep(1.6, 1200, 140) * env(int(RATE * 1.6), 0.4, 0.6, 0.8),
            lowpass(noise(1.6), 700) * env(int(RATE * 1.6), 0.45, 0.55) * 0.4,
            bell(1.6, 174.61, 0.5)), 1.7),
        "sfx", 4, "Descending — going somewhere else.")
    add("ui_move", pad_to(bell(0.1, 880.0, 0.4), 0.12), "ui", 6, "Focus moved.")
    add("ui_confirm", pad_to(mix(bell(0.22, 1046.5, 0.5), bell(0.22, 1567.98, 0.3)), 0.26),
        "ui", 5, "Accept.")
    add("ui_cancel", pad_to(bell(0.22, 415.3, 0.5), 0.26), "ui", 5, "Back.")
    return b


# --------------------------------------------------------------------- music

def music_bank() -> dict:
    """Three short loops from guide §14. Deliberately plain and loopable.

    Each is an exact number of bars at its own tempo so the loop point lands on a
    beat — a placeholder bed that clicks every eight seconds is more distracting
    than no music.
    """
    out = {}

    def bars(bpm: float, count: int, beats_per_bar: int = 4) -> float:
        return count * beats_per_bar * 60.0 / bpm

    # music_sunfall_explore: warm plucked strings, soft percussion, distant bells
    bpm = 84.0
    length = bars(bpm, 4)
    beat = 60.0 / bpm
    buf = np.zeros(int(RATE * length))

    def place(layer: np.ndarray, at: float) -> None:
        start = int(RATE * at)
        end = min(buf.size, start + layer.size)
        if end > start:
            buf[start:end] += layer[:end - start]

    # A minor pentatonic figure — five notes, no wrong ones, no key to establish.
    scale = [220.0, 261.63, 293.66, 329.63, 392.0]
    for i in range(16):
        note = scale[[0, 2, 1, 4, 0, 3, 2, 1, 0, 2, 4, 3, 0, 1, 2, 0][i]]
        p = pluck(1.1, note) * env(int(RATE * 1.1), 0.005, 0.995, 1.1)
        place(p * 0.5, i * beat * 1.0)
    for i in range(8):
        h = lowpass(noise(0.12), 1100) * env(int(RATE * 0.12), 0.02, 0.98, 2.4)
        place(h * 0.22, i * beat * 2.0 + beat * 0.5)
    for i in range(2):
        place(bell(3.4, 110.0, 0.3), i * beat * 8.0)
    out["music_sunfall_explore"] = {
        "samples": buf, "bus": "music", "loop": True,
        "note": "Warm plucked strings, soft percussion, distant bells. 84 BPM, 4 bars.",
    }

    # music_sunfall_combat: faster percussion, distorted bell rhythm, synth pulse
    bpm = 132.0
    length = bars(bpm, 4)
    beat = 60.0 / bpm
    buf = np.zeros(int(RATE * length))
    for i in range(16):
        k = lowpass(noise(0.16), 180) * env(int(RATE * 0.16), 0.002, 0.998, 2.2)
        place(k * 0.6, i * beat)
    for i in range(8):
        s = highpass(noise(0.1), 1600) * env(int(RATE * 0.1), 0.002, 0.998, 3.0)
        place(s * 0.3, i * beat * 2.0 + beat)
    for i in range(8):
        # Clipped bell — the guide's "distorted bell rhythm".
        b = np.tanh(bell(0.5, 164.81, 1.0) * 3.0)
        place(b * 0.28, i * beat * 2.0)
    pulse = sweep(length, 55.0, 55.0, "square")
    lfo = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (1.0 / (beat * 0.5)) * t(length)))
    buf += pulse * lfo * 0.16
    out["music_sunfall_combat"] = {
        "samples": buf, "bus": "music", "loop": True,
        "note": "Faster percussion, distorted bell rhythm, synth pulse. 132 BPM, 4 bars.",
    }

    # music_first_bell: heavy bell strikes, chain percussion, choir-like pads
    bpm = 72.0
    length = bars(bpm, 4)
    beat = 60.0 / bpm
    buf = np.zeros(int(RATE * length))
    for i in range(4):
        place(bell(4.2, 82.41, 0.9), i * beat * 4.0)
    for i in range(16):
        c = highpass(noise(0.2), 2200) * env(int(RATE * 0.2), 0.02, 0.98, 2.0)
        place(c * 0.16, i * beat + beat * 0.5)
    # "Choir-like": stacked detuned sines on a minor triad. Not a choir. Close
    # enough to hold the harmony a real pad would.
    for f in (110.0, 130.81, 164.81, 220.0):
        for detune in (-2.5, 0.0, 2.5):
            buf += (np.sin(2 * np.pi * (f + detune) * t(length))
                    * (0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * t(length))) * 0.05)
    out["music_first_bell"] = {
        "samples": buf, "bus": "music", "loop": True,
        "note": "Heavy bell strikes, chain percussion, choir-like pads. 72 BPM, 4 bars.",
    }
    return out


# ---------------------------------------------------------------------- build

def main() -> int:
    print("Synthesising placeholder audio (no samples, nothing downloaded)\n")
    slots = {"sfx": [], "music": []}

    sfx = sfx_bank()
    for name in sorted(sfx):
        entry = sfx[name]
        path = SFX_DIR / ("%s.wav" % name)
        size = write(path, entry["samples"])
        seconds = entry["samples"].size / RATE
        slots["sfx"].append({
            "slot": name,
            "path": "res://assets/audio/sfx/%s.wav" % name,
            "bus": entry["bus"],
            "priority": entry["priority"],
            "seconds": round(seconds, 3),
            "bytes": size,
            "note": entry["note"],
        })
    print("  sfx    %d slots, %.1f KiB" % (
        len(slots["sfx"]), sum(s["bytes"] for s in slots["sfx"]) / 1024))

    music = music_bank()
    for name in sorted(music):
        entry = music[name]
        path = MUSIC_DIR / ("%s.wav" % name)
        size = write(path, entry["samples"], stereo=True)
        seconds = entry["samples"].size / RATE
        slots["music"].append({
            "slot": name,
            "path": "res://assets/audio/music/%s.wav" % name,
            "bus": entry["bus"],
            "loop": True,
            "seconds": round(seconds, 3),
            "bytes": size,
            "note": entry["note"],
        })
        print("  music  %-24s %5.2fs  %6.1f KiB" % (name, seconds, size / 1024))

    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps({
        "_comment": [
            "Generated by tools/make_placeholder_audio.py. Do not hand-edit.",
            "Every entry is synthesised from scratch — no samples, nothing licensed.",
            "`priority` is guide §14's mix order: 1 is the player damage warning and",
            "must always be audible, 6 is environment and is the first to be dropped.",
            "To replace a placeholder with real audio, write over the same filename and",
            "reimport. Nothing in the game refers to these files by anything but slot.",
        ],
        "sample_rate": RATE,
        "buses": ["Master", "music", "sfx", "ui"],
        "sfx": slots["sfx"],
        "music": slots["music"],
    }, indent=2) + "\n")

    total = sum(s["bytes"] for s in slots["sfx"] + slots["music"])
    print("\nWrote %s" % MANIFEST.relative_to(ROOT))
    print("%d slots, %.2f MiB" % (len(slots["sfx"]) + len(slots["music"]), total / 1024 / 1024))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
