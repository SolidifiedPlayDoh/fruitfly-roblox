from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from typing import Callable

OVERLAY_PATH = Path(__file__).resolve().parents[2] / "studio" / "obs" / "overlay.html"
BRAIN_PATH = Path(__file__).resolve().parents[2] / "studio" / "obs" / "brain.html"


class BrainHttp:
    def __init__(
        self,
        see: Callable[[dict], dict],
        chat: Callable[[dict, dict], dict] | None = None,
        host: str = "127.0.0.1",
        port: int = 8765,
        preview=None,
    ) -> None:
        self.see = see
        self.chat = chat
        self.host = host
        self.port = port
        self.preview = preview
        self._lock = Lock()
        self._last: dict = {"forward": 0, "turn": 0, "jump": False, "source": "idle"}
        self._httpd: ThreadingHTTPServer | None = None

    def start(self) -> None:
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def _send(self, payload: dict) -> None:
                body = json.dumps(payload).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _send_file(self, path: Path, content_type: str) -> None:
                try:
                    body = path.read_bytes()
                except OSError:
                    body = b"missing"
                    content_type = "text/plain"
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def _send_bytes(self, body: bytes, content_type: str) -> None:
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:  # noqa: N802
                path = (self.path or "/").split("?", 1)[0].rstrip("/") or "/"
                if path == "/obs":
                    self._send_file(OVERLAY_PATH, "text/html; charset=utf-8")
                    return
                if path == "/obs/brain":
                    self._send_file(BRAIN_PATH, "text/html; charset=utf-8")
                    return
                if path == "/obs/brain-layout" and owner.preview is not None:
                    self._send_bytes(owner.preview.preview_layout(), "application/octet-stream")
                    return
                if path == "/obs/brain-spikes" and owner.preview is not None:
                    self._send_bytes(owner.preview.preview_spikes(), "application/octet-stream")
                    return
                with owner._lock:
                    snapshot = dict(owner._last)
                self._send(snapshot)

            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b"{}"
                try:
                    payload = json.loads(raw.decode("utf-8") or "{}")
                except json.JSONDecodeError:
                    payload = {}
                if not isinstance(payload, dict):
                    payload = {}
                path = (self.path or "/").split("?", 1)[0]
                if path.rstrip("/").endswith("/chat"):
                    if owner.chat is None:
                        self._send({"reply": "...", "ok": False, "error": "no chat"})
                        return
                    with owner._lock:
                        snapshot = dict(owner._last)
                    self._send(owner.chat(payload, snapshot))
                    return
                drive = owner.see(payload)
                with owner._lock:
                    owner._last = drive
                self._send(drive)

            def log_message(self, format: str, *args) -> None:  # noqa: A003
                return

        self._httpd = ThreadingHTTPServer((self.host, self.port), Handler)
        print(f"MaleCNS listening on http://{self.host}:{self.port}/see", flush=True)
        print(f"OBS overlay on http://{self.host}:{self.port}/obs", flush=True)
        print(f"OBS brain on http://{self.host}:{self.port}/obs/brain", flush=True)
        print(f"Fly chat on http://{self.host}:{self.port}/chat (ollama llama3.2)", flush=True)
        self._httpd.serve_forever()
