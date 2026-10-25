"""On-demand discovery from local project registries, never conversation transcripts."""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path

SKIP = {".git", ".codex", ".claude", ".agents", ".venv", "venv", "node_modules", "vendor", "dist", "build", "Library", "__pycache__", "examples", "samples", "fixtures"}


def primary_ids(tasks):
    top = [task["id"] for task in tasks if not task["id"].startswith("line-") and "." not in task["id"]]
    return top if top and len(top) == len(set(top)) and any("." in task["id"] for task in tasks) else []


def registry_json(path):
    if not path.is_file():
        return {}
    if path.stat().st_size > 15_000_000:
        raise ValueError("本地项目索引过大，请使用手动连接")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ValueError("无法读取本地项目索引，请重试或使用手动连接") from error
    return data if isinstance(data, dict) else {}


def codex_roots(home, registry_file=None):
    directory = Path(os.environ.get("CODEX_HOME", str(home / ".codex"))).expanduser()
    state = registry_json(Path(registry_file) if registry_file else directory / ".codex-global-state.json")
    projects = state.get("local-projects", {})
    rows = projects.values() if isinstance(projects, dict) else projects if isinstance(projects, list) else []
    roots = []
    for project in rows:
        if not isinstance(project, dict):
            continue
        paths = project.get("rootPaths", [])
        if not paths and project.get("path"):
            paths = [project["path"]]
        for path in paths if isinstance(paths, list) else []:
            roots.append((path, project.get("name") or project.get("label")))
    labels = state.get("electron-workspace-root-labels", {})
    labels = labels if isinstance(labels, dict) else {}
    legacy = state.get("electron-saved-workspace-roots", [])
    for path in legacy if isinstance(legacy, list) else []:
        roots.append((path, labels.get(path)))
    return roots


def claude_roots(home, registry_file=None):
    state = registry_json(Path(registry_file) if registry_file else home / ".claude.json")
    projects = state.get("projects", {})
    roots = [(path, None) for path in projects] if isinstance(projects, dict) else []
    directory = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(home / ".claude"))).expanduser() / "projects"
    if registry_file is None and directory.is_dir():
        for folder in sorted(directory.iterdir())[:300]:
            if folder.is_symlink() or not folder.is_dir():
                continue
            index = registry_json(folder / "sessions-index.json")
            original = index.get("originalPath")
            if isinstance(original, str):
                roots.append((original, None))
            # Read the dedicated index only. JSONL transcripts are never opened.
            entries = index.get("entries", [])
            for entry in entries[:300] if isinstance(entries, list) else []:
                if isinstance(entry, dict) and isinstance(entry.get("projectPath"), str):
                    roots.append((entry["projectPath"], None))
    return roots


def find_task_files(root):
    from progress import parse_tasks, read_document, source_path
    from work_structure import HISTORY, parse_work_plan, local_work_links, visible_lines
    root = Path(root).expanduser().resolve()
    if not root.is_dir():
        return []
    candidates, linked = [], set()
    visited = 0
    for directory, folders, files in os.walk(root, followlinks=False):
        depth = len(Path(directory).relative_to(root).parts)
        folders[:] = sorted(name for name in folders if name not in SKIP and not name.startswith(".") and not HISTORY.search(name)
                            and not (Path(directory) / name).is_symlink())
        if depth >= 3 or root in {Path.home().resolve(), Path(root.anchor)}:
            folders[:] = []
        visited += 1
        if visited > 250:
            break
        for filename in sorted(files):
            lower = filename.lower()
            if not lower.endswith(".md") or lower in {"agents.md", "claude.md", "skill.md"}:
                continue
            if not any(word in lower for word in ("task", "todo", "plan", "module", "roadmap", "handoff", "readme", "requirement", "模块", "任务", "计划", "进度", "待办", "路线图")):
                continue
            relative = str((Path(directory) / filename).relative_to(root))
            if HISTORY.search(relative):
                continue
            try:
                path = source_path(root, relative)
                content = read_document(path)
                tasks = parse_tasks(content, exclude_instructions=lower.startswith("readme"))
                groups = parse_work_plan(content, relative)
            except (OSError, ValueError, UnicodeError):
                continue
            # Explicit documentation links outrank a conventional filename.
            if any(token in lower for token in ("readme", "handoff", "status", "交接", "进度")):
                for target in local_work_links(content, relative):
                    try:
                        linked.add(str(source_path(root, target).relative_to(root)))
                    except ValueError:
                        continue
            if not tasks and not groups:
                continue
            score = 100 if lower == "tasks.md" else 90 if "task" in lower else 85 if "module" in lower or "模块" in lower else 80 if "todo" in lower else 70 if "plan" in lower else 50
            headings = [line.lstrip("# ").strip() for _, line in visible_lines(content) if re.match(r"^#{1,2}\s", line)]
            current = any(re.search(r"^(?:current\b|active\b|当前|本轮|本次|正在)", title, re.I) for title in headings)
            obsolete = any(re.search(r"obsolete|superseded|deprecated|旧版本|已替代", title, re.I) for title in headings)
            obsolete = obsolete or bool(tasks and all(t["done"] for t in tasks) and any(re.search(r"(?:release|版本).*?(?:completed|shipped|已完成|已发布)|(?:completed|已完成).*?(?:release|版本)", title, re.I) for title in headings) and not current)
            score += 45 if current else 0
            score -= 150 if obsolete else 0
            work_lines = {task["line"] for group in groups for task in group["tasks"]}
            main_tasks = [task for task in tasks if task["section"] not in work_lines] if groups else tasks
            candidates.append({"file": relative, "total": len(tasks), "done": sum(task["done"] for task in tasks), "score": score - depth, "obsolete": obsolete,
                               "reason": "obsolete" if obsolete else "current" if current else "conventional", "title": headings[0][:100] if headings else path.stem,
                               "primaryIds": primary_ids(main_tasks), "workTasks": sum(group["total"] for group in groups)})
            if len(candidates) >= 40:
                break
        if len(candidates) >= 40:
            break
    for candidate in candidates:
        if candidate["file"] in linked and not candidate["obsolete"]:
            candidate["score"] += 65
            candidate["reason"] = "linked"
    return sorted(candidates, key=lambda item: (-item["score"], item["file"]))


def discover_projects(provider, config, home=None, registry_file=None, authorized_roots=None):
    if provider not in {"codex", "claude"}:
        raise ValueError("请选择 Codex 或 Claude Code")
    if authorized_roots is not None and registry_file is None:
        return {"provider": provider, "projects": [], "needsPermission": True}
    home = Path(home) if home else Path.home()
    roots = codex_roots(home, registry_file) if provider == "codex" else claude_roots(home, registry_file)
    connected = {str(Path(p["root"]).expanduser().resolve()): p["id"] for p in config["projects"]}
    projects, seen = [], set()
    for path, label in roots:
        if not isinstance(path, str) or not Path(path).expanduser().is_absolute():
            continue
        root = Path(path).expanduser().resolve()
        if str(root) in seen:
            continue
        seen.add(str(root))
        needs_grant = authorized_roots is not None and not any(root.is_relative_to(Path(grant).resolve()) for grant in authorized_roots)
        available = needs_grant or root.is_dir()
        choices = [item for item in find_task_files(root) if not item.get("obsolete")] if available and not needs_grant and str(root) not in connected else []
        projects.append({"id": hashlib.sha256(f"{provider}:{root}".encode()).hexdigest()[:20],
                         "name": label if isinstance(label, str) and label else root.name,
                         "root": str(root), "available": available, "requiresAuthorization": needs_grant,
                         "connectedId": connected.get(str(root)),
                         "tasksFile": choices[0]["file"] if choices else None,
                         "primaryIds": choices[0]["primaryIds"] if choices else [],
                         "taskCount": choices[0]["total"] if choices else 0})
    return {"provider": provider, "projects": projects}


def connect_discovered(config, provider, identity, home=None, **options):
    candidates = discover_projects(provider, config, home, **options)["projects"]
    selected = next((project for project in candidates if project["id"] == identity), None)
    if not selected or not selected["available"]:
        raise ValueError("该项目目录已不可用，请刷新项目列表")
    if selected.get("requiresAuthorization"):
        raise PermissionError("请先授权访问该项目目录")
    if selected["connectedId"]:
        return {"id": selected["connectedId"], "alreadyConnected": True}
    project = {"id": hashlib.sha256(selected["root"].encode()).hexdigest()[:16],
               "name": selected["name"], "root": selected["root"], "provider": provider,
               "tasksFile": selected["tasksFile"], "autoTasks": True,
               "primaryIds": selected["primaryIds"], "dependencies": {}, "estimates": {}, "hoursPerDay": 4}
    handoff = Path(project["root"]) / "PROJECT_HANDOFF.md"
    if handoff.is_file() and handoff.resolve().is_relative_to(Path(project["root"])):
        project["handoffFile"] = "PROJECT_HANDOFF.md"
    config["projects"].append(project)
    return {"id": project["id"], "awaitingPlan": not bool(project["tasksFile"])}
