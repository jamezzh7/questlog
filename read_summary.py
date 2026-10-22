#!/usr/bin/env python3
"""One-shot data bridge for the native widget. No server, Git or handoff reads."""
import argparse
import json
from pathlib import Path

from progress import get_progress


def load_summary(config_path, project_id=None, authorize=None):
    config = json.loads(Path(config_path).read_text(encoding="utf-8"))
    projects = config["projects"]
    if not projects:
        return {"language": config.get("language", "auto"), "projects": [], "project": None}
    project = next((p for p in projects if p["id"] == project_id), projects[0])
    if authorize:
        authorize(project["root"])
    progress = get_progress(project, include_context=False)
    current = progress["current"]
    return {"language": config.get("language", "auto"), "projects": [{"id": p["id"], "name": p["name"]} for p in projects],
            "project": {"id": progress["id"], "name": progress["name"], "overall": progress["overall"],
                        "current": {k: current.get(k) for k in ("title", "done", "total", "percent", "kind")} if current else None,
                        "work": progress.get("work"), "watchFiles": progress.get("watchFiles", []),
                        "warnings": progress.get("warnings", []),
                        "warning": "; ".join(f'{item["file"]}: {item["message"]}' for item in progress.get("warnings", [])) or None,
                        "eta": progress["eta"]}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--project")
    args = parser.parse_args()
    try:
        print(json.dumps(load_summary(args.config, args.project), ensure_ascii=False))
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
        raise SystemExit(1)
