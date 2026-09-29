"""MaleCNS connectome (frozen) + a Roblox readout trained while you play."""

from __future__ import annotations

import threading
import time
from pathlib import Path

import numpy as np
from flybrain import FeatureDetectors, FlyBrain
from flybrain.reservoir import Readout, Trace

FRUIT_NAMES = {"banana", "apple", "grape", "grapes", "lime", "fruit", "mango", "peach"}
REPEL_NAMES = {"pineapple", "stench", "rotten"}
PLAYER_NAMES = {"player", "solidifiedplaydoh", "character"}
READOUT_PATH = Path(__file__).resolve().parents[2] / "readout.npz"


def _rate(idx: np.ndarray, fired: np.ndarray) -> float:
    if idx.size == 0:
        return 0.0
    return float(np.intersect1d(idx, fired, assume_unique=False).size) / float(idx.size)


def _is_player(obj: dict) -> bool:
    kind = str(obj.get("kind") or "").lower()
    name = str(obj.get("name") or "").lower()
    if kind == "player":
        return True
    return any(token in name for token in PLAYER_NAMES)


def _is_fruit(obj: dict) -> bool:
    kind = str(obj.get("kind") or "").lower()
    if kind in {"fruit", "attract"}:
        return True
    name = str(obj.get("name") or "").lower()
    return any(token in name for token in FRUIT_NAMES)


def _is_repel(obj: dict) -> bool:
    kind = str(obj.get("kind") or "").lower()
    if kind in {"repel", "stench"}:
        return True
    name = str(obj.get("name") or "").lower()
    return any(token in name for token in REPEL_NAMES)


def _is_wall(obj: dict) -> bool:
    kind = str(obj.get("kind") or "").lower()
    if kind in {"player", "fruit", "attract", "ground", "repel", "stench"}:
        return False
    if kind == "wall":
        return True
    name = str(obj.get("name") or "").lower()
    return any(token in name for token in ("wall", "barrier", "baseplate"))


def _chemosense(objects: list[dict]) -> tuple[float, float]:
    attract = 0.0
    repel = 0.0
    for obj in objects:
        distance = float(obj.get("distance") or 50.0)
        strength = float(obj.get("strength") or 1.0)
        fall = max(0.0, 1.0 - distance / 42.0) * strength
        if _is_repel(obj):
            repel = max(repel, fall * 1.25)
        elif _is_fruit(obj):
            attract = max(attract, fall)
    return attract, repel


def _ring_action(distances) -> tuple[float, float, float] | None:
    """Steer from a 360 distance ring. Bearing 0 is ahead, positive is right."""
    if not isinstance(distances, list) or len(distances) < 8:
        return None
    samples: list[tuple[float, float]] = []
    for item in distances:
        if not isinstance(item, dict):
            continue
        try:
            bearing = float(item.get("bearing")) % 360.0
            distance = float(item.get("distance"))
        except (TypeError, ValueError):
            continue
        samples.append((bearing, distance))
    if len(samples) < 8:
        return None

    def nearest(target: float) -> float:
        best = samples[0][1]
        best_gap = 999.0
        for bearing, distance in samples:
            gap = abs(bearing - target) % 360.0
            gap = min(gap, 360.0 - gap)
            if gap < best_gap:
                best_gap = gap
                best = distance
        return best

    ahead = nearest(0.0)
    right_weight = 0.0
    ahead_weight = 0.0
    for bearing, distance in samples:
        rad = np.deg2rad(bearing)
        right_weight += np.sin(rad) * distance
        ahead_weight += np.cos(rad) * distance
    heading = float(np.degrees(np.arctan2(right_weight, ahead_weight)))
    if ahead < 8:
        turn = float(np.clip(heading / 40.0, -1, 1))
        if abs(turn) < 0.4:
            turn = 0.85 if heading >= 0 else -0.85
        forward = -0.2 if ahead < 3 else 0.05
    else:
        turn = float(np.clip(heading / 90.0, -1, 1))
        forward = float(np.clip(0.25 + (ahead - 8.0) / 24.0, 0.2, 0.9))
        return forward, turn, ahead


def _ring_samples(distances) -> list[tuple[float, float]]:
    samples: list[tuple[float, float]] = []
    if not isinstance(distances, list):
        return samples
    for item in distances:
        if not isinstance(item, dict):
            continue
        try:
            samples.append((float(item.get("bearing")) % 360.0, float(item.get("distance")), float(item.get("trail") or 0)))
        except (TypeError, ValueError):
            continue
    return samples


def teacher_action(
    objects: list[dict],
    poke: bool,
    *,
    altitude: float = 3.0,
    airborne: bool = False,
    bout: str = "rest",
) -> np.ndarray:
    """Rest, walk, or fly. Chase ripe fruit, flee pineapple stench."""
    target = None
    player = None
    fruit = None
    repel = None
    threat = 0.0
    wall_turn = 0.0
    wall_block = 0.0
    for obj in objects:
        dx = float(obj.get("dx") or 0.0)
        size = float(obj.get("size") or 4.0)
        distance = float(obj.get("distance") or 50.0)
        if _is_repel(obj):
            if repel is None or distance < repel[2]:
                repel = (dx, size, distance, "repel")
            threat = max(threat, min(1.0, (1.0 - distance / 22.0) * 1.3))
        elif _is_fruit(obj):
            if fruit is None or distance < fruit[2]:
                fruit = (dx, size, distance, "fruit")
        elif _is_player(obj):
            if player is None:
                player = (dx, size, distance, "player")
        if _is_wall(obj) and distance < 20:
            front = 1.0 - min(1.0, abs(dx) / 28.0)
            proximity = 1.0 - min(1.0, distance / 20.0)
            wall_block = max(wall_block, front * proximity)
            if abs(dx) < 3:
                wall_turn += 0.9 * proximity
            else:
                wall_turn += float(np.sign(dx)) * proximity
        if (
            distance < 8
            and not _is_wall(obj)
            and not _is_player(obj)
            and not _is_fruit(obj)
        ):
            threat = max(threat, 1.0 - distance / 8.0)

    target = fruit or player

    turn = float(np.clip(wall_turn, -1, 1))
    jump = 0.0
    fly = 0.0
    up = 0.0
    forward = 0.0

    if repel is not None and repel[2] < 34:
        dx, _size, distance, _kind = repel
        away = -float(np.tanh(dx / 10.0))
        if abs(dx) < 8:
            away = 0.85 if dx >= 0 else -0.85
        turn = float(np.clip(away + 0.35 * wall_turn, -1, 1))
        fly = 1.0
        jump = 1.0
        up = 0.75 if altitude < 16 else -0.1
        forward = -0.55 if abs(dx) < 18 else 0.35
        forward *= 1.0 - 0.7 * wall_block
        return np.array(
            [
                float(np.clip(forward, -1, 1)),
                turn,
                jump,
                fly,
                float(np.clip(up, -1, 1)),
            ],
            np.float32,
        )

    if poke or threat > 0.55:
        fly = 1.0
        jump = 1.0
        forward = 0.55 * (1.0 - wall_block)
        up = 0.7 if altitude < 14 else -0.1
        turn += 0.4
    elif bout == "rest" and not airborne:
        forward = 0.0
        fly = 0.0
        if wall_block > 0.5:
            turn = float(np.clip(wall_turn, -1, 1))
    elif bout == "fly" or airborne:
        fly = 0.85 if altitude < 22 else 0.5
        if altitude < 6:
            up = 0.65
        elif altitude > 16:
            up = -0.45
        else:
            up = 0.05
        if target is not None:
            dx, _size, distance, kind = target
            turn = float(np.tanh(dx / 12.0)) + 0.5 * turn
            if kind == "fruit" and distance < 10:
                fly = 0.2
                up = -0.7
                forward = 0.15
            else:
                forward = 0.45 + 0.35 * (1.0 - min(1.0, abs(dx) / 40.0))
        else:
            forward = 0.2 * (1.0 - wall_block)
        if wall_block > 0.45:
            forward = min(forward, -0.15)
            up = max(up, 0.35)
    else:
        # walk bout
        fly = 0.0
        if target is None:
            forward = 0.2 * (1.0 - wall_block)
        else:
            dx, _size, distance, _kind = target
            turn = float(np.tanh(dx / 12.0)) + 0.5 * turn
            aligned = 1.0 - min(1.0, abs(dx) / 40.0)
            forward = 0.2 + 0.55 * aligned
            if distance < 6:
                forward *= 0.15
            if distance > 18 and aligned > 0.7:
                fly = 0.55
                up = 0.4
                jump = 0.8
        forward *= 1.0 - 0.95 * wall_block
        if wall_block > 0.6:
            forward = min(forward, -0.2)

    return np.array(
        [
            float(np.clip(forward, -1, 1)),
            float(np.clip(turn, -1, 1)),
            jump,
            float(np.clip(fly, 0, 1)),
            float(np.clip(up, -1, 1)),
        ],
        np.float32,
    )


class MaleCNSFly:
    def __init__(self) -> None:
        print("Loading MaleCNS (166,700 neurons). Wiring stays frozen; a Roblox readout trains on top.")
        self.brain = FlyBrain(device="cpu", sensory_input=True)
        self.eyes = FeatureDetectors(self.brain, chase_base=0.8, chase_gain=0.4, cap=0.8)
        self.forward_idx = self.brain.cells(["DNg100"])
        self.back_idx = self.brain.cells(["MDN"])
        self.steer_l = self.brain.cells(["DNa02"], side="L")
        self.steer_r = self.brain.cells(["DNa02"], side="R")
        self.escape_idx = self.brain.cells(["DNp01"])
        self.dn = self.brain.cells(["descending_neuron"])
        self.dn_l = self.brain.cells(["descending_neuron"], side="L")
        self.dn_r = self.brain.cells(["descending_neuron"], side="R")
        self.trace = Trace(
            self.brain,
            types=["DNa02", "DNg100", "MDN", "DNp01", "LC10a", "LPLC2", "LC4"],
        )
        self._ema = {"forward": 0.0, "turn": 0.0, "jump": 0.0, "fly": 0.0, "up": 0.0}
        self._X: list[np.ndarray] = []
        self._y: list[np.ndarray] = []
        self._readout: Readout | None = None
        self._fit_lock = threading.Lock()
        self._fitting = False
        self.samples = 0
        self._bout = "rest"
        self._bout_until = 0.0
        self._steer_sign = 0
        self._steer_ahead: float | None = None
        self._steer_note = "no attempts yet"
        self._clearance = [0.0] * 24
        self._visits: dict[tuple[int, int], int] = {}
        self._cell: tuple[int, int] | None = None
        self._attempts: list[str] = []
        self._preview_lock = threading.Lock()
        self._preview_seq = 0
        self._preview_spikes = np.empty(0, np.uint32)
        self._preview_rng = np.random.default_rng(7)
        self._preview_layout = b""
        self._build_preview()
        if READOUT_PATH.exists():
            try:
                self._readout = Readout.load(READOUT_PATH)
                print("loaded trained Roblox readout from", READOUT_PATH)
            except Exception as exc:
                print("could not load readout:", exc)

    def _build_preview(self) -> None:
        """Flat view of the real MaleCNS coordinates, for the OBS brain picture."""
        pos = np.asarray(self.brain.positions, dtype=np.float32)
        finite = np.isfinite(pos).all(axis=1)
        idx = np.flatnonzero(finite).astype(np.uint32)
        width, height = 720, 350
        if idx.size == 0:
            self._preview_layout = b"FLY1" + np.zeros(4, np.uint32).tobytes()
            return
        x = pos[idx, 0]
        z = pos[idx, 2]
        xmin, xmax = float(x.min()), float(x.max())
        zmin, zmax = float(z.min()), float(z.max())
        pad = 0.05
        # Animal left is the high X. Put that on the left of the picture.
        tx = 1.0 - (x - xmin) / max(xmax - xmin, 1.0)
        tz = (z - zmin) / max(zmax - zmin, 1.0)
        tx = pad + tx * (1.0 - 2 * pad)
        tz = pad + tz * (1.0 - 2 * pad)
        xs = np.clip(tx * (width - 1), 0, width - 1).astype(np.uint16)
        ys = np.clip(tz * (height - 1), 0, height - 1).astype(np.uint16)
        names = np.asarray(self.brain.superclass, dtype=str)[idx]
        kind = np.zeros(idx.size, np.uint8)
        kind[np.char.startswith(names, "cb_")] = 1
        kind[np.char.startswith(names, "ol_") | np.char.startswith(names, "visual_")] = 2
        kind[np.char.startswith(names, "vnc_")] = 3
        command = np.isin(
            names,
            [
                "descending_neuron",
                "descending_neuron_tbc",
                "ascending_neuron",
                "efferent_descending",
                "efferent_ascending",
                "cb_motor",
                "vnc_motor",
            ],
        )
        kind[command] = 4
        header = np.array([self.brain.n, width, height, idx.size], np.uint32)
        self._preview_layout = (
            b"FLY1" + header.tobytes() + idx.tobytes() + xs.tobytes() + ys.tobytes() + kind.tobytes()
        )
        names = np.asarray(self.brain.superclass, dtype=str)
        types = np.asarray(self.brain.cell_type, dtype=str)
        watch = np.isin(
            names,
            ["descending_neuron", "descending_neuron_tbc", "visual_projection", "visual_projection_tbc"],
        )
        watch |= np.isin(types, ["DNg100", "MDN", "DNa02", "DNp01", "LC10a", "LPLC2", "LC4"])
        self._preview_watch = watch
        print(f"brain preview placed {idx.size} neurons, watching {int(watch.sum())}", flush=True)

    def preview_layout(self) -> bytes:
        return self._preview_layout

    def preview_spikes(self) -> bytes:
        with self._preview_lock:
            ids = self._preview_spikes
            seq = self._preview_seq
        header = np.array([seq, ids.size], np.uint32)
        return b"SPK1" + header.tobytes() + ids.tobytes()

    def _remember_preview(self, chunks: list[np.ndarray]) -> None:
        if not chunks:
            ids = np.empty(0, np.uint32)
        else:
            ids = np.unique(np.concatenate(chunks))
            ids = ids[self._preview_watch[ids]]
            if ids.size:
                types = np.asarray(self.brain.cell_type, dtype=str)[ids]
                command = np.isin(types, ["DNg100", "MDN", "DNa02", "DNp01", "LC10a", "LPLC2", "LC4"])
                rest = ids[~command]
                if rest.size > 400:
                    rest = self._preview_rng.choice(rest, 400, replace=False)
                ids = np.concatenate([ids[command], np.asarray(rest, dtype=ids.dtype)])
            ids = np.asarray(ids, dtype=np.uint32)
        with self._preview_lock:
            self._preview_spikes = ids
            self._preview_seq = (self._preview_seq + 1) & 0xFFFFFFFF

    def _pick_bout(self, poke: bool, airborne: bool, attract: float, repel: float) -> str:
        now = time.time()
        if poke or repel > 0.28:
            self._bout = "walk"
            self._bout_until = now + 1.2
            return self._bout
        if attract > 0.22:
            self._bout = "walk"
            self._bout_until = now + 1.4
            return self._bout
        if now < self._bout_until:
            if self._bout == "fly":
                self._bout = "walk"
            return self._bout
        roll = float(np.random.random())
        if roll < 0.62:
            self._bout = "rest"
            self._bout_until = now + 1.5 + 4.0 * float(np.random.random())
        else:
            self._bout = "walk"
            self._bout_until = now + 0.4 + 1.6 * float(np.random.random())
        return self._bout

    def _remember_space(self, samples: list[tuple[float, float]], pose: tuple[float, float, float] | None) -> None:
        seen: set[int] = set()
        facing = 0.0 if pose is None else pose[2]
        for sample in samples:
            bearing, distance = sample[0], sample[1]
            world = (facing + bearing) % 360.0
            index = int(np.floor(world / 15.0)) % 24
            seen.add(index)
            self._clearance[index] = max(float(distance), self._clearance[index] * 0.995)
        for index in range(24):
            if index not in seen:
                self._clearance[index] *= 0.995
        if pose is None:
            return
        cell = (int(np.floor(pose[0] / 8.0)), int(np.floor(pose[1] / 8.0)))
        if cell != self._cell:
            self._visits[cell] = self._visits.get(cell, 0) + 1
            self._cell = cell

    def _space_score(self, bearing: float, distance: float, pose: tuple[float, float, float] | None) -> float:
        if pose is None:
            return float(distance)
        facing, x, z = pose[2], pose[0], pose[1]
        world = (facing + bearing) % 360.0
        index = int(np.floor(world / 15.0)) % 24
        rad = np.deg2rad(world)
        cell = (
            int(np.floor((x + np.sin(rad) * 10.0) / 8.0)),
            int(np.floor((z + np.cos(rad) * 10.0) / 8.0)),
        )
        penalty = 2.5 * min(self._visits.get(cell, 0), 4)
        if self._cell == cell:
            penalty = 0.0
        return float(distance) + 0.7 * self._clearance[index] - penalty

    def _apple_from(self, smells) -> tuple[float, float] | None:
        if not isinstance(smells, list):
            return None
        best: tuple[float, float] | None = None
        for obj in smells:
            if not isinstance(obj, dict) or str(obj.get("name") or "").lower() != "apple":
                continue
            if not _is_fruit(obj):
                continue
            try:
                bearing = float(obj.get("bearing")) % 360.0
                studs = float(obj.get("apple_studs") if obj.get("apple_studs") is not None else 99)
            except (TypeError, ValueError):
                continue
            if best is None or studs < best[1]:
                best = (bearing, studs)
        return best

    def _steer_from_ring(self, distances, pose_raw, smells=None) -> tuple[float, float, float] | None:
        """Turn toward open space that leads to the apple smell."""
        samples = _ring_samples(distances)
        if len(samples) < 8:
            return None
        pose = None
        if isinstance(pose_raw, dict):
            try:
                pose = (float(pose_raw["x"]), float(pose_raw["z"]), float(pose_raw["facing"]))
            except (TypeError, ValueError, KeyError):
                pose = None
        self._remember_space(samples, pose)
        apple = self._apple_from(smells)

        def nearest(target: float) -> tuple[float, float]:
            best = samples[0][1]
            best_trail = samples[0][2] if len(samples[0]) > 2 else 0.0
            best_gap = 999.0
            for sample in samples:
                bearing, distance = sample[0], sample[1]
                trail = sample[2] if len(sample) > 2 else 0.0
                gap = abs(bearing - target) % 360.0
                gap = min(gap, 360.0 - gap)
                if gap < best_gap:
                    best_gap = gap
                    best = distance
                    best_trail = trail
            return best, best_trail

        def gap_to(bearing: float, target: float) -> float:
            gap = abs(bearing - target) % 360.0
            return min(gap, 360.0 - gap)

        def score(item: tuple) -> float:
            bearing, distance = item[0], item[1]
            trail = item[2] if len(item) > 2 else 0.0
            base = self._space_score(bearing, distance, pose) - min(max(trail, 0.0), 4.0) * 5.0
            if apple is None or distance < 8.0:
                return base
            gap = gap_to(bearing, apple[0])
            if gap > 70.0:
                return base
            return base + (1.0 - gap / 70.0) * 40.0

        ahead, ahead_trail = nearest(0.0)
        if apple is not None and apple[1] < 6.0:
            note = "eating the apple"
            self._steer_sign = 0
            self._steer_ahead = ahead
            self._steer_note = note
            if not self._attempts or self._attempts[-1] != note:
                self._attempts.append(note)
                del self._attempts[:-6]
            return 0.0, 0.0, apple[1]

        best_bearing = max(samples, key=score)[0]
        signed = best_bearing if best_bearing <= 180.0 else best_bearing - 360.0
        desired = 1 if signed >= 0.0 else -1
        previous = self._steer_ahead
        note = None
        if self._steer_sign != 0 and previous is not None:
            if ahead >= previous + 2.0:
                desired = self._steer_sign
                note = f"turn {'right' if desired > 0 else 'left'}: succeeded, space ahead opened ({previous:.0f}->{ahead:.0f})"
            elif ahead <= previous - 2.0:
                desired = -self._steer_sign
                note = f"turn {'right' if self._steer_sign > 0 else 'left'}: failed, space ahead closed ({previous:.0f}->{ahead:.0f})"
            else:
                desired = self._steer_sign
                note = f"turn {'right' if desired > 0 else 'left'}: not finished ({ahead:.0f} ahead)"
        remembered = max(self._clearance)
        where = int(np.argmax(self._clearance)) * 15
        smell_ahead = apple is None or gap_to(0.0, apple[0]) <= 50.0
        if ahead >= 12.0 and smell_ahead and ahead_trail < 2.2:
            forward = float(np.clip(0.55 + (ahead - 12.0) / 28.0, 0.55, 1.0))
            turn = float(np.clip(signed / 70.0, -0.45, 0.45))
            self._steer_sign = 0
            self._steer_ahead = ahead
            smell = "" if apple is None else f"; apple {apple[1]:.0f} studs at {apple[0]:.0f}°"
            note = f"forward: space is ahead ({ahead:.0f} studs)"
            self._steer_note = f"{note}; remembers {remembered:.0f} studs toward {where:.0f}°{smell}"
            if not self._attempts or self._attempts[-1] != note:
                self._attempts.append(note)
                del self._attempts[:-6]
            return forward, turn, ahead
        self._steer_sign = desired
        self._steer_ahead = ahead
        if note is None:
            side = "right" if desired > 0 else "left"
            if apple is None:
                note = f"turn {side}: toward remembered space ({ahead:.0f} ahead)"
            else:
                note = f"turn {side}: toward the apple smell ({ahead:.0f} ahead)"
        if not self._attempts or self._attempts[-1] != note:
            self._attempts.append(note)
            del self._attempts[:-6]
        smell = "" if apple is None else f"; apple {apple[1]:.0f} studs at {apple[0]:.0f}°"
        self._steer_note = f"{note}; remembers {remembered:.0f} studs toward {where:.0f}°{smell}"
        forward = -0.15 if ahead < 3.0 else 0.08
        return forward, float(desired), ahead

    def see(self, payload: dict) -> dict:
        objects = list(payload.get("objects") or [])
        smells = list(payload.get("smells") or [])
        combined = objects + smells
        poke = bool(payload.get("poke"))
        altitude = float(payload.get("altitude") or 3.0)
        airborne = bool(payload.get("airborne")) or altitude > 4.5
        attract, repel = _chemosense(combined)
        bout = self._pick_bout(poke, airborne, attract, repel)
        inject = self.eyes.inject(*self._scene(combined, poke))
        spike_count = 0
        rates = {
            "DNg100": 0.0,
            "MDN": 0.0,
            "DNa02_L": 0.0,
            "DNa02_R": 0.0,
            "DNp01": 0.0,
            "DN": 0.0,
            "DN_L": 0.0,
            "DN_R": 0.0,
        }
        features = None
        steps = 8
        fired_chunks: list[np.ndarray] = []
        for _ in range(steps):
            fired = self.brain.step(inject=inject)
            fired_chunks.append(np.asarray(fired, dtype=np.int64))
            features = self.trace.observe(fired)
            spike_count += int(getattr(fired, "size", 0))
            rates["DNg100"] += _rate(self.forward_idx, fired)
            rates["MDN"] += _rate(self.back_idx, fired)
            rates["DNa02_L"] += _rate(self.steer_l, fired)
            rates["DNa02_R"] += _rate(self.steer_r, fired)
            rates["DNp01"] += _rate(self.escape_idx, fired)
            rates["DN"] += _rate(self.dn, fired)
            rates["DN_L"] += _rate(self.dn_l, fired)
            rates["DN_R"] += _rate(self.dn_r, fired)
        for key in rates:
            rates[key] /= steps
        self._remember_preview(fired_chunks)

        taught = teacher_action(
            combined,
            poke,
            altitude=altitude,
            airborne=airborne,
            bout=bout,
        )
        ring = self._steer_from_ring(payload.get("distances"), payload.get("pose"), smells)
        ring_ahead = None
        if ring is not None:
            ring_forward, ring_turn, ring_ahead = ring
            apple = self._apple_from(smells)
            if apple is not None and apple[1] >= 6.0 and ring_ahead >= 10 and abs(ring_turn) < 0.6:
                gap = min(apple[0], 360.0 - apple[0])
                if gap < 40.0:
                    signed = apple[0] if apple[0] <= 180.0 else apple[0] - 360.0
                    ring_turn = float(np.clip(0.5 * ring_turn + 0.5 * np.tanh(signed / 40.0), -1, 1))
                    ring_forward = max(ring_forward, 0.55)
            taught = np.array(
                [ring_forward, ring_turn, float(taught[2]), float(taught[3]), float(taught[4])],
                np.float32,
            )
        if features is not None:
            self._X.append(features.astype(np.float32))
            self._y.append(taught)
            self.samples += 1
            if len(self._X) > 500:
                self._X = self._X[-500:]
                self._y = self._y[-500:]
            if self.samples >= 80 and self.samples % 40 == 0:
                self._maybe_fit()

        native_forward = float(
            np.tanh(8.0 * (rates["DNg100"] - rates["MDN"]) + 5.0 * rates["DN"])
        )
        native_turn = float(
            np.tanh(
                10.0 * (rates["DNa02_R"] - rates["DNa02_L"])
                + 5.0 * (rates["DN_R"] - rates["DN_L"])
            )
        )
        native_jump = rates["DNp01"]
        native_fly = 0.0
        native_up = 0.0
        native = np.array(
            [native_forward, native_turn, native_jump, native_fly, native_up],
            np.float32,
        )

        mix = 0.0
        wall_close = any(
            _is_wall(obj) and float(obj.get("distance") or 99) < 10 for obj in combined
        )
        # The ring is the incentive to enter open space. Neurons still pull.
        raw = 0.85 * native + 0.15 * taught
        if ring is not None:
            raw = 0.35 * native + 0.65 * taught
        if wall_close or (ring_ahead is not None and ring_ahead < 12):
            raw = 0.2 * native + 0.8 * taught

        self._ema["forward"] = 0.35 * self._ema["forward"] + 0.65 * float(raw[0])
        self._ema["turn"] = 0.3 * self._ema["turn"] + 0.7 * float(raw[1])
        self._ema["jump"] = 0.65 * self._ema["jump"] + 0.35 * float(raw[2])
        self._ema["fly"] = 0.0
        self._ema["up"] = 0.0

        source = f"MaleCNS+{bout}"
        return {
            "forward": float(np.clip(self._ema["forward"], -1, 1)),
            "turn": float(np.clip(self._ema["turn"], -1, 1)),
            "jump": bool(self._ema["jump"] > 0.4 or poke),
            "fly": float(np.clip(self._ema["fly"], 0, 1)),
            "up": float(np.clip(self._ema["up"], -1, 1)),
            "bout": bout,
            "source": source,
            "spikes": spike_count,
            "samples": self.samples,
            "trained": mix,
            "memory": self._steer_note,
            "neurons": rates,
            "t": time.time(),
        }

    def _maybe_fit(self) -> None:
        if self._fitting or len(self._X) < 80:
            return
        X = np.stack(self._X)
        y = np.stack(self._y)
        self._fitting = True

        def work() -> None:
            try:
                model = Readout.fit(
                    X,
                    y,
                    kind="ridge",
                    components=(5, 20),
                    lambdas=(0.1, 1.0, 10.0),
                )
                with self._fit_lock:
                    self._readout = model
                model.save(READOUT_PATH)
                print(
                    f"trained Roblox readout on {len(X)} samples, "
                    f"k={model.components} cv={model.cv_score:.3f}"
                )
            except Exception as exc:
                print("readout fit failed:", exc)
            finally:
                self._fitting = False

        threading.Thread(target=work, daemon=True).start()

    def _scene(self, objects: list[dict], poke: bool) -> tuple:
        player = None
        fruit = None
        shots = []
        threat = 0.4 if poke else 0.0
        for obj in objects:
            dx = float(obj.get("dx") or 0.0)
            size = float(obj.get("size") or 4.0)
            distance = float(obj.get("distance") or 50.0)
            if _is_repel(obj):
                threat = max(threat, min(1.0, (1.0 - distance / 16.0) * 1.35))
                shots.append((str(obj.get("name") or "stench"), dx, max(size, 8.0)))
            elif _is_fruit(obj):
                if fruit is None:
                    fruit = (dx, size)
            elif _is_player(obj):
                if player is None:
                    player = (dx, size)
            else:
                shots.append((str(obj.get("name") or "obj"), dx, size))
            if distance < 10 and not _is_wall(obj) and not _is_fruit(obj):
                threat = max(threat, 1.0 - distance / 10.0)
        opp = fruit or player
        return opp, shots, threat
