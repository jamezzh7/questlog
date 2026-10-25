"""Bounded, source-attributed document excerpts. Never infer task completion from prose."""
from pathlib import Path
import re

from progress import read_document, source_path

NAMES = ("handoff", "交接", "进度", "进展", "status", "readme", "roadmap", "计划", "plan", "requirement", "需求", "交付说明", "项目说明")


def excerpt(content, recent=False):
    # Ignore code examples; all excerpts are displayed as plain text, never HTML.
    lines, fenced = [], False
    for line in content.splitlines():
        if re.match(r"^\s*(```|~~~)", line):
            fenced = not fenced
        elif not fenced:
            lines.append(line)
    clean = "\n".join(lines).strip()
    sections = re.split(r"(?=^##\s+)", clean, flags=re.M)
    selected = next((part for part in sections if re.match(r"##\s+(当前|正在|Current|Status|Next)", part, re.I)), None)
    if selected is None and recent:
        dated = list(re.finditer(r"^(?:#{1,6}\s+)?(20\d{2})[-年/](\d{1,2})[-月/](\d{1,2})(?:日)?[^\n]*", clean, re.M))
        dated = [match for match in dated if 1 <= int(match[2]) <= 12 and 1 <= int(match[3]) <= 31]
        if dated:
            newest = max(dated, key=lambda match: (tuple(int(match[i]) for i in (1, 2, 3)), match.start()))
            tail = clean[newest.start():]
            selected = tail.split("\n## ", 1)[0] if tail.startswith("## ") else tail.split("\n\n", 1)[0]
    if selected is None:
        # Handoffs usually keep their newest entry first; README uses its introduction.
        intro = sections[0]
        prose = re.sub(r"^#{1,6}\s+.*$", "", intro, flags=re.M).strip()
        selected = intro if len(prose) > 60 or len(sections) == 1 else sections[1]
    title_match = re.search(r"^#{1,6}\s+(.+)$", selected, re.M) or re.search(r"^#\s+(.+)$", clean, re.M)
    title = title_match.group(1) if title_match else ""
    body = re.sub(r"^#{1,6}\s+.*$", "", selected, flags=re.M).strip()
    return title, body[:1600], len(body) > 1600


def project_documents(config, tasks_file=None):
    root = Path(config["root"]).expanduser().resolve()
    folders = [root]
    if root not in {Path.home().resolve(), Path(root.anchor)}:
        folders += [root / name for name in ("docs", "specs", "deliverables")]
        specs = root / "specs"
        if specs.is_dir() and not specs.is_symlink():
            folders += [p for p in sorted(specs.iterdir())[:12] if p.is_dir() and not p.is_symlink()]
    candidates = {}
    if config.get("handoffFile"):
        candidates[config["handoffFile"]] = -1
    for folder in folders:
        if not folder.is_dir() or folder.is_symlink():
            continue
        for path in sorted(folder.iterdir())[:250]:
            name = path.name.lower()
            if name.startswith(".") or path.suffix.lower() != ".md" or path.is_symlink() or not path.is_file():
                continue
            rank = next((i for i, token in enumerate(NAMES) if token in name), None)
            if rank is not None:
                relative = str(path.relative_to(root))
                candidates.setdefault(relative, rank)
    documents = []
    for relative in sorted(candidates, key=lambda file: (candidates[file], len(Path(file).parts), file)):
        if relative == tasks_file:
            continue
        try:
            path = source_path(root, relative)
            content = read_document(path)
            title, text, truncated = excerpt(content, recent=any(token in relative.lower() for token in ("handoff", "交接", "进度", "进展", "status", "交付说明")))
            if not text:
                continue
            first = next((line for line in text.splitlines() if line.strip()), "")
            selected_heading = re.search(r"^#{1,6}\s+" + re.escape(title) + r"\s*#*\s*$", content, re.M) if title else None
            offset = content.find(first, selected_heading.end() if selected_heading else 0) if first else -1
            documents.append({"file": relative, "path": str(path), "modified": path.stat().st_mtime,
                              "line": content[:offset].count("\n") + 1 if offset >= 0 else 1,
                              "evidenceLines": list(enumerate(content.splitlines(), 1)),
                              "title": title or path.stem, "text": text, "truncated": truncated})
        except (OSError, ValueError, UnicodeError):
            # Optional docs must not prevent the actual checklist from loading.
            continue
        if len(documents) == 4:
            break
    return documents
