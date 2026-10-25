#!/usr/bin/env python3
"""Local-only companion service. All project sources are read-only."""
from __future__ import annotations

import argparse
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
from api_service import LocalAPI, read_config, write_config

BASE = Path(__file__).resolve().parent


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def valid_host(self):
        return self.headers.get("Host") in {f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}"}

    def respond(self, status, value, mime="application/json; charset=utf-8"):
        data = json.dumps(value, ensure_ascii=False).encode() if not isinstance(value, bytes) else value
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.valid_host():
            return self.respond(403, {"error": "仅允许本机访问"})
        url = urlsplit(self.path)
        if url.path.startswith("/api/"):
            return self.respond(*LocalAPI(self.server.config_path).request("GET", self.path))
        assets = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/appearance.js": "appearance.js", "/i18n.js": "i18n.js", "/style.css": "style.css", "/icons.png": "icons.png", "/scene.svg": "scene.svg", "/favicon.svg": "favicon.svg"}
        filename = assets.get(url.path)
        if not filename:
            return self.respond(404, {"error": "未找到"})
        suffix = Path(filename).suffix
        mime = {".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".svg": "image/svg+xml"}[suffix]
        return self.respond(200, (BASE / "public" / filename).read_bytes(), mime + ("; charset=utf-8" if suffix in {".html", ".css", ".js"} else ""))

    def do_POST(self):
        origin = self.headers.get("Origin")
        allowed = {f"http://127.0.0.1:{self.server.server_port}", f"http://localhost:{self.server.server_port}"}
        if not self.valid_host() or origin not in allowed or self.headers.get("Content-Type") != "application/json":
            return self.respond(403, {"error": "请求来源不匹配"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length < 64000:
                raise ValueError("请求大小不正确")
            payload = json.loads(self.rfile.read(length))
        except (ValueError, TypeError) as error:
            return self.respond(422, {"error": str(error)})
        self.respond(*LocalAPI(self.server.config_path).request("POST", self.path, payload))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4318)
    parser.add_argument("--config", type=Path, default=BASE / "projects.json")
    parser.add_argument("--parent-pid", type=int)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.config_path = args.config.resolve()
    if args.parent_pid:
        def parent_watchdog():
            while True:
                time.sleep(2)
                if os.getppid() != args.parent_pid:
                    os._exit(0)
        threading.Thread(target=parent_watchdog, daemon=True).start()
    print(json.dumps({"url": f"http://127.0.0.1:{server.server_port}"}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
