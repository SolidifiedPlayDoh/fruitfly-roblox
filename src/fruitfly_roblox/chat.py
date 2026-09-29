"""Short fly-voice replies via local Ollama llama3.2."""

from __future__ import annotations

import json
import urllib.error
import urllib.request

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL = "llama3.2"

SYSTEM = (
    "You are a living fruit fly (Drosophila). Tiny body, huge compound eyes, "
    "always tasting air with your feet. You are not an assistant. "
    "Reply in 2 to 8 words only. Sensory, twitchy, insect. "
    "Words like: sweet, rot, wind, shadow, buzz, sticky, bright, flee. "
    "Never mention AI, models, Roblox, computers, or being a chatbot. "
    "A huge warm moving thing may be nearby. Pineapple stink is death. Ripe fruit is yes."
)


def _clip(text: str) -> str:
    text = " ".join((text or "").strip().split())
    text = text.strip("\"'`")
    if not text:
        return "..."
    parts = text.replace("!", ".").split(".")
    text = parts[0].strip() or text
    words = text.split()
    if len(words) > 8:
        text = " ".join(words[:8])
    return text[:72]


class FlyTalk:
    def __init__(self, model: str = MODEL) -> None:
        self.model = model
        self._history: list[dict[str, str]] = []

    def reply(self, payload: dict, state: dict | None = None) -> dict:
        text = str((payload or {}).get("text") or "")
        text = " ".join(text.strip().split())[:240]
        if not text:
            return {"reply": "?", "ok": False, "error": "empty"}
        state = state or {}
        bout = state.get("bout") or "rest"
        context = (
            f"Body now: {bout}. "
            f"thrust={float(state.get('forward') or 0):.2f} "
            f"wings={float(state.get('fly') or 0):.2f} "
            f"up={float(state.get('up') or 0):.2f}. "
            f"spikes={state.get('spikes') or 0}."
        )
        user = f"{context}\nBig thing said: {text}"
        messages = [{"role": "system", "content": SYSTEM}]
        messages.extend(self._history[-6:])
        messages.append({"role": "user", "content": user})
        payload = {
            "model": self.model,
            "stream": False,
            "options": {"temperature": 0.95, "num_predict": 36, "top_p": 0.9},
            "messages": messages,
        }
        req = urllib.request.Request(
            OLLAMA_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as exc:
            return {"reply": "brain-mouth quiet", "ok": False, "error": str(exc)}
        except TimeoutError:
            return {"reply": "too much air", "ok": False, "error": "timeout"}
        raw = ""
        msg = data.get("message") if isinstance(data, dict) else None
        if isinstance(msg, dict):
            raw = str(msg.get("content") or "")
        reply = _clip(raw)
        self._history.append({"role": "user", "content": text})
        self._history.append({"role": "assistant", "content": reply})
        if len(self._history) > 12:
            self._history = self._history[-12:]
        return {"reply": reply, "ok": True, "model": self.model}
