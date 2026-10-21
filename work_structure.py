"""Bounded, read-only adapters for linked Markdown work plans.

Work records describe what a project says, never infer product completion or
execution from priority, document order, commit activity or an Issue close rate.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$")
WORK_ID = re.compile(r"^([A-Za-z][A-Za-z0-9]*(?:[-_.][A-Za-z0-9]+)*[-_.]\d+)\b[\s:：、-]*(.*)$")
FIELD = re.compile(r"^\s*(?:[-*+]\s+)?(?:\*\*)?([^:：\n]{1,30}?)(?:\*\*)?\s*[:：]\s*(.*)$")
HISTORY = re.compile(r"(?:^|[/\s_-])(?:archive[d]?|history|historical|legacy)(?:$|[/\s_-])|历史|归档|存档", re.I)
WORK_LINK = re.compile(r"module|模块|task|任务|work[-_ ]?plan|工作计划|工作分解", re.I)


def visible_lines(text):
    # Preserve line numbers while ignoring examples and comments.
    text = re.sub(r"<!--.*?-->", lambda m: re.sub(r"[^\n]", " ", m[0]), text, flags=re.S)
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker:
            token = marker[1]
            if fence is None:
                fence = token[0], len(token)
            elif token[0] == fence[0] and len(token) >= fence[1]:
                fence = None
            continue
        if fence is None:
            yield number, line


def sections(text):
    result, stack, occurrences = [], [], {}
    for number, line in visible_lines(text):
        heading = HEADING.match(line)
        if heading:
            level, title = len(heading[1]), heading[2]
            while stack and stack[-1]["level"] >= level:
                stack.pop()
            parents = tuple(item["key"] for item in stack)
            occurrence = occurrences.get((parents, title), 0) + 1
            occurrences[parents, title] = occurrence
            record = {"title": title, "level": level, "line": number, "body": [],
                      "parents": list(stack), "key": f"{title}:{occurrence}"}
            result.append(record); stack.append(record)
        elif result:
            result[-1]["body"].append((number, line))
    return result


def status_value(raw):
    value = re.sub(r"[`*_]", "", raw).strip()
    value = re.sub(r"^P\d\s*[;；:：,，·-]?\s*", "", value, flags=re.I)
    completed = re.match(r"^(?:已交付|已完成|已验收|完成|done|completed|delivered)(?=$|[;；,，.。!！（(])", value, re.I)
    partial = re.search(r"部分|仍需|仍待|待验收|尚未|未完成|未交付|partial|not complete|not delivered|awaiting acceptance", value, re.I)
    if completed and not partial:
        return "done"
    if re.match(r"^(?:进行中|正在实施|实施中|in[ -]progress\b|doing\b|active\b|working\b)", value, re.I):
        return "in_progress"
    if re.search(r"推迟|暂缓|搁置|deferred|postponed|on hold", value, re.I):
        return "deferred"
    if re.search(r"不可开始|不能开始|not ready|cannot start", value, re.I):
        return "blocked"
    if re.search(r"可开始|ready(?: to (?:start|begin))?\b", value, re.I):
        return "ready"
    if re.search(r"阻断|依赖|(?:^|[;；，,])\s*依\S|需用户|需.*(?:决定|授权|操作)|blocked|waiting|awaiting|depends|needs? user", value, re.I):
        return "blocked"
    return "pending"


def metadata(record):
    fields = []
    for _number, line in record["body"]:
        match = FIELD.match(line)
        if match:
            fields.append((match[1].replace("**", "").strip(), match[2].strip().lstrip("* ")))
    status = next((value for key, value in fields if re.search(r"状态|status|state", key, re.I)), "")
    priority = next((value for key, value in fields if re.search(r"优先级|priority", key, re.I)), "")
    rank = re.search(r"\bP[0-9]\b", priority or status, re.I)
    dependency = next((value for key, value in fields if re.search(r"依赖|阻断|dependenc|blocker", key, re.I)), "")
    return status, rank[0].upper() if rank else None, dependency, fields


def work_task(identity, title, raw, priority, dependency, fields, file, line):
    status = status_value(raw)
    return {"id": identity, "title": title, "status": status, "statusText": raw,
            "done": True if status == "done" else False if status != "pending" else None,
            "priority": priority, "dependency": dependency or None, "notes": [
                {"label": key, "text": value} for key, value in fields], "file": file, "line": line}


def parse_work_plan(text, file, linked=False):
    records = sections(text)
    groups = {}

    def add(record, task, parent=False):
        ancestors = record["parents"] + ([] if parent else [record])
        if any(HISTORY.search(item["title"]) for item in ancestors):
            return
        group = record["parents"][-1] if parent and record["parents"] else record
        keys = [item["key"] for item in group["parents"]] + [group["key"]]
        identity = "module-" + hashlib.sha256(f"{file}:{keys}".encode()).hexdigest()[:16]
        entry = groups.setdefault(identity, {"id": identity, "title": group["title"], "kind": "module",
                                            "file": file, "tasks": [], "done": None, "percent": None})
        task["groupId"] = identity; task["groupTitle"] = entry["title"]
        entry["tasks"].append(task)

    for record in records:
        identity = WORK_ID.match(record["title"])
        raw, priority, dependency, fields = metadata(record)
        # A task heading needs a stable ID and an explicit task record, rather
        # than treating every architecture/document heading as planned work.
        if (identity and (raw or fields)) or (raw and record["level"] >= 3):
            key = f'{file}:{[item["key"] for item in record["parents"]]}:{record["key"]}'
            task_id = identity[1] if identity else "heading-" + hashlib.sha256(key.encode()).hexdigest()[:12]
            title = (identity[2] or identity[1]) if identity else record["title"]
            add(record, work_task(task_id, title, raw, priority, dependency,
                                  fields, file, record["line"]), parent=True)
        # Also accept explicit Task / Status Markdown tables in module sections.
        header = None
        for number, line in record["body"]:
            if not line.strip().startswith("|"):
                header = None; continue
            cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
            if all(re.fullmatch(r":?-+:?", cell) for cell in cells):
                continue
            if header is None:
                names = [cell.casefold() for cell in cells]
                if any(name in {"status", "state", "状态"} for name in names) and any(name in {"task", "task id", "id", "任务", "任务 id"} for name in names):
                    header = names
                continue
            if len(cells) != len(header):
                continue
            row = dict(zip(header, cells))
            label = next((row[key] for key in ("task", "task id", "任务", "任务 id", "id") if row.get(key)), "")
            match = WORK_ID.match(label)
            if not match:
                continue
            title = next((row[key] for key in ("title", "name", "标题", "名称") if row.get(key)), match[2] or label)
            raw = next(row[key] for key in ("status", "state", "状态") if key in row)
            priority = next((row[key] for key in ("priority", "优先级") if row.get(key)), None)
            dependency = next((row[key] for key in ("dependencies", "依赖") if row.get(key)), "")
            add(record, work_task(match[1], title, raw, priority, dependency, list(row.items()), file, number))

    if not groups:
        # Checkbox-only module plans are useful too. A normal main checklist
        # remains a checklist unless the source/section explicitly says module.
        from progress import parse_tasks
        by_line = {record["line"]: record for record in records}
        for task in parse_tasks(text):
            record = by_line.get(task["section"])
            if record and (linked or re.search(r"module|模块|work[-_]plan", file, re.I)
                           or re.search(r"\bmodule\b|模块", record["title"], re.I)):
                task.update({"file": file, "statusText": "", "priority": None, "notes": []})
                add(record, task)
    for group in groups.values():
        group["total"] = len(group["tasks"])
        group["active"] = any(task["status"] == "in_progress" for task in group["tasks"])
    return list(groups.values())


def local_work_links(text, file):
    for _number, line in visible_lines(text):
        for label, destination in re.findall(r"\[([^\]\n]+)\]\(<?([^\s)>]+)>?(?:\s+[\"'][^\n]*?[\"'])?\)", line):
            parsed = urlsplit(destination)
            if parsed.scheme or parsed.netloc or not parsed.path or parsed.path.startswith(("/", "~")):
                continue
            path = unquote(parsed.path)
            if Path(path).suffix.lower() == ".md" and WORK_LINK.search(f"{label} {path}") and not HISTORY.search(f"{label} {path}"):
                yield str(Path(file).parent / path)


def collect_work_structure(root, path, content):
    from progress import read_document, source_path
    relative = str(path.relative_to(root))
    queue = [(relative, content, 0)]
    seen = {path}
    groups, sources, warnings = [], [], []
    watch = {str(path)}
    digest = hashlib.sha256()
    while queue:
        file, text, depth = queue.pop(0)
        digest.update(file.encode()); digest.update(text.encode())
        parsed_groups = parse_work_plan(text, file, linked=depth > 0)
        groups.extend(parsed_groups)
        links = list(local_work_links(text, file))
        if depth > 0 and not parsed_groups and not links:
            warnings.append({"file": file, "message": "关联文档中未识别到模块任务，请检查任务格式"})
        if depth >= 2:
            continue
        for target in links:
            try:
                linked_path = source_path(root, target)
            except ValueError as error:
                warnings.append({"file": target, "message": str(error)}); continue
            if linked_path in seen:
                continue
            if len(seen) >= 8:
                warnings.append({"file": target, "message": "关联任务文档超过读取上限（8 份）"}); continue
            seen.add(linked_path); watch.add(str(linked_path))
            canonical = str(linked_path.relative_to(root))
            try:
                linked_text = read_document(linked_path)
                sources.append({"file": canonical, "path": str(linked_path), "modified": linked_path.stat().st_mtime})
                queue.append((canonical, linked_text, depth + 1))
            except (OSError, ValueError, UnicodeError) as error:
                if isinstance(error, FileNotFoundError):
                    code, message = "missing", "关联任务文档不存在或已移动"
                elif isinstance(error, PermissionError):
                    code, message = "permission", "无法读取关联任务文档，请检查权限"
                elif isinstance(error, UnicodeError):
                    code, message = "encoding", "关联任务文档不是有效的 UTF-8 文本"
                else:
                    code, message = "read", "无法读取关联任务文档，请检查文件及大小"
                warnings.append({"file": canonical, "code": code, "message": message})
    # Duplicate IDs in a work plan are ambiguous; surface them without corrupting
    # the main checklist or presenting two records as a single completed task.
    identities = [(group["file"], task["id"]) for group in groups for task in group["tasks"]]
    if len(identities) != len(set(identities)):
        warnings.append({"file": relative, "message": "关联任务 ID 重复，请核对任务台账"})
    tasks = [task for group in groups for task in group["tasks"]]
    active = [group for group in groups if group["active"]]
    candidates = [task for task in tasks if task["status"] == "in_progress"] or [task for task in tasks if task["status"] == "ready"]
    candidates.sort(key=lambda task: task.get("priority") or "P9")
    return {"groups": groups, "current": active[0] if len(active) == 1 else None,
            "next": candidates[0] if candidates else None,
            "overview": {"kind": "module", "groupCount": len(groups), "taskCount": len(tasks), "activeCount": len(active)},
            "sources": sources, "warnings": warnings, "watchFiles": sorted(watch), "revision": digest.hexdigest()[:16]}
