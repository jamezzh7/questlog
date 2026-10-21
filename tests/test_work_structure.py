import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from discovery import find_task_files
from progress import get_progress, parse_tasks
from read_summary import load_summary
from work_structure import parse_work_plan, status_value


PLAN = """# Work plan
## Access module
### ACCESS-01: Sign in
- Priority / Status: P0; needs user approval
- Acceptance: Verify account access
## Search module
### SEARCH-01: Search index
- Priority / Status: P1; ready to start
- Dependencies: Local fixtures only
- Acceptance: Search returns expected results
### SEARCH-02: Integrate production
- Priority / Status: P2; deferred
"""


class WorkStructureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        (self.root / "docs").mkdir()
        self.main = self.root / "tasks.md"
        self.main.write_text("# Main checklist\n- [x] A1 Foundation\n- [ ] B1 Acceptance\n\n[Module tasks](docs/module-plan.md)\n")
        self.plan = self.root / "docs/module-plan.md"
        self.plan.write_text(PLAN)
        self.config = {"id": "sample", "name": "Sample", "root": str(self.root), "tasksFile": "tasks.md", "primaryIds": ["A1", "B1"]}

    def tearDown(self):
        self.temp.cleanup()

    def read(self):
        return get_progress(self.config, include_context=False)

    def test_linked_modules_keep_main_denominator_and_do_not_invent_activity(self):
        result = self.read()
        self.assertEqual(result["overall"], {"done": 1, "total": 2, "percent": 50})
        self.assertEqual(result["work"], {"kind": "module", "groupCount": 2, "taskCount": 3, "activeCount": 0})
        self.assertIsNone(result["current"])
        self.assertEqual(result["next"]["id"], "SEARCH-01")
        self.assertEqual(result["nextKind"], "ready")
        self.assertTrue(all(group["percent"] is None and group["done"] is None for group in result["groups"]))
        self.assertEqual(result["sources"][1]["file"], "docs/module-plan.md")

    def test_linked_file_change_updates_revision_and_native_watch_files(self):
        before = self.read()
        self.plan.write_text(PLAN.replace("ready to start", "in progress"))
        after = self.read()
        self.assertNotEqual(before["revision"], after["revision"])
        self.assertEqual(before["overall"], after["overall"])
        self.assertEqual(after["current"]["title"], "Search module")
        self.assertEqual(after["work"]["activeCount"], 1)
        config = self.root / "projects.json"
        config.write_text(json.dumps({"projects": [self.config]}))
        summary = load_summary(config)["project"]
        self.assertIn(str(self.plan), summary["watchFiles"])
        self.assertEqual(summary["current"]["kind"], "module")
        self.assertIsNone(summary["current"]["done"])

    def test_parallel_modules_are_not_reduced_to_the_last_one(self):
        self.plan.write_text(PLAN.replace("needs user approval", "in progress").replace("ready to start", "in progress"))
        result = self.read()
        self.assertEqual(result["work"]["activeCount"], 2)
        self.assertIsNone(result["current"])
        self.assertEqual(result["next"]["id"], "ACCESS-01")

    def test_status_only_completion_never_checks_parent_acceptance(self):
        self.plan.write_text(PLAN.replace("ready to start", "delivered"))
        result = self.read()
        task = result["groups"][1]["tasks"][0]
        self.assertTrue(task["done"])
        self.assertEqual(result["overall"]["done"], 1)
        self.assertIsNone(result["next"])

    def test_migration_prefers_linked_modules_to_retained_milestone_history(self):
        self.main.write_text(self.main.read_text() + "\n## M10 historical increment\n- [ ] M10.1 Old pending work\n")
        result = self.read()
        self.assertEqual(result["groupKind"], "module")
        self.assertTrue(all(not group["title"].startswith("M10") for group in result["groups"]))
        self.assertEqual(result["next"]["id"], "SEARCH-01")

    def test_archived_links_and_fenced_examples_are_not_work(self):
        (self.root / "docs/history").mkdir()
        (self.root / "docs/history/module-plan.md").write_text(PLAN)
        self.main.write_text(self.main.read_text() + "\n[Historical module plan](docs/history/module-plan.md)\n```md\n[Module tasks](docs/example-tasks.md)\n```\n")
        self.plan.write_text(PLAN + "\n## Archived module\n### OLD-01: Historic work\n- Status: in progress\n")
        result = self.read()
        self.assertEqual(result["work"]["taskCount"], 3)
        self.assertEqual(len(result["watchFiles"]), 2)

    def test_missing_link_keeps_main_reading_and_watches_for_recovery(self):
        self.plan.unlink()
        result = self.read()
        self.assertEqual(result["overall"]["percent"], 50)
        self.assertIn(str(self.plan), result["watchFiles"])
        self.assertEqual(result["warnings"][0]["file"], "docs/module-plan.md")
        self.assertEqual(result["warnings"][0]["code"], "missing")
        self.assertNotIn("Errno", result["warnings"][0]["message"])
        self.plan.write_text(PLAN)
        self.assertEqual(self.read()["work"]["taskCount"], 3)

    def test_unsupported_linked_format_is_visible_without_changing_scope(self):
        self.plan.write_text("# Module plan\nNo machine-readable task states yet.\n")
        result = self.read()
        self.assertEqual(result["overall"]["total"], 2)
        self.assertTrue(result["warnings"])

    def test_links_cannot_escape_root_or_read_external_symlinks(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "tasks.md"
            target.write_text(PLAN)
            (self.root / "docs/escape-tasks.md").symlink_to(target)
            self.main.write_text(self.main.read_text() + "\n[Other tasks](../../outside-tasks.md)\n[Tasks](docs/escape-tasks.md)\n[Module tasks](https://example.invalid/tasks.md)\n")
            result = self.read()
        self.assertEqual(result["work"]["taskCount"], 3)
        self.assertEqual(len(result["warnings"]), 2)
        self.assertNotIn(str(target), result["watchFiles"])

    def test_bounded_traversal_and_cycles(self):
        self.plan.write_text(PLAN + "\n[Module tasks](../tasks.md)\n" + "\n".join(f"[Tasks {i}](tasks-{i}.md)" for i in range(12)))
        for i in range(12):
            (self.root / f"docs/tasks-{i}.md").write_text(PLAN)
        result = self.read()
        self.assertLessEqual(len(result["watchFiles"]), 8)
        self.assertTrue(result["warnings"])

    def test_standalone_module_plan_is_discovered_without_faking_percentage(self):
        self.main.unlink()
        config = {"id": "module-only", "name": "Modules", "root": str(self.root), "autoTasks": True}
        choice = find_task_files(self.root)[0]
        self.assertEqual(choice["file"], "docs/module-plan.md")
        self.assertEqual(choice["workTasks"], 3)
        result = get_progress(config, include_context=False)
        self.assertEqual(result["overall"]["total"], 0)
        self.assertEqual(result["work"]["taskCount"], 3)
        self.assertFalse(result["eta"]["available"])

    def test_discovery_prefers_live_modules_to_archived_task_files(self):
        self.main.unlink()
        archive = self.root / "docs/progress-history"
        archive.mkdir()
        (archive / "tasks.md").write_text("- [x] A1 Old work\n")
        choices = find_task_files(self.root)
        self.assertEqual(choices[0]["file"], "docs/module-plan.md")
        self.assertFalse(any("history" in choice["file"] for choice in choices))

    def test_module_state_tables_and_checkbox_module_plans(self):
        table = "## Module: Accounts\n| Task | Title | Status | Priority |\n| --- | --- | --- | --- |\n| ACCOUNT-01 | Sync account | in progress | P1 |\n| ACCOUNT-02 | Review | not ready | P0 |\n"
        groups = parse_work_plan(table, "modules.md")
        self.assertEqual([task["status"] for task in groups[0]["tasks"]], ["in_progress", "blocked"])
        groups = parse_work_plan("## Module: Search\n- [x] SEARCH-01 Index\n- [ ] SEARCH-02 Results\n", "modules.md")
        self.assertEqual(groups[0]["total"], 2)
        self.assertEqual(groups[0]["tasks"][0]["id"], "SEARCH-01")

    def test_module_acceptance_subtasks_are_not_a_product_percentage(self):
        self.plan.write_text(PLAN + "- [x] Local test passed\n- [ ] Deployment accepted\n")
        config = {**self.config, "tasksFile": "docs/module-plan.md", "primaryIds": []}
        result = get_progress(config, include_context=False)
        self.assertEqual(result["overall"]["total"], 0)
        self.plan.write_text("## Module: Search\n- [x] SEARCH-01 Index\n- [ ] SEARCH-02 Results\n")
        result = get_progress(config, include_context=False)
        self.assertEqual(result["overall"], {"done": 1, "total": 2, "percent": 50})
        self.assertEqual(result["work"]["taskCount"], 2)

    def test_ids_are_stable_across_unrelated_line_insertions(self):
        before = self.read()["groups"][1]["id"]
        self.plan.write_text("<!-- New introduction -->\n\n" + PLAN)
        self.assertEqual(self.read()["groups"][1]["id"], before)
        self.assertEqual(parse_tasks("- [ ] GOV-01 Governance\n")[0]["id"], "GOV-01")

    def test_state_headings_without_task_codes_get_stable_identities(self):
        text = "# Plan\n## Search\n### Add search\n- Status: In progress\n- Acceptance: Results visible\n"
        groups = parse_work_plan(text, "plan.md")
        self.assertEqual(groups[0]["title"], "Search")
        self.assertEqual(groups[0]["tasks"][0]["status"], "in_progress")
        self.assertEqual(groups[0]["tasks"][0]["id"], parse_work_plan("\n\n"+text,"plan.md")[0]["tasks"][0]["id"])

    def test_no_context_git_or_model_work_in_widget_path(self):
        with patch("progress.git_activity", side_effect=AssertionError("No Git")), patch("project_context.project_documents", side_effect=AssertionError("No context scan")):
            self.assertEqual(self.read()["work"]["taskCount"], 3)

    def test_negated_or_planned_states_are_not_started_or_delivered(self):
        for value in ("not done", "未完成", "ready to start", "可开始（待后续实施）", "尚未开始"):
            self.assertNotIn(status_value(value), ("done", "in_progress"))
        self.assertEqual(status_value("P1；接口/fixture可开始，真实来源验证需对应许可/预算"), "ready")

    def test_partial_completion_is_not_task_delivery(self):
        for raw in ("已完成接口，仍需验收", "completed tests; awaiting acceptance", "已完成，仍待真实环境验收"):
            self.assertNotEqual(status_value(raw), "done")
        for raw in ("已交付", "P1；已交付（离线范围）", "Completed; PR #12"):
            self.assertEqual(status_value(raw), "done")


if __name__ == "__main__":
    unittest.main()
