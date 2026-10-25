from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from progress import get_progress
from project_context import excerpt, project_documents
from discovery import find_task_files


class DetailTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.config = {"id": "detail", "name": "Detail", "root": str(self.root), "autoTasks": True, "tasksFile": None}

    def tearDown(self):
        self.temp.cleanup()

    def test_no_plan_still_has_attributed_documents_and_activity(self):
        (self.root / "README.md").write_text("# Product\n\nA local companion for projects.\n")
        with patch("progress.git_activity", return_value=[{"commit": "abc", "date": "2026-10-17", "title": "Work"}]):
            result = get_progress(self.config)
        self.assertEqual(result["state"], "no-plan")
        self.assertEqual(result["overall"]["total"], 0)
        self.assertFalse(result["eta"]["available"])
        self.assertEqual(result["context"][0]["file"], "README.md")
        self.assertIn("local companion", result["context"][0]["text"])
        self.assertEqual(result["sources"][0]["path"], str(self.root / "README.md"))
        self.assertEqual(result["activity"][0]["commit"], "abc")

    def test_widget_reads_bounded_status_evidence_without_git_or_full_context(self):
        (self.root / "STATUS.md").write_text("# Status\nCurrent: Search\nBlocker: Awaiting review\n")
        with patch("progress.git_activity", side_effect=AssertionError("No Git")):
            result = get_progress(self.config, include_context=False)
        self.assertEqual(result["context"], [])
        self.assertEqual(result["tracking"]["mode"], "status")
        self.assertEqual(result["tracking"]["signals"][0]["file"], "STATUS.md")

    def test_generic_sections_are_inspectable_without_double_counting(self):
        (self.root / "tasks.md").write_text("# Build\n## Design\n- [x] Sketch\n## Ship\n- [ ] Install\n")
        result = get_progress(self.config)
        self.assertEqual(result["overall"], {"done": 1, "total": 2, "percent": 50})
        self.assertEqual([m["title"] for m in result["milestones"]], ["Design", "Ship"])
        self.assertFalse(result["milestonesSeparate"])
        self.assertEqual(result["current"]["title"], "Ship")
        self.assertEqual(result["current"]["tasks"][0]["line"], 5)

    def test_duplicate_section_names_remain_separate(self):
        (self.root / "tasks.md").write_text("## Tests\n- [x] Unit\n## Tests\n- [ ] Integration\n")
        result = get_progress(self.config)
        self.assertEqual(len(result["milestones"]), 2)
        self.assertNotEqual(result["milestones"][0]["id"], result["milestones"][1]["id"])

    def test_optional_bad_documents_cannot_break_progress(self):
        (self.root / "tasks.md").write_text("- [x] A1 Work\n")
        (self.root / "README.md").write_bytes(b"\xff\xfe")
        self.config["handoffFile"] = "../outside.md"
        result = get_progress(self.config)
        self.assertEqual(result["overall"]["percent"], 100)
        self.assertEqual(result["context"], [])

    def test_context_scan_is_bounded_and_does_not_follow_symlink_folders(self):
        outside = self.root / "private"
        outside.mkdir()
        (outside / "README.md").write_text("# Secret\n\nShould not be picked up through docs.\n")
        (self.root / "docs").symlink_to(outside, target_is_directory=True)
        for i in range(8):
            (self.root / f"plan-{i}.md").write_text(f"# Plan {i}\n\nDocument context.\n")
        docs = project_documents(self.config)
        self.assertEqual(len(docs), 4)
        self.assertFalse(any("Secret" in d["text"] for d in docs))

    def test_current_handoff_section_and_changes_are_read_from_source(self):
        path = self.root / "PROJECT_HANDOFF.md"
        path.write_text("# Handoff\n## Current work\n\nNew work pending.\n## History\n\nOld work complete.\n")
        result = get_progress(self.config)
        self.assertEqual(result["context"][0]["text"], "New work pending.")
        path.write_text(path.read_text().replace("New work pending.", "New update."))
        self.assertEqual(get_progress(self.config)["context"][0]["text"], "New update.")

    def test_chinese_plan_names_are_detected(self):
        (self.root / "实施计划.md").write_text("## 接线\n- [x] A1 骨架\n- [ ] B1 验收\n")
        self.assertEqual(find_task_files(self.root)[0]["done"], 1)
        self.assertEqual(get_progress(self.config)["overall"]["percent"], 50)

    def test_append_only_status_document_prefers_latest_dated_record(self):
        path = self.root / "交付说明.md"
        path.write_text("# Product\n\nDraft is unpublished.\n\n## Design\n\nOlder work.\n\n2026-09-24: First preview.\n\n2026-09-27: Published with visitor password retained.\n")
        document = project_documents(self.config)[0]
        self.assertEqual(document["title"], "Product")
        self.assertIn("Published with visitor password retained", document["text"])
        self.assertNotIn("unpublished", document["text"])

    def test_dated_heading_excerpt_stops_at_next_section(self):
        _title, text, _truncated = excerpt("# Handoff\n## 2026-10-17 Current\n\nNew work.\n## 2026-10-16 History\n\nOld work.\n", recent=True)
        self.assertIn("New work.", text)
        self.assertNotIn("Old work.", text)

    def test_stage_identity_survives_insertions_before_heading(self):
        path = self.root / "tasks.md"
        path.write_text("## First\n- [x] A1 Design\n## Second\n- [ ] B1 Build\n")
        before = get_progress(self.config)["current"]["id"]
        path.write_text("# Overview\n\nMore context.\n" + path.read_text())
        self.assertEqual(get_progress(self.config)["current"]["id"], before)


if __name__ == "__main__":
    unittest.main()
