"""Generate golden fixtures for the Dart port from the original Python.

    python tools/gen_fixtures.py

Reads `pull_ups/src/reps.py` read-only (no network, no API key, no video) and
writes `test/fixtures/*.json`. Each fixture carries synthetic COCO-17 poses and
every number the Python pipeline derived from them, so `flutter test` can prove
the Dart port agrees to the last decimal.
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP_DIR = HERE.parent
DEMO_DIR = APP_DIR.parent / "pull_ups"
FIXTURE_DIR = APP_DIR / "test" / "fixtures"

sys.path.insert(0, str(DEMO_DIR))

import config as cfg  # noqa: E402  (the pipeline's own constants)
from src import reps  # noqa: E402

# ── Geometry ────────────────────────────────────────────────────────────────
# A body in normalized coordinates, built so the elbow angle sweeps from a
# near-straight hang (~167 degrees) to a folded top (~60 degrees) as the torso
# rises. Nothing here is a real athlete; it is a rig that exercises every
# branch of the counter and the grader.
WRIST_Y = 0.22
SHOULDER_Y_HANG = 0.568
TORSO_SPAN = 0.23
UPPER_ARM = 0.175
MAX_RISE = 0.173

LEFT = (0.45, 0.44)
RIGHT = (0.55, 0.56)


def _elbow(shoulder, wrist, sign):
    sx, sy = shoulder
    wx, wy = wrist
    dx, dy = wx - sx, wy - sy
    dist = math.hypot(dx, dy)
    half = dist / 2.0
    h = math.sqrt(max(UPPER_ARM**2 - half**2, 0.0))
    mx, my = (sx + wx) / 2.0, (sy + wy) / 2.0
    px, py = -dy / dist, dx / dist
    # The two candidates are mirror images; pick the one further outwards.
    a = (mx + px * h, my + py * h)
    b = (mx - px * h, my - py * h)
    return a if (a[0] - mx) * sign > 0 else b


def pose(
    rise: float,
    clearance: float,
    *,
    off_bar: float = 0.0,
    missing: tuple[str, ...] = (),
    score: float = 0.9,
    rng: random.Random | None = None,
    noise: float = 0.0,
    side_missing: str | None = None,
):
    """One COCO-17 person at *rise* metres of normalized displacement."""
    sh_y = SHOULDER_Y_HANG - rise
    hip_y = sh_y + TORSO_SPAN
    head_y = WRIST_Y - clearance * TORSO_SPAN

    kpts = [[0.0, 0.0] for _ in range(17)]
    scores = [0.0] * 17

    def put(i, x, y):
        if rng is not None and noise:
            x += rng.uniform(-noise, noise)
            y += rng.uniform(-noise, noise)
        kpts[i] = [x, y]
        scores[i] = score

    put(0, 0.5, head_y)                    # nose
    put(1, 0.49, head_y - 0.006)           # left eye
    put(2, 0.51, head_y - 0.006)           # right eye
    put(3, 0.47, head_y + 0.004)           # left ear
    put(4, 0.53, head_y + 0.004)           # right ear
    put(5, LEFT[0], sh_y)                  # left shoulder
    put(6, RIGHT[0], sh_y)                 # right shoulder
    put(11, 0.46, hip_y)                   # left hip
    put(12, 0.54, hip_y)                   # right hip
    put(13, 0.46, hip_y + 0.2)             # left knee
    put(14, 0.54, hip_y + 0.2)             # right knee
    put(15, 0.46, hip_y + 0.4)             # left ankle
    put(16, 0.54, hip_y + 0.4)             # right ankle

    for side, (sx, wx), (elbow_i, wrist_i) in (
        ("left", LEFT, (7, 9)),
        ("right", RIGHT, (8, 10)),
    ):
        wrist = (wx, WRIST_Y + off_bar)
        elbow = _elbow((sx, sh_y), wrist, -1.0 if side == "left" else 1.0)
        put(elbow_i, *elbow)
        put(wrist_i, *wrist)

    hidden = set(missing)
    if side_missing == "left":
        hidden |= {"left_shoulder", "left_elbow", "left_wrist"}
    elif side_missing == "right":
        hidden |= {"right_shoulder", "right_elbow", "right_wrist"}
    names = ["nose", "left_eye", "right_eye", "left_ear", "right_ear",
             "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
             "left_wrist", "right_wrist", "left_hip", "right_hip",
             "left_knee", "right_knee", "left_ankle", "right_ankle"]
    for name in hidden:
        i = names.index(name)
        kpts[i] = [0.0, 0.0]
        scores[i] = 0.0

    return {
        "kpts_xy": kpts,
        "kpts_score": scores,
        "bbox_xywh": [0.35, max(0.0, sh_y - 0.15), 0.3, min(0.9, hip_y + 0.45)],
        "track_id": 0,
    }


def frames_from(
    rise_and_clearance,
    *,
    fps: float,
    off_bar_ranges=(),
    missing_ranges=(),
    rng: random.Random | None = None,
    noise: float = 0.0,
    empty_ranges=(),
):
    frames = []
    for i, (rise, clearance) in enumerate(rise_and_clearance):
        in_off = any(a <= i < b for a, b in off_bar_ranges)
        missing = ()
        for a, b, names in missing_ranges:
            if a <= i < b:
                missing = names
        persons = [] if any(a <= i < b for a, b in empty_ranges) else [
            pose(rise, clearance, off_bar=0.09 if in_off else 0.0,
                 missing=missing, rng=rng, noise=noise)
        ]
        frames.append({"index": i, "persons": persons})
    return frames


def profile(reps_spec, fps=30.0, tail=0.35):
    """A rise/clearance profile. Each rep is (rest_s, up_s, hold_s, down_s, clearance)."""
    seconds = sum(rest + up + hold + down for rest, up, hold, down, _ in reps_spec)
    total = int(round((seconds + tail) * fps))
    out = []
    for i in range(total):
        out.append((0.0, 0.0))
    cursor = 0
    for rest, up, hold, down, clear in reps_spec:
        cursor += int(round(rest * fps))
        n_up = max(2, int(round(up * fps)))
        for k in range(n_up):
            if cursor + k >= total:
                break
            out[cursor + k] = (MAX_RISE * (k + 1) / n_up, clear * (k + 1) / n_up)
        cursor += n_up
        n_hold = int(round(hold * fps))
        for k in range(n_hold):
            if cursor + k >= total:
                break
            out[cursor + k] = (MAX_RISE, clear)
        cursor += n_hold
        n_down = max(2, int(round(down * fps)))
        for k in range(n_down):
            if cursor + k >= total:
                break
            out[cursor + k] = (MAX_RISE * (1 - (k + 1) / n_down), clear * (1 - (k + 1) / n_down))
        cursor += n_down
    return out[:total]


def _json_safe(value):
    """JSON has no NaN; `null` marks it, and the Dart test reads it back as NaN."""
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    return value


def dump(path: Path, name: str, mode: str, frames, fps: float, aspect: float,
         n_source: int, analysis) -> None:
    out = {
        "name": name,
        "mode": mode,
        "fps": fps,
        "aspect": aspect,
        "n_source_frames": n_source,
        "frames": frames,
        "expected": {
            "baseline": float(analysis.baseline),
            "amplitude": float(analysis.amplitude),
            "hang_required": float(analysis.hang_required),
            "clearance_required": float(analysis.clearance_required),
            "indices": [int(v) for v in analysis.indices],
            "times": [float(v) for v in analysis.times],
            "displacement": [float(v) for v in analysis.displacement],
            "head_margin": [float(v) for v in analysis.head_margin],
            "elbow": [float(v) for v in analysis.elbow],
            "clearance": [float(v) for v in analysis.clearance],
            "on_bar": [bool(v) for v in analysis.on_bar],
            "counts": [int(v) for v in analysis.counts_by_source_frame],
            "reps": [
                {
                    "number": r.number,
                    "valley_frame": r.valley_frame,
                    "onset_frame": r.onset_frame,
                    "peak_frame": r.peak_frame,
                    "end_frame": r.end_frame,
                    "valley_time": float(r.valley_time),
                    "onset_time": float(r.onset_time),
                    "peak_time": float(r.peak_time),
                    "end_time": float(r.end_time),
                    "ascent_seconds": float(r.ascent_seconds),
                    "moving_seconds": float(r.moving_seconds),
                    "descent_seconds": float(r.descent_seconds),
                    "total_seconds": float(r.total_seconds),
                    "height": float(r.height),
                    "rom": None if r.rom is None else {
                        "complete": bool(r.rom.complete),
                        "hang_degrees": float(r.rom.hang_degrees),
                        "peak_degrees": float(r.rom.peak_degrees),
                        "clearance": float(r.rom.clearance),
                        "bottom_ok": bool(r.rom.bottom_ok),
                        "top_ok": bool(r.rom.top_ok),
                        "hang_required": float(r.rom.hang_required),
                        "clearance_required": float(r.rom.clearance_required),
                    },
                }
                for r in analysis.reps
            ],
        },
    }
    path.write_text(json.dumps(_json_safe(out), indent=1))
    print(f"  {path.name}: {len(analysis.reps)} reps")


def config_for(mode: str):
    """The demo's config, with the three constants that make a chin-up a chin-up."""
    if mode == "pullUp":
        return cfg

    class ChinConfig:
        pass

    out = ChinConfig()
    for key in dir(cfg):
        if key.isupper():
            setattr(out, key, getattr(cfg, key))
    out.HEAD_JOINTS = ("left_eye", "right_eye")
    out.REQUIRE_HEAD_ABOVE_HANDS = True
    out.GRADE_ROM = False
    out.REP_METRIC = "moving"
    return out


def build(name, mode, frames, fps=30.0, aspect=720 / 1280, n_source=None):
    n_source = len(frames) if n_source is None else n_source
    analysis = reps.analyze(frames, fps, n_source, cfg=config_for(mode), aspect=aspect)
    dump(FIXTURE_DIR / f"{name}.json", name, mode, frames, fps, aspect, n_source,
         analysis)


def main() -> int:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for old in FIXTURE_DIR.glob("*.json"):
        old.unlink()
    rng = random.Random(7)

    six = [(0.6, 0.55, 0.1, 0.65, 0.42)] * 6
    build("six_full_pull_ups", "pullUp",
          frames_from(profile(six), fps=30, rng=rng, noise=0.0012))

    partial = []
    for i in range(5):
        partial.append((0.5, 0.55, 0.1, 0.6, 0.42 if i % 2 == 0 else 0.05))
    build("alternating_clearance", "pullUp",
          frames_from(profile(partial), fps=30, rng=rng, noise=0.001))

    # Every valley starts bent: no full hang anywhere.
    short_bottom = [(0.5, 0.55, 0.1, 0.6, 0.4)] * 4

    def bent_bottom(base):
        return [
            ((MAX_RISE * 0.17) + (MAX_RISE * 0.83) * rise, clear)
            for rise, clear in base
        ]
    base = profile(short_bottom)
    build("no_full_hang", "pullUp",
          frames_from(bent_bottom(base), fps=30, rng=rng, noise=0.0008))

    build("single_rep", "pullUp",
          frames_from(profile([(0.3, 0.5, 0.1, 0.55, 0.42)]),
                      fps=30, rng=rng, noise=0.0015))

    build("no_reps", "pullUp",
          frames_from([(0.0, 0.0)] * 90, fps=30, noise=0.0))

    build("no_person", "pullUp",
          frames_from([(0.0, 0.0)] * 60, fps=30, empty_ranges=[(0, 60)]))

    build("missing_arm_and_head", "pullUp",
          frames_from(profile([(0.5, 0.55, 0.1, 0.6, 0.42)] * 3),
                      fps=30, rng=rng, noise=0.0008,
                      missing_ranges=[(5, 14, ("left_elbow", "left_wrist")),
                                      (30, 40, ("nose", "left_eye", "right_eye",
                                                "left_ear", "right_ear"))]))

    build("hands_off_bar", "pullUp",
          frames_from(profile([(0.5, 0.55, 0.1, 0.6, 0.42)] * 3),
                      fps=30, rng=rng, noise=0.0008,
                      off_bar_ranges=[(20, 30), (62, 70)]))

    cut = profile([(0.4, 0.55, 0.1, 0.7, 0.42), (0.4, 0.55, 0.0, 0.0, 0.42)])
    build("ends_mid_rep", "pullUp", frames_from(cut, fps=30, rng=rng, noise=0.001))

    build("three_frames", "pullUp",
          frames_from([(0.0, 0.0), (MAX_RISE, 0.42), (0.0, 0.0)], fps=30))

    build("all_joints_unseen", "pullUp",
          frames_from([(0.0, 0.0)] * 45, fps=30,
                      missing_ranges=[(0, 45, tuple(
                          ["nose", "left_eye", "right_eye", "left_ear",
                           "right_ear", "left_shoulder", "right_shoulder",
                           "left_elbow", "right_elbow", "left_wrist",
                           "right_wrist", "left_hip", "right_hip",
                           "left_knee", "right_knee", "left_ankle",
                           "right_ankle"]))]))

    build("many_reps_60fps", "pullUp",
          frames_from(profile([(0.25, 0.4, 0.05, 0.45, 0.42)] * 8, fps=60),
                      fps=60, rng=rng, noise=0.001))

    build("landscape_aspect", "pullUp",
          frames_from(profile([(0.5, 0.55, 0.1, 0.6, 0.42)] * 3),
                      fps=30, rng=rng, noise=0.001,),
          aspect=1280 / 720)

    # Chin-up mode gates every rep on the chin clearing the bar. These reps
    # never get the head above the hands, so they must not count at all.
    build("chin_up_below_bar", "chinUp",
          frames_from(profile([(0.4, 0.55, 0.1, 0.6, -0.12)] * 3),
                      fps=30, rng=rng, noise=0.0008))

    build("chin_up_over_bar", "chinUp",
          frames_from(profile([(0.4, 0.55, 0.1, 0.6, 0.35)] * 3),
                      fps=30, rng=rng, noise=0.0008))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
