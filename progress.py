"""Read-only Markdown progress adapters. No model, brokerage or network calls."""
from __future__ import annotations

import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

TASK = re.compile(r"^\s*[-*+]\s+\[([ xX!~\-])\]\s+(.+)$")
IDENTIFIER = re.compile(r"^([A-Z]+\d*(?:[._-][A-Z0-9]+)*)\b[\s:：.、-]*(.*)$")


def parse_tasks(text):
    tasks, heading, fence, section = [], "任务清单", False, 0
    for number, line in enumerate(text.splitlines(), 1):
        if re.match(r"^\s*(```|~~~)", line):
            fence = not fence
            continue
        if fence:
            continue
        title = re.match(r"^#{1,6}\s+(.+?)\s*#*$", line)
        if title:
            heading = title.group(1)
            section = number
        match = TASK.match(line)
        if not match:
            continue
        mark, label = match.groups()
        identity = IDENTIFIER.match(label)
        task_id = identity.group(1) if identity else f"line-{number}"
        name = identity.group(2) if identity else label
        # Requirements references are evidence, not part of the task name.
        name = re.sub(r"[（(]R\d+[^）)]*[）)]\s*", "", name).rstrip("。；;")
        tasks.append({"id": task_id, "title": name, "done": mark.lower() == "x",
                      "status": "done" if mark.lower() == "x" else "blocked" if mark == "!" else "pending",
                      "heading": heading, "section": section, "line": number})
    return tasks


def source_path(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("任务文档必须位于项目目录内")
    if path.suffix.lower() != ".md":
        raise ValueError("请选择 Markdown (.md) 任务文档")
    return path


def read_document(path):
    if path.stat().st_size > 2_000_000:
        raise ValueError("任务文档超过 2 MB")
    return path.read_text(encoding="utf-8")


def summary(tasks):
    done = sum(task["done"] for task in tasks)
    return {"done": done, "total": len(tasks), "percent": round(done / len(tasks) * 100) if tasks else 0}


def estimate_remaining(primary, config):
    remaining = [task for task in primary if not task["done"]]
    if not remaining:
        return {"available": True, "complete": True, "label": "清单已完成", "detail": "以项目最终验收为准"}
    estimates = config.get("estimates", {})
    missing = [task["id"] for task in remaining if task["id"] not in estimates]
    if missing:
        return {"available": False, "label": "完成时间待估算", "missing": missing,
                "detail": f"{len(missing)} 项尚无工时估算；外部依赖等待时间未知"}
    low = sum(estimates[task["id"]][0] for task in remaining)
    high = sum(estimates[task["id"]][1] for task in remaining)
    hours = config.get("hoursPerDay", 4)
    days = [round(low / hours, 1), round(high / hours, 1)]
    return {"available": True, "complete": False, "hours": [low, high], "days": days,
            "label": f"约 {days[0]:g}–{days[1]:g} 个工作日",
            "detail": f"{low:g}–{high:g} 工时，每天 {hours:g} 小时；不含依赖等待"}


def git_activity(root):
    try:
        result = subprocess.run(["git", "-C", str(root), "log", "-5", "--format=%h%x09%aI%x09%s"],
                                capture_output=True, text=True, timeout=3, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode:
        return []
    return [dict(zip(("commit", "date", "title"), line.split("\t", 2)))
            for line in result.stdout.splitlines() if line.count("\t") >= 2]


def task_groups(tasks):
    groups = {}
    for task in tasks:
        groups.setdefault(task["section"], []).append(task)
    result, occurrences = [], {}
    for group in groups.values():
        title = group[0]["heading"]
        occurrences[title] = occurrences.get(title, 0) + 1
        result.append({"id": f"{title}:{occurrences[title]}", "title": title, "tasks": group, **summary(group)})
    return result


def add_context(result, config, include_context):
    # The widget never scans documentation or Git. Context exists only in details.
    result.update({"context": [], "handoff": None, "activity": []})
    if include_context:
        from project_context import project_documents
        result["context"] = project_documents(config, result.get("tasksFile"))
        seen = {source["path"] for source in result["sources"]}
        for document in result["context"]:
            if document["path"] not in seen:
                result["sources"].append({key: document[key] for key in ("file", "path", "modified")})
                seen.add(document["path"])
        result["activity"] = git_activity(Path(config["root"]).expanduser().resolve())
    return result


def get_progress(config, include_context=True):
    root = Path(config["root"]).expanduser().resolve()
    if config.get("autoTasks") and not config.get("tasksFile"):
        from discovery import find_task_files
        choices = find_task_files(root)
        if choices:
            config = {**config, "tasksFile": choices[0]["file"], "primaryIds": choices[0]["primaryIds"]}
        else:
            if not root.is_dir():
                raise ValueError("项目目录不存在")
            return add_context({"id": config["id"], "name": config["name"], "root": str(root), "state": "no-plan", "tasksFile": None,
                    "primary": [], "overall": {"done": 0, "total": 0, "percent": 0}, "milestones": [],
                    "current": None, "next": None, "dependencies": 0, "milestonesSeparate": False,
                    "eta": {"available": False, "label": "未建立计划", "detail": "已连接项目，尚未发现 Markdown 任务清单"},
                    "estimates": {}, "hoursPerDay": config.get("hoursPerDay", 4), "sources": [], "handoff": None,
                    "activity": [], "revision": "no-plan", "checkedAt": datetime.now(timezone.utc).isoformat(),
                    "method": "尚无任务清单，暂不计算完成比例。发现任务清单后会自动开始跟踪。"}, config, include_context)
    path = source_path(root, config["tasksFile"])
    content = read_document(path)
    from work_structure import collect_work_structure
    work = collect_work_structure(root, path, content)
    tasks = parse_tasks(content)
    ids = config.get("primaryIds", [])
    primary = [dict(task) for task in tasks if task["id"] in ids] if ids else [dict(task) for task in tasks]
    if not ids and work["groups"]:
        work_lines = {task["line"] for group in work["groups"] if group["file"] == str(path.relative_to(root)) for task in group["tasks"]}
        # Acceptance subchecks beneath a structured task heading are not an
        # implicit main checklist. Top-level checkbox tasks retain their usual
        # counting behavior, and explicit primaryIds still win.
        primary = [task for task in primary if task["section"] not in work_lines]
    if not primary and not work["groups"]:
        raise ValueError("任务文档中没有找到可统计的复选任务")
    if ids and set(ids) - {task["id"] for task in primary}:
        raise ValueError("主任务清单已变化，请更新主任务 ID 配置")
    if len({task["id"] for task in primary}) != len(primary):
        raise ValueError("主任务 ID 重复，请为任务使用唯一 ID")
    dependencies = config.get("dependencies", {})
    for task in primary:
        task["dependency"] = dependencies.get(task["id"])
        # A dependency on a broad stage does not mean all implementation is blocked.
        if not task["done"] and task["dependency"]:
            task["status"] = "dependency"
    primary_ids = {item["id"] for item in primary}
    supplemental = [task for task in tasks if task["id"] not in primary_ids]
    milestones = task_groups(supplemental or primary)
    if not supplemental and len(milestones) == 1:
        milestones = []
    ordered = reversed(milestones) if supplemental else iter(milestones)
    current = next((group for group in ordered if group["done"] < group["total"]),
                   milestones[-1] if milestones else None)
    if current and current["done"] < current["total"]:
        next_task = next(task for task in current["tasks"] if not task["done"])
    else:
        next_task = next((task for task in primary if not task["done"] and not task.get("dependency")),
                         next((task for task in primary if not task["done"]), None))
    sources = [{"file": config["tasksFile"], "path": str(path), "modified": path.stat().st_mtime}, *work["sources"]]
    if work["groups"]:
        current, next_task = work["current"], work["next"]
    elif current:
        current["kind"] = "stage" if supplemental else "section"
    groups = work["groups"] or milestones
    eta = estimate_remaining(primary, config) if primary else {"available": False, "label": "未提供主验收清单", "detail": "模块任务独立展示，不推算整体完成比例或工时"}
    return add_context({"id": config["id"], "name": config["name"], "root": str(root), "primary": primary,
            "tasksFile": config["tasksFile"], "milestonesSeparate": bool(supplemental),
            "overall": summary(primary), "milestones": milestones, "current": current, "next": next_task,
            "groups": groups, "groupKind": "module" if work["groups"] else "stage" if supplemental else "section",
            "work": work["overview"] if work["groups"] else None, "warnings": work["warnings"], "watchFiles": work["watchFiles"],
            "nextKind": ("active" if next_task["status"] == "in_progress" else "ready") if work["groups"] and next_task else "next",
            "dependencies": sum(not task["done"] and bool(task.get("dependency")) for task in primary),
            "eta": eta, "estimates": config.get("estimates", {}),
            "hoursPerDay": config.get("hoursPerDay", 4), "sources": sources, "revision": work["revision"],
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "method": "主清单独立计数；模块按任务原文状态展示，不推算模块百分比。" if work["groups"] else "主清单等权计数；阶段子任务单独统计。百分比不代表工时完成度。" if supplemental else
                      "任务按文档章节分组；每项仅计数一次。百分比不代表工时完成度。"}, config, include_context)
