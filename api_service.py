"""Transport-independent local API; project inputs are read-only."""
from __future__ import annotations
import json
import math
import os
from pathlib import Path
import tempfile
import threading
import uuid
from urllib.parse import parse_qs, urlsplit
from progress import get_progress, parse_tasks, read_document, source_path
from discovery import connect_discovered, discover_projects, find_task_files, primary_ids
from read_summary import load_summary

LOCK = threading.RLock()


class MissingResource(LookupError):
    pass


def read_config(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_config(path, config):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".projects-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(config, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class LocalAPI:
    def __init__(self, config_path, authorized_roots=None, registries=None, activity_reader=None):
        self.config_path = Path(config_path)
        self.authorized_roots = None if authorized_roots is None else tuple(Path(p).resolve() for p in authorized_roots)
        self.registries = registries or {}
        self.activity_reader = activity_reader

    def authorize(self, root):
        root = Path(root).expanduser().resolve()
        if self.authorized_roots is not None and not any(root.is_relative_to(grant) for grant in self.authorized_roots):
            raise PermissionError("请先授权访问该项目目录")
        return root

    def discovery_options(self, provider):
        if self.authorized_roots is None:
            return {}
        return {"registry_file": self.registries.get(provider), "authorized_roots": self.authorized_roots}

    def request(self, method, path, payload=None):
        try:
            url = urlsplit(path)
            if url.scheme or url.netloc or not url.path.startswith("/api/"):
                raise ValueError("请求路径不正确")
            if method not in {"GET", "POST"}:
                return 405, {"error": "不支持的请求方法"}
            with LOCK:
                config = read_config(self.config_path)
                if method == "GET":
                    return 200, self.read(config, url.path, parse_qs(url.query))
                if not isinstance(payload, dict):
                    raise ValueError("请求格式不正确")
                if len(json.dumps(payload, ensure_ascii=False).encode()) >= 64000:
                    raise ValueError("请求大小不正确")
                if url.query:
                    raise ValueError("请求路径不正确")
                if url.path == "/api/projects":
                    self.authorize(str(payload.get("root", "")))
                if url.path in {"/api/sources", "/api/estimates"}:
                    project = next((p for p in config["projects"] if p["id"] == payload.get("project")), None)
                    if project is None:
                        raise ValueError("项目不存在")
                    self.authorize(project["root"])
                if url.path == "/api/connections":
                    candidates = discover_projects(payload.get("provider"), config, **self.discovery_options(payload.get("provider")))["projects"]
                    candidate = next((p for p in candidates if p["id"] == payload.get("project")), None)
                    if candidate is None:
                        raise ValueError("该项目目录已不可用，请刷新项目列表")
                    self.authorize(candidate["root"])
                result = self.mutate(config, url.path, payload)
                write_config(self.config_path, config)
                return 200, result
        except MissingResource as error:
            return 404, {"error": str(error)}
        except FileNotFoundError:
            return 422, {"error": "文件不存在或已移动，请检查项目路径和任务清单"}
        except PermissionError as error:
            return (403, {"error": str(error)}) if str(error) == "请先授权访问该项目目录" else (422, {"error": "无法读取文件，请检查文件权限"})
        except (OSError, ValueError, KeyError, TypeError) as error:
            return 422, {"error": str(error)}

    def read(self, config, endpoint, query):
        if endpoint == "/api/preferences":
            return {"language": config.get("language", "auto")}
        if endpoint == "/api/projects":
            return {"projects": [{"id": p["id"], "name": p["name"]} for p in config["projects"]]}
        if endpoint == "/api/discovery":
            provider = query.get("provider", [""])[0]
            return discover_projects(provider, config, **self.discovery_options(provider))
        if endpoint == "/api/native/connection-target" and self.authorized_roots is not None:
            provider = query.get("provider", [""])[0]
            candidate = next((p for p in discover_projects(provider, config, **self.discovery_options(provider))["projects"] if p["id"] == query.get("project", [None])[0]), None)
            if candidate is None:
                raise ValueError("该项目目录已不可用，请刷新项目列表")
            return {"root": candidate["root"]}
        if endpoint == "/api/summary":
            return load_summary(self.config_path, query.get("project", [None])[0], authorize=self.authorize)
        if endpoint not in {"/api/progress", "/api/sources", "/api/document"}:
            raise MissingResource("未找到")
        project = next((p for p in config["projects"] if p["id"] == query.get("project", [None])[0]), None)
        if project is None:
            raise MissingResource("项目不存在")
        root = self.authorize(project["root"])
        if endpoint == "/api/document":
            relative = query.get("file", [""])[0]
            return {"file": relative, "text": read_document(source_path(root, relative))}
        if endpoint == "/api/sources":
            choices = find_task_files(root)
            return {"selected": project.get("tasksFile") or (choices[0]["file"] if choices else None), "choices": choices}
        return get_progress(project, activity_reader=self.activity_reader)

    def mutate(self, config, endpoint, payload):
        if endpoint == "/api/preferences":
            language = payload.get("language")
            if language not in ("auto", "en", "zh", "fr"):
                raise ValueError("不支持的界面语言")
            config["language"] = language
            result = {"language": language}
        elif endpoint == "/api/connections":
            result = connect_discovered(config, payload.get("provider"), payload.get("project"), **self.discovery_options(payload.get("provider")))
        elif endpoint == "/api/projects/remove":
            identity = payload.get("project")
            if not isinstance(identity, str) or not identity.strip():
                raise ValueError("请选择要移除的项目")
            index = next((i for i, p in enumerate(config["projects"]) if p["id"] == identity), None)
            if index is None:
                raise ValueError("项目不存在")
            config["projects"].pop(index)
            result = {"removed": identity, "projects": [{"id": p["id"], "name": p["name"]} for p in config["projects"]]}
        elif endpoint == "/api/sources":
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
        elif endpoint == "/api/projects":
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
            get_progress(project, include_context=False)
            config["projects"].append(project)
            result = {"id": project["id"]}
        elif endpoint == "/api/estimates":
            project = next((p for p in config["projects"] if p["id"] == payload.get("project")), None)
            if project is None:
                raise ValueError("项目不存在")
            allowed_ids = {task["id"] for task in get_progress(project, include_context=False)["primary"] if not task["done"]}
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
            raise MissingResource("未找到")
        return result
