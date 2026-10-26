"""Allowlisted local input for the native iCloud publisher. Never uses the network."""
import json
import re
from pathlib import Path

from progress import get_progress

MAX_PROJECTS = 50


def display_text(value, limit):
    text = " ".join(str(value or "").split())
    # Prose remains opt-in: it may contain confidential content even after redaction.
    text = re.sub(r"file://\S+|(?<!\w)/(?:Users|home|private|tmp|var|Volumes|opt|etc)/\S+|[A-Za-z]:\\\S+", "[local path]", text)
    return text[:limit]


def load_sync_snapshot(config_path, project_ids, include_text=False, authorize=None):
    if not isinstance(project_ids, list) or len(project_ids) > MAX_PROJECTS or any(not isinstance(p, str) or not p or len(p) > 200 for p in project_ids):
        raise ValueError("Invalid sync project selection")
    wanted = set(project_ids)
    config = json.loads(Path(config_path).read_text(encoding="utf-8"))
    rows = []
    for project in config["projects"]:
        if project["id"] not in wanted:
            continue
        row = {"id": project["id"], "name": display_text(project["name"], 100),
               "state": "unavailable", "mode": "unknown", "scope": "", "counts": None, "percent": None, "signals": [], "needsReview": False}
        try:
            if authorize:
                authorize(project["root"])
            progress = get_progress(project, include_context=False)
            tracking = progress["tracking"]
            counts = {key: tracking["counts"][key] for key in ("done", "total", "active", "blocked", "pending", "unknown")}
            row.update(state="ready", mode=tracking["mode"], counts=counts,
                       scope=display_text(tracking.get("title"), 100) if tracking["mode"] == "measured" else "",
                       needsReview=bool(tracking.get("conflicts")))
            if tracking["mode"] == "measured" and progress["overall"]["total"]:
                row["percent"] = progress["overall"]["percent"]
            if include_text:
                row["signals"] = [{"kind": "status" if s["kind"] == "state" else s["kind"], "text": display_text(s["text"], 240)}
                                  for s in tracking.get("signals", []) if s["kind"] in {"current", "blocker", "next", "delivery", "state"}][:4]
        except PermissionError:
            row["state"] = "permission"
        except (OSError, ValueError, KeyError, TypeError):
            pass
        rows.append(row)
    return {"projects": rows}
