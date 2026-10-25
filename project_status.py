"""Local, attributed project state. Activity never changes completion counts."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re


FIELD = re.compile(r"^\s*(?:[-*+]\s+)?(?:\*\*)?(当前(?:事项|工作|任务)?|正在进行|current(?: work| task)?|working on|阻塞(?:项)?|阻断|blockers?|blocked by|下一步|next(?: steps?| action)?|最近交付|recent delivery|项目状态|project status)(?:\*\*)?\s*[:：]\s*(.+)$", re.I)


def document_signals(documents):
    signals, states = [], set()
    for document in documents:
        cursor = document.get("line", 1)
        # Match back to the source for exact line attribution, including headings
        # omitted by the excerpt renderer. No additional file reads are needed.
        source_lines = document.get("evidenceLines", [])
        for line in document["text"].splitlines():
            if not line.strip():
                continue
            match = FIELD.match(line)
            if not match:
                continue
            label, value = match.groups()
            kind = "blocker" if re.search(r"阻|block", label, re.I) else "next" if re.search(r"下一步|next", label, re.I) else "delivery" if re.search(r"交付|delivery", label, re.I) else "state" if re.search(r"状态|status", label, re.I) else "current"
            if kind == "blocker" and re.fullmatch(r"无|暂无|没有|none|no(?:ne)? blockers?", value.strip("。. "), re.I):
                continue
            number = next((number for number, original in source_lines if number >= cursor and original.strip() == line.strip()), cursor)
            cursor = number + 1
            evidence = {"kind": kind, "text": value.strip()[:240], "file": document["file"], "line": number, "modified": document["modified"]}
            if not any(item["kind"] == kind and item["text"] == evidence["text"] for item in signals):
                signals.append(evidence)
            if kind == "state":
                from work_structure import status_value
                states.add(status_value(value))
        if not any(item["file"] == document["file"] for item in signals) and re.search(r"^(?:current\b|当前|正在)", document["title"], re.I):
            text = document["text"].strip()
            if text:
                signals.append({"kind": "current", "text": text.split("\n\n", 1)[0][:240], "file": document["file"], "line": document.get("line", 1), "modified": document["modified"]})
    return signals[:12], len(states - {"pending"}) > 1


def counts(tasks):
    return {"total": len(tasks), "done": sum(item.get("done") is True for item in tasks),
            "active": sum(item.get("status") == "in_progress" for item in tasks),
            "blocked": sum(item.get("status") in {"blocked", "dependency"} for item in tasks),
            "pending": sum(item.get("done") is False and item.get("status") not in {"in_progress", "blocked", "dependency"} for item in tasks),
            "unknown": sum(item.get("done") is None for item in tasks)}


def observed_tasks(result, config):
    """Combine at most four eligible sources; never double-count linked subtasks."""
    from discovery import find_task_files
    from progress import parse_tasks, source_path, read_document
    from work_structure import parse_work_plan
    root = Path(config["root"]).expanduser().resolve()
    groups, watch = [], set(result.get("watchFiles", []))
    records = {}
    conflicts = []

    def add(file, tasks, title=None, identity=None):
        unique = []
        for task in tasks:
            item = {**task, "file": file, "line": task.get("line", 1)}
            task_identity = item["id"]
            key = (task_identity, re.sub(r"\s+", " ", item["title"]).strip().casefold()) if not task_identity.startswith(("line-", "heading-")) else (file, task_identity)
            if key in records:
                previous = records[key]
                if previous.get("status") != item.get("status"):
                    previous.update(done=None, status="pending", statusText="")
                    conflicts.append({"file": file, "line": item["line"], "text": item["title"]})
                continue
            item.setdefault("statusText", "")
            item.setdefault("notes", [])
            records[key] = item
            unique.append(item)
        if unique:
            for item in unique:
                item.update(groupId=identity or "observed:" + file, groupTitle=title or file)
            groups.append({"id": identity or "observed:" + file, "title": title or file, "file": file, "tasks": unique, "done": sum(t.get("done") is True for t in unique), "total": len(unique), "active": any(t["status"] == "in_progress" for t in unique)})

    if result["primary"]:
        if result.get("groups") and result.get("groupKind") != "module":
            selected = {task["id"] for task in result["primary"]}
            for group in result["groups"]:
                add(result["tasksFile"], [task for task in group["tasks"] if task["id"] in selected], group["title"], group["id"])
        else:
            add(result["tasksFile"], result["primary"])
    else:
        for group in result.get("groups", []):
            add(group["file"], group["tasks"], group["title"], group["id"])
    seen = {result.get("tasksFile"), *(group.get("file") for group in result.get("groups", []))}
    if config.get("autoTasks"):
        for candidate in [item for item in find_task_files(root) if not item.get("obsolete") and item["file"] not in seen][:3]:
            file = candidate["file"]
            try:
                path = source_path(root, file)
                content = read_document(path)
                structured = parse_work_plan(content, file)
                tasks = parse_tasks(content, exclude_instructions=path.name.lower().startswith("readme"))
                work_lines = {task["line"] for group in structured for task in group["tasks"]}
                main = [task for task in tasks if task["section"] not in work_lines]
                add(file, main or [task for group in structured for task in group["tasks"]])
                watch.add(str(path))
                if not any(source["path"] == str(path) for source in result["sources"]):
                    result["sources"].append({"file": file, "path": str(path), "modified": path.stat().st_mtime})
            except (OSError, ValueError, UnicodeError):
                continue
    for group in groups:
        group["done"] = sum(item.get("done") is True for item in group["tasks"])
        group["active"] = any(item.get("status") == "in_progress" for item in group["tasks"])
    return groups, watch, conflicts


def enrich(result, config, include_context):
    from progress import summary, estimate_remaining
    from project_context import project_documents
    scope = config.get("trackingScope", {})
    kind = scope.get("kind", "auto")
    signals, conflicts = [], []
    title = scope.get("title") or result.get("tasksFile") or ""
    if kind == "goals":
        tasks = [{"id": item["id"], "title": item["title"], "done": item["done"], "status": "done" if item["done"] else "pending", "dependency": None} for item in scope["items"]]
        goal_config = {**config, "estimates": config.get("goalEstimates", {}), "hoursPerDay": config.get("goalHoursPerDay", config.get("hoursPerDay", 4))}
        result.update(primary=tasks, overall=summary(tasks), tasksFile=None, state="goals", groups=[], milestones=[], groupKind="goal", work=None,
                      current=None, next=next((item for item in tasks if not item["done"]), None), nextKind="next", dependencies=0,
                      eta=estimate_remaining(tasks, goal_config), estimates=goal_config["estimates"], hoursPerDay=goal_config["hoursPerDay"])
        mode, basis = "measured", "goals"
    elif (result["primary"] or result.get("groups")) and ((kind == "checklist" and scope.get("source") == result.get("tasksFile")) or (result["primary"] and ((config.get("primaryIds") and config.get("tasksFile") == result.get("tasksFile")) or not config.get("autoTasks")))):
        tasks = result["primary"] or [task for group in result["groups"] for task in group["tasks"]]
        if not result["primary"]:
            result.update(primary=tasks, overall=summary(tasks), eta=estimate_remaining(tasks, config))
        mode, basis = "measured", "checklist"
    elif result["primary"] or result.get("groups"):
        groups, watch, conflicts = observed_tasks(result, config)
        tasks = [task for group in groups for task in group["tasks"]]
        mode, basis = "tasks", "detected"
        active = [group for group in groups if group["active"]]
        previous = result.get("current")
        current = active[0] if len(active) == 1 else previous if not active and previous and any(g["id"] == previous["id"] for g in groups) else None
        result.update(groups=groups, groupKind="module", current=current,
                      work={"kind": "observed", "groupCount": len(groups), "taskCount": len(tasks), "activeCount": len(active)},
                      watchFiles=sorted(watch), next=next((item for item in tasks if item["status"] == "in_progress"), next((item for item in tasks if item["status"] == "ready"), None)))
        result["nextKind"] = "active" if result["next"] and result["next"]["status"] == "in_progress" else "ready"
    else:
        tasks = []
        documents = result["context"] if include_context else project_documents(config)
        signals, conflict = document_signals(documents)
        conflicts = [item for item in signals if item["kind"] == "state"] if conflict else []
        mode, basis = ("status", "documents") if signals else ("unknown", "none")
        watched = set(result.get("watchFiles", []))
        watched.update(document["path"] for document in documents)
        result["watchFiles"] = sorted(watched)
    for document in result["context"]:
        document.pop("evidenceLines", None)
    result["tracking"] = {"mode": mode, "basis": basis, "title": title[:100], "coverage": "defined" if mode == "measured" else "unknown",
                          "counts": counts(tasks), "signals": signals, "conflicts": conflicts, "scope": scope,
                          "savedGoals": config.get("savedGoals", scope if kind == "goals" else {})}
    # Exclude volatile checkedAt, so reading unchanged sources does not announce updates.
    signature = json.dumps([result["revision"], result["tracking"], result.get("groups", [])], ensure_ascii=False, sort_keys=True)
    result["revision"] = hashlib.sha256(signature.encode()).hexdigest()[:16]
    return result
