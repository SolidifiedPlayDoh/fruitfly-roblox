"""Jev plays the Roblox place as its own character. The fruit fly is a separate body."""

from __future__ import annotations

import json
import math
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock, Thread

DECISIONS_URL = "https://openrouter.ai/api/alpha/decisions"
DEFAULT_MODEL = "typesafe/jev-1.13"
SPEND_CAP = 2.0

# Positive turn is the rig's right. The place already applies that as a strafe,
# and AutoRotate faces the rig along the move.
DRIVES: dict[str, tuple[float, float, bool]] = {
    "forward": (1.0, 0.0, False),
    "turn_left": (0.05, -1.0, False),
    "turn_right": (0.05, 1.0, False),
    "back": (-0.6, 0.0, False),
    "jump": (0.7, 0.0, True),
    "idle": (0.0, 0.0, False),
}

QUESTIONS = {
    "move": {
        "type": "choice",
        "instructions": (
            "You are Jev, a friendly Roblox player. "
            "Walk up to the other player and hang out with them, the way a player joins a friend. "
            "The fruit fly is not you. Ignore it. "
            "If the other player is left or behind left, turn left. "
            "If they are right, turn right. "
            "If they are ahead and not close, walk to them. "
            "If they are ahead and close, stop next to them. A jump is a hello. "
            "If a wall is close and ahead, turn."
        ),
        "criteria": {
            "turn_left": "The other player is left, behind, or behind left. Turn left toward them.",
            "turn_right": "The other player is right or behind right. Turn right toward them.",
            "forward": "The other player is ahead, and not close yet. Walk up to them.",
            "idle": "The other player is close. Stand with them.",
            "jump": "The other player is close. Hop once to say hello.",
            "back": "A wall is in your face, or you are overlapping the other player.",
        },
    }
}

MAZE_QUESTIONS = {
    "move": {
        "type": "choice",
        "instructions": (
            "You are Jev in a maze. A ripe apple is at the end. Apple smell is good. "
            "Reach the apple and eat it. "
            "apple_degrees is the smell. 0 is ahead, 90 is right, 180 is behind, 270 is left. "
            "distances_studs is a full circle of how far you can move. 48 is the farthest. "
            "Prefer the open direction closest to the apple over a longer corridor that points away from it. "
            "Walking into open space toward the smell is success. Rotating in place is failure. "
            "memory lists what you just tried and whether the space ahead opened or closed. "
            "apple_degrees under 40 or over 320 means the smell is ahead. If ahead_studs is 12 or more, walk. Do not turn. "
            "If the smell is left and that side is open, turn left. If it is right and that side is open, turn right. "
            "If the smell points through a wall, take the open direction closest to it. "
            "If the last turn succeeded or is not finished, repeat that same turn until the smell is ahead. Do not switch sides. "
            "A turn is not finished when the space is still beside you. "
            "If the last turn failed, do not repeat it. Turn the other way once. "
            "trail_ahead, trail_left, and trail_right are your own faint smell. "
            "fresh means new ground. faint means you passed once. heavy means you keep pacing the same place. "
            "Prefer a fresh opening toward the apple. A heavy trail ahead means do not walk that way again. "
            "You may still cross a faint trail if it is the only open way toward the apple. "
            "If the last two attempts are opposite turns, you are looping. "
            "Commit to the open fresh direction closest to the apple, then walk. "
            "The steps question is how many studs that walk should be. Do not choose farther than ahead_studs."
        ),
        "criteria": {
            "forward": "Ahead is 12 studs or more, the apple smell is ahead, and trail_ahead is fresh or faint. Walk a measured distance.",
            "turn_left": "The apple smell is on the left and that side is open, or trail_ahead is heavy and the left is fresher. Do not pick this if the last turn_left failed.",
            "turn_right": "The apple smell is on the right and that side is open, or trail_ahead is heavy and the right is fresher. Do not pick this if the last turn_right failed.",
            "back": "Ahead and both sides are only a few studs, behind is long, and turning failed. Go back.",
            "idle": "apple_studs is under 6. You reached the apple. Stop and eat it.",
            "jump": "You just reached the apple. One hop, then stop and eat it.",
        },
    },
    "steps": {
        "type": "score",
        "instructions": (
            "How far should this forward step be? "
            "Short if the opening is short or the trail ahead is faint. "
            "Long if the corridor toward the apple is clear and fresh. "
            "Never longer than ahead_studs."
        ),
        "criteria": [
            "4 studs, a short step",
            "8 studs",
            "12 studs",
            "18 studs",
            "24 studs",
            "32 studs, a long clear corridor",
        ],
    },
}

STEP_STUDS = (4, 8, 12, 18, 24, 32)


def _range_word(distance: float) -> str:
    if distance < 8:
        return "close"
    if distance < 22:
        return "near"
    if distance < 45:
        return "far"
    return "distant"


def _where(dx: float) -> str:
    # Vision dx is object-space X times 6. Positive X is the rig's right.
    if dx > 8:
        return "right"
    if dx < -8:
        return "left"
    return "ahead"


def _phrase(entry: dict) -> tuple[float, str] | None:
    if not isinstance(entry, dict):
        return None
    try:
        distance = float(entry.get("distance") or 99)
    except (TypeError, ValueError):
        return None
    name = str(entry.get("name") or entry.get("kind") or "something")
    if entry.get("where"):
        where = str(entry["where"])
    else:
        try:
            where = _where(float(entry.get("dx") or 0))
        except (TypeError, ValueError):
            where = "nearby"
    if entry.get("visible") is False:
        sight = ", out of sight"
    elif entry.get("visible") is True:
        sight = ", in sight"
    else:
        sight = ""
    return distance, f"{name} is {where}, {_range_word(distance)}{sight}"


def _ring(maze: dict) -> list[tuple[int, int, float]]:
    raw = maze.get("distances")
    samples: list[tuple[int, int]] = []
    if not isinstance(raw, list):
        return samples
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            bearing = int(round(float(item.get("bearing")))) % 360
            studs = int(round(float(item.get("studs"))))
            trail = float(item.get("trail") or 0)
        except (TypeError, ValueError):
            continue
        samples.append((bearing, studs, trail))
    samples.sort(key=lambda pair: pair[0])
    return samples


def _bearing_words(bearing: int) -> str:
    if bearing <= 20 or bearing >= 340:
        return "ahead"
    if bearing < 180:
        return f"{bearing} degrees right"
    return f"{360 - bearing} degrees left"


def _trail_word(value: float) -> str:
    if value < 0.45:
        return "fresh"
    if value < 2.0:
        return "faint"
    return "heavy"


def _trail_at(samples: list[tuple[int, int, float]], bearing: int) -> str:
    best = 0.0
    best_gap = 999
    for sample_bearing, _studs, trail in samples:
        gap = abs(sample_bearing - bearing) % 360
        gap = min(gap, 360 - gap)
        if gap < best_gap:
            best_gap = gap
            best = trail
    return _trail_word(best)


def _clearest(samples: list[tuple[int, int]]) -> tuple[int, int] | None:
    if not samples:
        return None
    return max(samples, key=lambda pair: pair[1])


def maze_state(payload: dict, last_move: str, memory: list[str], last_result: str) -> dict:
    maze = payload.get("maze") if isinstance(payload.get("maze"), dict) else {}
    samples = _ring(maze)
    ahead = next((studs for bearing, studs, _trail in samples if bearing == 0), None)
    best = _clearest([(bearing, studs) for bearing, studs, _trail in samples])
    state: dict = {
        "goal": "follow the ripe apple smell to the end of the maze and eat the apple",
        "sense": "studs before contact. 0 is ahead, 90 is right, 180 is behind, 270 is left. 48 is the farthest.",
        "distances_studs": {str(bearing): studs for bearing, studs, _trail in samples},
        "ahead_studs": ahead,
        "behind_studs": next((studs for bearing, studs, _trail in samples if bearing == 180), None),
        "clearest_bearing": None if best is None else best[0],
        "clearest_studs": None if best is None else best[1],
        "clearest": "unknown" if best is None else _bearing_words(best[0]),
        "exit": str(maze.get("exit") or "hidden"),
        "apple": str(maze.get("apple") or "ripe apple, the smell is good"),
        "trail_ahead": _trail_at(samples, 0),
        "trail_right": _trail_at(samples, 90),
        "trail_left": _trail_at(samples, 270),
        "trail_behind": _trail_at(samples, 180),
        "last_move": last_move or "none",
        "last_result": last_result,
        "memory": memory or ["no attempts yet"],
    }
    for key in ("exit_degrees", "exit_studs", "apple_degrees", "apple_studs"):
        try:
            if maze.get(key) is not None:
                state[key] = int(round(float(maze[key])))
        except (TypeError, ValueError):
            continue
    return state


def world_state(payload: dict) -> dict:
    """Short scene in words. Jev is a player looking at the place."""
    ranked: list[tuple[float, str]] = []
    seen: set[str] = set()
    raw = list(payload.get("characters") or []) + list(payload.get("objects") or [])
    for entry in raw:
        phrased = _phrase(entry)
        if phrased is None or phrased[1] in seen:
            continue
        seen.add(phrased[1])
        ranked.append(phrased)
    ranked.sort(key=lambda item: item[0])
    seen_lines = [line for _, line in ranked[:5]]
    return {
        "you": "in the air" if payload.get("airborne") else "standing",
        "seen": seen_lines or "nothing nearby",
    }


def _studs_from_score(answer: dict | None, ahead: int | None) -> int:
    index = 2
    if isinstance(answer, dict):
        try:
            if answer.get("score") is not None:
                index = int(round(float(answer["score"])))
            else:
                probabilities = answer.get("probabilities")
                if isinstance(probabilities, dict) and probabilities:
                    best = max(probabilities, key=lambda key: float(probabilities[key] or 0))
                    index = int(best)
        except (TypeError, ValueError):
            index = 2
    index = max(0, min(len(STEP_STUDS) - 1, index))
    chosen = STEP_STUDS[index]
    if isinstance(ahead, int) and ahead > 0:
        chosen = min(chosen, max(4, ahead - 2))
    return chosen


def drive_from_choice(choice: str, confidence: float, probabilities: dict) -> dict:
    forward, turn, jump = DRIVES.get(choice, DRIVES["idle"])
    if choice not in DRIVES:
        choice = "idle"
    return {
        "forward": forward,
        "turn": turn,
        "jump": jump,
        "fly": 0.0,
        "up": 0.0,
        "bout": choice,
        "source": "jev",
        "choice": choice,
        "confidence": confidence,
        "probabilities": probabilities,
        "spikes": 0,
        "t": time.time(),
    }


class JevPilot:
    def __init__(
        self,
        api_key: str,
        *,
        model: str = DEFAULT_MODEL,
        hz: float = 4.0,
        timeout: float = 2.5,
    ) -> None:
        self.api_key = api_key
        self.model = model
        self.interval = 1.0 / max(hz, 0.2)
        self.timeout = timeout
        self._lock = Lock()
        self._last_call = 0.0
        self._inflight = False
        self.cap = SPEND_CAP
        self._session = 0.0
        self._account_usage = 0.0
        self._baseline: float | None = None
        self._calls = 0
        self._capped = False
        self._drive = drive_from_choice("idle", 0.0, {})
        self._drive["source"] = "jev-hold"
        self._attempts: list[str] = []
        self._pending: dict | None = None
        Thread(target=self._account_loop, daemon=True).start()

    def _pose_of(self, payload: dict) -> tuple[float, float] | None:
        pose = payload.get("pose")
        if not isinstance(pose, dict):
            return None
        try:
            return (float(pose["x"]), float(pose["z"]))
        except (TypeError, ValueError, KeyError):
            return None

    def _ahead_of(self, payload: dict) -> int | None:
        maze = payload.get("maze") if isinstance(payload.get("maze"), dict) else {}
        for bearing, studs, _trail in _ring(maze):
            if bearing == 0:
                return studs
        return None

    def _note_attempt(self, ahead: int | None, pose: tuple[float, float] | None) -> str:
        pending = self._pending
        if pending is None:
            return "none yet"
        moved = 0.0
        old = pending.get("pose")
        if pose is not None and isinstance(old, tuple):
            moved = math.hypot(pose[0] - old[0], pose[1] - old[1])
        before = pending.get("ahead")
        choice = str(pending.get("choice") or "idle")
        if isinstance(before, int) and ahead is not None and ahead >= before + 3:
            outcome = "succeeded, space ahead opened"
        elif isinstance(before, int) and ahead is not None and ahead <= before - 3:
            outcome = "failed, space ahead closed"
        elif choice == "forward" and moved >= 1.2:
            outcome = "succeeded, you walked into the space"
        elif choice == "forward" and moved < 0.6:
            outcome = "failed, forward did not move you"
        elif choice in ("turn_left", "turn_right") and isinstance(before, int) and ahead is not None and ahead > before:
            outcome = "succeeded, space ahead opened a little"
        elif choice in ("turn_left", "turn_right"):
            outcome = "not finished, the open space is still beside you"
        else:
            outcome = "no clear change"
        line = f"{choice}: {outcome}"
        if isinstance(before, int) and ahead is not None:
            line += f" (ahead {before}->{ahead}, moved {moved:.1f})"
        self._attempts.append(line)
        del self._attempts[:-6]
        return line

    def _remember_choice(self, choice: str, ahead: int | None, pose: tuple[float, float] | None) -> None:
        self._pending = {"choice": choice, "ahead": ahead, "pose": pose}

    def _shown_spend(self) -> float:
        if self._baseline is None:
            return self._session
        return max(self._account_usage, self._baseline + self._session)

    def _stamp(self, drive: dict) -> dict:
        out = dict(drive)
        out["spent"] = round(self._shown_spend(), 6)
        out["cap"] = self.cap
        return out

    def _account_loop(self) -> None:
        while True:
            self.refresh_account()
            time.sleep(8)

    def refresh_account(self) -> None:
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/key",
            headers={"Authorization": f"Bearer {self.api_key}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError):
            return
        info = data.get("data") if isinstance(data, dict) else None
        if not isinstance(info, dict):
            return
        try:
            usage = float(info.get("usage") or 0)
        except (TypeError, ValueError):
            return
        limit = info.get("limit")
        with self._lock:
            self._account_usage = usage
            if self._baseline is None:
                self._baseline = usage
            if isinstance(limit, (int, float)) and float(limit) > 0:
                self.cap = float(limit)

    def snapshot(self) -> dict:
        with self._lock:
            return self._stamp(self._drive)

    def see(self, payload: dict) -> dict:
        if payload.get("done"):
            with self._lock:
                if self._drive.get("source") != "jev-finished":
                    self._drive = drive_from_choice("idle", 1.0, {})
                    self._drive["source"] = "jev-finished"
                    self._drive["studs"] = 0
                    print("jev reached the apple and stopped spending", flush=True)
                return self._stamp(self._drive)
        now = time.monotonic()
        with self._lock:
            if self._shown_spend() >= self.cap:
                if not self._capped:
                    self._capped = True
                    self._drive = drive_from_choice("idle", 1.0, {})
                    self._drive["source"] = "jev-cap"
                    print(f"jev reached the ${self.cap:.2f} cap and stopped", flush=True)
                return self._stamp(self._drive)
            if self._inflight or now - self._last_call < self.interval:
                return self._stamp(self._drive)
            self._inflight = True
            self._last_call = now
        last_move = str(self._drive.get("choice") or "none")
        if isinstance(payload.get("maze"), dict):
            ahead_now = self._ahead_of(payload)
            pose_now = self._pose_of(payload)
            last_result = self._note_attempt(ahead_now, pose_now)
            state = maze_state(payload, last_move, list(self._attempts), last_result)
            questions = MAZE_QUESTIONS
        else:
            state = world_state(payload)
            questions = QUESTIONS
        try:
            answer, steps, cost = self._decide(state, questions)
        except (urllib.error.URLError, TimeoutError, OSError, RuntimeError) as exc:
            print(f"jev hold: {exc}", flush=True)
            with self._lock:
                self._inflight = False
                held = self._stamp(self._drive)
            held["source"] = "jev-hold"
            held["error"] = str(exc)
            return held
        choice = str(answer.get("choice") or "idle")
        try:
            confidence = float(answer.get("confidence") or 0)
        except (TypeError, ValueError):
            confidence = 0.0
        probabilities = answer.get("probabilities")
        if not isinstance(probabilities, dict):
            probabilities = {}
        drive = drive_from_choice(choice, confidence, probabilities)
        ahead_limit = state.get("ahead_studs") if isinstance(state.get("ahead_studs"), int) else None
        drive["studs"] = _studs_from_score(steps, ahead_limit) if drive["choice"] == "forward" else 0
        drive["cost"] = cost
        drive["inputs"] = state
        drive["watch"] = {
            "ahead": state.get("ahead_studs"),
            "apple_studs": state.get("apple_studs"),
            "apple_degrees": state.get("apple_degrees"),
            "trail": state.get("trail_ahead"),
            "last": state.get("last_result"),
            "clearest": state.get("clearest"),
        }
        if isinstance(payload.get("maze"), dict):
            self._remember_choice(drive["choice"], state.get("ahead_studs"), self._pose_of(payload))
        with self._lock:
            self._session += cost
            self._calls += 1
            calls = self._calls
            self._drive = drive
            self._inflight = False
            stamped = self._stamp(drive)
            spent = stamped["spent"]
        detail = state.get("seen")
        if detail is None and "ahead_studs" in state:
            detail = (
                f"ahead={state.get('ahead_studs')} clearest={state.get('clearest')} "
                f"{state.get('last_result')}"
            )
        print(
            f"jev {drive['choice']} {drive.get('studs') or 0}studs conf={confidence:.2f} ${cost:.6f}  total ${spent:.5f}  {detail}",
            flush=True,
        )
        if calls % 20 == 0:
            print(f"jev spent ${spent:.4f} over {calls} decisions", flush=True)
        return stamped

    def _decide(self, state: dict, questions: dict) -> tuple[dict, dict | None, float]:
        body = json.dumps(
            {"model": self.model, "state": state, "questions": questions}
        ).encode("utf-8")
        req = urllib.request.Request(
            DECISIONS_URL,
            data=body,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "http://127.0.0.1",
                "X-Title": "jev-roblox",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:240]
            raise RuntimeError(f"OpenRouter {exc.code}: {detail}") from exc
        if not isinstance(data, dict):
            raise RuntimeError("Jev returned a non-object")
        answers = data.get("answers")
        move = answers.get("move") if isinstance(answers, dict) else None
        if not isinstance(move, dict):
            raise RuntimeError("Jev response had no move answer")
        steps = answers.get("steps") if isinstance(answers, dict) else None
        if not isinstance(steps, dict):
            steps = None
        usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
        try:
            cost = float(usage.get("cost") or 0)
        except (TypeError, ValueError):
            cost = 0.0
        return move, steps, cost


class _ReuseServer(ThreadingHTTPServer):
    allow_reuse_address = True


def serve(pilot: JevPilot, host: str = "127.0.0.1", port: int = 8766) -> None:
    owner = pilot

    class Handler(BaseHTTPRequestHandler):
        def _send(self, payload: dict) -> None:
            raw = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self) -> None:  # noqa: N802
            path = (self.path or "/").split("?", 1)[0].rstrip("/") or "/"
            if path == "/obs/inputs":
                page = Path(__file__).resolve().parents[2] / "studio" / "obs" / "jev.html"
                try:
                    body = page.read_bytes()
                except OSError:
                    body = b"missing"
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self._send(owner.snapshot())

        def do_POST(self) -> None:  # noqa: N802
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b"{}"
            try:
                payload = json.loads(raw.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                payload = {}
            if not isinstance(payload, dict):
                payload = {}
            self._send(owner.see(payload))

        def log_message(self, format: str, *args) -> None:  # noqa: A003
            return

    try:
        httpd = _ReuseServer((host, port), Handler)
    except OSError as exc:
        raise SystemExit(f"Port {port} is already taken ({exc}).") from exc
    print(f"Jev listening on http://{host}:{port}/see", flush=True)
    print(f"OBS inputs on http://{host}:{port}/obs/inputs", flush=True)
    print(f"model {pilot.model} via OpenRouter, about {1 / pilot.interval:.1f} decisions/s", flush=True)
    print("Drives the grey Jev character. The fruit fly stays on port 8765.", flush=True)
    httpd.serve_forever()


def _load_dotenv() -> None:
    path = os.path.join(os.path.dirname(__file__), "..", "..", ".env")
    path = os.path.abspath(path)
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.readlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        name, value = line.split("=", 1)
        name = name.strip()
        value = value.strip().strip('"').strip("'")
        if name and name not in os.environ:
            os.environ[name] = value


def api_key_from_env() -> str:
    _load_dotenv()
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not key:
        raise SystemExit(
            "Set OPENROUTER_API_KEY. Jev is billed to that OpenRouter account."
        )
    return key
