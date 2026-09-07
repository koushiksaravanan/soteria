"""Soteria realtime log viewer — stdlib only, no deps.

Serves ui/static/index.html and streams NDJSON log lines over SSE.
Optionally tails `docker logs -f <container>` when ?source=container&name=X.

Usage:
  python3 ui/server.py [--port 8787] [--log ui/sample-records.ndjson]
  SOTERIA_LOG=~/.soteria/records.ndjson python3 ui/server.py --port 8787
  Open http://127.0.0.1:8787
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import subprocess
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

BASE = Path(__file__).resolve().parent
STATIC = BASE / "static"
DEFAULT_LOG = BASE / "sample-records.ndjson"


class Tailer:
    """Poll a growing NDJSON file and fan out lines to subscribers."""

    def __init__(self, path: Path):
        self.path = path
        self.subs: set[queue.Queue] = set()
        self.lock = threading.Lock()
        self.offset = 0
        if path.exists():
            self.offset = path.stat().st_size  # live-only; history via /api/events
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            try:
                if self.path.exists():
                    size = self.path.stat().st_size
                    if size < self.offset:  # rotated/truncated
                        self.offset = 0
                    if size > self.offset:
                        with open(self.path, "rb") as f:
                            f.seek(self.offset)
                            chunk = f.read(size - self.offset)
                            self.offset = size
                        for raw in chunk.splitlines():
                            line = raw.decode("utf-8", "replace").strip()
                            if line:
                                self._pub({"raw": line})
            except Exception as e:  # never kill the loop
                self._pub({"raw": json.dumps({"kind": "viewer.error", "level": "INFO", "summary": f"tail error: {e}", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})})
            time.sleep(0.5)

    def _pub(self, obj: dict):
        with self.lock:
            dead = []
            for q in self.subs:
                try:
                    q.put_nowait(obj)
                except Exception:
                    dead.append(q)
            for q in dead:
                self.subs.discard(q)

    def subscribe(self) -> queue.Queue:
        q: queue.Queue = queue.Queue(maxsize=1000)
        with self.lock:
            self.subs.add(q)
        return q

    def unsubscribe(self, q: queue.Queue):
        with self.lock:
            self.subs.discard(q)

    def last(self, n: int = 200) -> list[str]:
        try:
            with open(self.path, "rb") as f:
                lines = f.read().splitlines()[-n:]
            return [l.decode("utf-8", "replace") for l in lines if l.strip()]
        except FileNotFoundError:
            return []


def stream_docker_logs(name: str, out_q: queue.Queue, stop: threading.Event):
    """Push `docker logs -f` lines into out_q until stop is set."""
    try:
        p = subprocess.Popen(
            ["docker", "logs", "-f", "--tail", "100", name],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
        )
    except FileNotFoundError:
        out_q.put({"raw": json.dumps({"kind": "viewer.error", "level": "DENY", "summary": "docker binary not found", "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})})
        return
    assert p.stdout is not None
    try:
        for line in p.stdout:
            if stop.is_set():
                break
            line = line.rstrip("\n")
            if line:
                try:
                    out_q.put_nowait({"raw": line})
                except Exception:
                    pass
    finally:
        try:
            p.terminate()
        except Exception:
            pass


class Handler(SimpleHTTPRequestHandler):
    tailer: Tailer
    log_path: Path

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(STATIC), **kw)

    def log_message(self, *a):  # quiet
        pass

    def handle_error(self, request, client_address):
        import socket as _s
        import sys as _sys
        exc = _sys.exc_info()[1]
        # ignore benign disconnects from browsers/curl closing early
        if isinstance(exc, (ConnectionResetError, BrokenPipeError, _s.timeout)):
            return
        super().handle_error(request, client_address)

    def _send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/api/status":
            self._send_json({"log": str(self.log_path), "exists": self.log_path.exists()})
        elif u.path == "/api/events":
            qs = parse_qs(u.query)
            n = max(1, min(2000, int(qs.get("limit", ["200"])[0])))
            self._send_json({"lines": self.tailer.last(n)})
        elif u.path == "/api/events/stream":
            qs = parse_qs(u.query)
            source = qs.get("source", ["file"])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            if source == "container":
                name = qs.get("name", [""])[0]
                if not name:
                    self.wfile.write(b'data: {"raw": "{\\"kind\\":\\"viewer.error\\",\\"summary\\":\\"missing ?name=container\\"}"}\n\n')
                    return
                q: queue.Queue = queue.Queue(maxsize=1000)
                stop = threading.Event()
                threading.Thread(target=stream_docker_logs, args=(name, q, stop), daemon=True).start()
                try:
                    while True:
                        try:
                            obj = q.get(timeout=15)
                            self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
                        except queue.Empty:
                            self.wfile.write(b": ping\n\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass
                finally:
                    stop.set()
                return
            q = self.tailer.subscribe()
            try:
                while True:
                    try:
                        obj = q.get(timeout=15)
                        self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
                    except queue.Empty:
                        self.wfile.write(b": ping\n\n")
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                self.tailer.unsubscribe(q)
        else:
            if u.path == "/":
                self.path = "/index.html"
            super().do_GET()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--log", default=os.environ.get("SOTERIA_LOG", str(DEFAULT_LOG)))
    args = ap.parse_args()
    log_path = Path(os.path.expanduser(args.log))
    Handler.tailer = Tailer(log_path)
    Handler.log_path = log_path
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"soteria viewer: http://127.0.0.1:{args.port}  log={log_path}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
