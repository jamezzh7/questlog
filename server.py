#!/usr/bin/env python3
"""Local-only companion service. All project sources are read-only."""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from progress import get_progress, parse_tasks, read_document, source_path
from discovery import connect_discovered, discover_projects, find_task_files, primary_ids

BASE = Path(__file__).resolve().parent
LOCK = threading.Lock()


def read_config(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_config(path, config):
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix=".projects-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(config, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


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
        try:
            config = read_config(self.server.config_path)
            if url.path == "/api/preferences":
                return self.respond(200, {"language": config.get("language", "auto")})
            if url.path == "/api/projects":
                return self.respond(200, {"projects": [{"id": p["id"], "name": p["name"]} for p in config["projects"]]})
            if url.path == "/api/discovery":
                provider = parse_qs(url.query).get("provider", [""])[0]
                return self.respond(200, discover_projects(provider, config))
            if url.path in {"/api/progress", "/api/sources", "/api/document"}:
                project_id = parse_qs(url.query).get("project", [None])[0]
                project = next((p for p in config["projects"] if p["id"] == project_id), None)
                if not project:
                    return self.respond(404, {"error": "项目不存在"})
                if url.path == "/api/document":
                    relative = parse_qs(url.query).get("file", [""])[0]
                    path = source_path(Path(project["root"]).expanduser().resolve(), relative)
                    return self.respond(200, {"file": relative, "text": read_document(path)})
                if url.path == "/api/sources":
                    choices = find_task_files(project["root"])
                    selected = project.get("tasksFile") or (choices[0]["file"] if choices else None)
                    return self.respond(200, {"selected": selected, "choices": choices})
                return self.respond(200, get_progress(project))
            filename = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/i18n.js": "i18n.js", "/style.css": "style.css", "/icons.png": "icons.png", "/scene.svg": "scene.svg", "/favicon.svg": "favicon.svg"}.get(url.path)
            if not filename:
                return self.respond(404, {"error": "未找到"})
            mime = "text/html; charset=utf-8" if filename.endswith(".html") else "text/css; charset=utf-8" if filename.endswith(".css") else "text/javascript; charset=utf-8" if filename.endswith(".js") else "image/png" if filename.endswith(".png") else "image/svg+xml"
            return self.respond(200, (BASE / "public" / filename).read_bytes(), mime)
        except FileNotFoundError:
            return self.respond(422, {"error": "文件不存在或已移动，请检查项目路径和任务清单"})
        except PermissionError:
            return self.respond(422, {"error": "无法读取文件，请检查文件权限"})
        except (OSError, ValueError, KeyError) as error:
            return self.respond(422, {"error": str(error)})

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
            if not isinstance(payload, dict):
                raise ValueError("请求格式不正确")
            with LOCK:
                config = read_config(self.server.config_path)
                if self.path == "/api/preferences":
                    language = payload.get("language")
                    if language not in ("auto", "en", "zh", "fr"):
                        raise ValueError("不支持的界面语言")
                    config["language"] = language
                    result = {"language": language}
                elif self.path == "/api/connections":
                    result = connect_discovered(config, payload.get("provider"), payload.get("project"))
                elif self.path == "/api/projects/remove":
                    identity = payload.get("project")
                    if not isinstance(identity, str) or not identity.strip():
                        raise ValueError("请选择要移除的项目")
                    index = next((i for i, p in enumerate(config["projects"]) if p["id"] == identity), None)
                    if index is None:
                        raise ValueError("项目不存在")
                    config["projects"].pop(index)
                    result = {"removed": identity, "projects": [{"id": p["id"], "name": p["name"]} for p in config["projects"]]}
                elif self.path == "/api/sources":
                    project = next((p for p in config["projects"] if p["id"] == payload.get("project")), None)
                    if project is None:
                        raise ValueError("项目不存在")
                    relative = payload.get("file")
                    if not isinstance(relative, str) or not relative.strip():
                        raise ValueError("请选择任务文档")
                    root = Path(project["root"]).expanduser().resolve()
                    path = source_path(root, relative.strip())
                    relative = str(path.relative_to(root))
                    tasks = parse_tasks(read_document(path))
                    # Same-source saves preserve a manually defined primary scope.
                    previous = project.get("tasksFile")
                    previous_ids = project.get("primaryIds", [])
                    if not previous and project.get("autoTasks"):
                        choices = find_task_files(root)
                        if choices:
                            previous, previous_ids = choices[0]["file"], choices[0]["primaryIds"]
                    if relative != previous:
                        scopes = project.setdefault("planSettings", {})
                        if previous:
                            scopes[previous] = {key: project.get(key, [] if key == "primaryIds" else {})
                                                for key in ("primaryIds", "dependencies", "estimates")}
                            scopes[previous]["primaryIds"] = previous_ids
                        project.update(scopes.get(relative, {"primaryIds": primary_ids(tasks), "dependencies": {}, "estimates": {}}))
                    elif not project.get("tasksFile"):
                        project["primaryIds"] = primary_ids(tasks)
                    project.update({"tasksFile": relative, "autoTasks": False})
                    get_progress(project, include_context=False)
                    result = {"file": relative}
                elif self.path == "/api/projects":
                    root = Path(str(payload.get("root", ""))).expanduser()
                    if not root.is_absolute() or not root.is_dir():
                        raise ValueError("请输入存在的项目绝对路径")
                    name = str(payload.get("name", "")).strip()[:80]
                    if not name:
                        raise ValueError("请填写项目名称")
                    relative = str(payload.get("tasksFile", "")).strip()
                    if relative:
                        source_path(root, relative)
                    project = {"id": uuid.uuid4().hex[:12], "name": name, "root": str(root.resolve()),
                               "tasksFile": relative or None, "autoTasks": not bool(relative), "primaryIds": [], "dependencies": {}, "estimates": {}, "hoursPerDay": 4}
                    get_progress(project)
                    config["projects"].append(project)
                    result = {"id": project["id"]}
                elif self.path == "/api/estimates":
                    project = next((p for p in config["projects"] if p["id"] == payload.get("project")), None)
                    if project is None:
                        raise ValueError("项目不存在")
                    allowed_ids = {task["id"] for task in get_progress(project)["primary"] if not task["done"]}
                    estimates = payload.get("estimates", {})
                    if not isinstance(estimates, dict):
                        raise ValueError("估算格式不正确")
                    for task_id, bounds in estimates.items():
                        if task_id not in allowed_ids or not isinstance(bounds, list) or len(bounds) != 2:
                            raise ValueError("估算任务或范围不正确")
                        if any(isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) for n in bounds):
                            raise ValueError("工时必须为有效数字")
                        if not 0 <= bounds[0] <= bounds[1] <= 10000:
                            raise ValueError("工时范围应为 0–10000，且下限不大于上限")
                    hours = payload.get("hoursPerDay", 4)
                    if isinstance(hours, bool) or not isinstance(hours, (int, float)) or not math.isfinite(hours) or not 0 < hours <= 24:
                        raise ValueError("每日工时应大于 0 且不超过 24")
                    project["estimates"], project["hoursPerDay"] = estimates, hours
                    result = {"ok": True}
                else:
                    return self.respond(404, {"error": "未找到"})
                write_config(self.server.config_path, config)
            return self.respond(200, result)
        except FileNotFoundError:
            return self.respond(422, {"error": "文件不存在或已移动，请检查项目路径和任务清单"})
        except PermissionError:
            return self.respond(422, {"error": "无法读取文件，请检查文件权限"})
        except (OSError, ValueError, KeyError, TypeError) as error:
            return self.respond(422, {"error": str(error)})


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
