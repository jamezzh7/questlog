import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from api_service import LocalAPI
from discovery import find_task_files
from progress import get_progress, parse_tasks
from read_summary import load_summary, load_project_overview


class ProjectStatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.project = {"id": "sample", "name": "Sample", "root": str(self.root), "tasksFile": None, "autoTasks": True}

    def tearDown(self):
        self.temp.cleanup()

    def write(self, file, content):
        path = self.root / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def read(self, config=None, details=False):
        return get_progress(config or self.project, include_context=details, activity_reader=lambda _: [])

    def test_installation_checks_do_not_become_project_completion(self):
        self.write("README.md", "# Product\n## Installation\n- [x] Install Python\n- [x] Clone repository\n")
        self.assertEqual(find_task_files(self.root), [])
        result = self.read()
        self.assertEqual(result["overall"]["total"], 0)
        self.assertEqual(result["tracking"]["mode"], "unknown")

    def test_chinese_installation_sections_and_task_examples_are_excluded(self):
        self.write("README.zh-CN.md", "# 产品\n## 安装依赖\n- [x] 安装 Python\n## 示例任务\n- [x] 示例验收\n")
        self.assertEqual(find_task_files(self.root), [])

    def test_historical_links_do_not_outweigh_current_task_source(self):
        self.write("tasks.md", "- [ ] A1 Current task\n")
        self.write("docs/old-plan.md", "- [ ] B1 Old task\n")
        self.write("README.md", "# Product\n## History\n[Task plan](docs/old-plan.md)\n")
        self.assertEqual(find_task_files(self.root)[0]["file"], "tasks.md")

    def test_readme_installation_task_tables_are_not_project_work(self):
        self.write("README.md", "# Product\n## Installation\n| Task | Status |\n| --- | --- |\n| SETUP-01 Install | done |\n")
        self.assertEqual(find_task_files(self.root), [])

    def test_current_plan_beats_completed_old_release(self):
        self.write("tasks.md", "# Release 0.1 completed\n- [x] A1 Ship old release\n")
        self.write("docs/release-plan.md", "# Current release 0.2\n- [ ] B1 Build next release\n")
        result = self.read()
        self.assertEqual(result["tasksFile"], "docs/release-plan.md")
        self.assertEqual(result["tracking"]["counts"]["total"], 1)
        self.assertEqual(result["tracking"]["counts"]["done"], 0)

    def test_explicit_document_link_outweighs_a_conventional_filename(self):
        self.write("tasks.md", "- [x] A1 Initial experiment\n")
        self.write("docs/work-plan.md", "- [ ] B1 Current work\n")
        self.write("README.md", "# Product\n[Current task plan](docs/work-plan.md)\n")
        candidates = find_task_files(self.root)
        self.assertEqual(candidates[0]["file"], "docs/work-plan.md")
        self.assertEqual(candidates[0]["reason"], "linked")

    def test_readme_roadmap_checks_remain_valid_but_unconfirmed(self):
        self.write("README.md", "# Product\n## Roadmap\n- [x] A1 Search\n- [ ] A2 Export\n")
        result = self.read()
        self.assertEqual(result["tracking"]["mode"], "tasks")
        self.assertEqual(result["tracking"]["coverage"], "unknown")
        self.assertEqual(result["tracking"]["counts"]["done"], 1)

    def test_manual_source_does_not_silently_switch(self):
        self.write("tasks.md", "- [x] A1 Original\n")
        self.write("docs/current-plan.md", "# Current plan\n- [ ] B1 New\n")
        result = self.read({**self.project, "autoTasks": False, "tasksFile": "tasks.md"})
        self.assertEqual(result["tasksFile"], "tasks.md")
        self.assertEqual(result["tracking"]["mode"], "measured")

    def test_existing_primary_scope_is_kept_when_auto_source_is_unchanged(self):
        self.write("tasks.md", "- [x] A1 Build\n- [ ] B1 Ship\n")
        result = self.read({**self.project, "tasksFile": "tasks.md", "primaryIds": ["B1"]})
        self.assertEqual(result["overall"]["total"], 1)
        self.assertEqual(result["primary"][0]["id"], "B1")

    def test_examples_comments_and_history_are_not_tasks(self):
        text = "# Plan\n<!-- - [x] Hidden -->\n## Examples\n- [x] Fake\n## Current\n- [~] A1 Running\n## History\n- [x] Old\n"
        tasks = parse_tasks(text)
        self.assertEqual(len(tasks), 1)
        self.assertEqual(tasks[0]["line"], 6)
        self.assertEqual(tasks[0]["status"], "in_progress")

    def test_incomplete_sources_are_combined_without_duplicate_ids(self):
        self.write("tasks.md", "- [x] A1 Build\n- [~] A2 Review\n")
        self.write("docs/other-plan.md", "- [x] A1 Build\n- [!] B1 Wait for access\n")
        result = self.read()
        self.assertEqual(result["tracking"]["counts"]["total"], 3)
        self.assertEqual(result["tracking"]["counts"]["active"], 1)
        self.assertEqual(result["tracking"]["counts"]["blocked"], 1)

    def test_conflicting_task_states_are_unknown_instead_of_complete(self):
        self.write("tasks.md", "- [x] A1 Build\n")
        self.write("docs/other-plan.md", "- [ ] A1 Build\n")
        tracking = self.read()["tracking"]
        self.assertEqual(tracking["counts"]["total"], 1)
        self.assertEqual(tracking["counts"]["done"], 0)
        self.assertEqual(tracking["counts"]["unknown"], 1)
        self.assertTrue(tracking["conflicts"])

    def test_status_without_tasks_has_exact_source_lines_and_watch_paths(self):
        path = self.write("STATUS.md", "# Status\n\nCurrent: Search pagination\nBlocker: Waiting for API approval\nNext: Verify pagination\n")
        result = self.read()
        self.assertEqual(result["tracking"]["mode"], "status")
        self.assertEqual([(s["kind"], s["line"]) for s in result["tracking"]["signals"]], [("current", 3), ("blocker", 4), ("next", 5)])
        self.assertIn(str(path), result["watchFiles"])
        self.assertEqual(result["context"], [])

    def test_conflicting_active_task_is_not_reported_as_in_progress(self):
        self.write("tasks.md", "- [~] A1 Search\n")
        self.write("docs/other-plan.md", "- [x] A1 Search\n")
        result = self.read()
        self.assertEqual(result["tracking"]["counts"]["active"], 0)
        self.assertEqual(result["work"]["activeCount"], 0)
        self.assertEqual(result["groups"][0]["done"], 0)

    def test_status_conflicts_are_exposed_with_both_sources(self):
        self.write("STATUS.md", "# Status\nProject status: in progress\n")
        self.write("PROJECT_HANDOFF.md", "# Handoff\nProject status: done\n")
        tracking = self.read()["tracking"]
        self.assertEqual(tracking["mode"], "status")
        self.assertEqual(len(tracking["conflicts"]), 2)

    def test_details_strip_internal_source_lines(self):
        self.write("STATUS.md", "# Status\nCurrent: Search\n")
        result = self.read(details=True)
        self.assertNotIn("evidenceLines", result["context"][0])

    def test_repeated_status_text_points_to_the_selected_recent_section(self):
        self.write("STATUS.md", "# Status\n## 2026-10-10\nCurrent: Search\n## 2026-10-25\nCurrent: Search\n")
        result = self.read()
        self.assertEqual(result["tracking"]["signals"][0]["line"], 5)

    def test_git_activity_cannot_create_a_progress_percentage(self):
        self.write("README.md", "# Product\nJust a project description.\n")
        with patch("progress.git_activity", return_value=[{"commit": "abc", "title": "Ship everything", "date": "2026-10-25"}]):
            result = get_progress(self.project)
        self.assertEqual(result["tracking"]["mode"], "unknown")
        self.assertEqual(result["overall"]["total"], 0)

    def api(self):
        path = self.root / "projects.json"
        path.write_text(json.dumps({"language": "fr", "appearance": "dark", "projects": [self.project]}))
        return LocalAPI(path, authorized_roots=[str(self.root)]), path

    def test_confirming_scope_enables_a_percentage_with_a_name(self):
        self.write("tasks.md", "- [x] A1 Build\n- [ ] A2 Verify\n")
        api, path = self.api()
        code, _ = api.request("POST", "/api/scope", {"project": "sample", "kind": "checklist", "title": "Release 0.2", "source": "tasks.md"})
        self.assertEqual(code, 200)
        saved = json.loads(path.read_text())["projects"][0]
        result = self.read(saved)
        self.assertEqual(result["tracking"]["mode"], "measured")
        self.assertEqual(result["tracking"]["title"], "Release 0.2")
        self.assertEqual(result["overall"]["percent"], 50)

    def test_goals_work_without_task_files_and_never_write_project_files(self):
        original = self.write("README.md", "# Product\nDescription.\n").read_bytes()
        api, path = self.api()
        payload = {"project": "sample", "kind": "goals", "title": "First preview", "items": [{"title": "Prototype", "done": True}, {"title": "Verify", "done": False}]}
        code, result = api.request("POST", "/api/scope", payload)
        self.assertEqual(code, 200)
        fresh = LocalAPI(path, authorized_roots=[str(self.root)])
        summary = fresh.request("GET", "/api/summary")[1]["project"]
        self.assertEqual(summary["tracking"]["basis"], "goals")
        self.assertEqual(summary["overall"]["percent"], 50)
        self.assertEqual((self.root / "README.md").read_bytes(), original)
        self.assertEqual(json.loads(path.read_text())["appearance"], "dark")
        self.assertEqual(load_project_overview(path)["projects"][0]["tracking"], summary["tracking"])
        items = result["scope"]["items"]
        items[1]["done"] = True
        payload["items"] = items
        self.assertEqual(fresh.request("POST", "/api/scope", payload)[0], 200)
        self.assertEqual(load_summary(path)["project"]["overall"]["percent"], 100)

    def test_invalid_goals_leave_config_unchanged(self):
        api, path = self.api()
        before = path.read_bytes()
        for items in [[], [{"title": "Goal", "done": "yes"}], [{"title": "Goal", "done": True}, {"title": "Goal", "done": False}], [{"title": "x" * 201, "done": False}]]:
            self.assertEqual(api.request("POST", "/api/scope", {"project": "sample", "kind": "goals", "items": items})[0], 422)
            self.assertEqual(path.read_bytes(), before)

    def test_scope_mutation_requires_project_access(self):
        _, path = self.api()
        before = path.read_bytes()
        api = LocalAPI(path, authorized_roots=[])
        self.assertEqual(api.request("POST", "/api/scope", {"project": "sample", "kind": "auto"})[0], 403)
        self.assertEqual(path.read_bytes(), before)

    def test_goals_are_retained_when_switching_tracking_modes(self):
        api, path = self.api()
        body = {"project": "sample", "kind": "goals", "title": "Preview", "items": [{"title": "Verify", "done": False}]}
        self.assertEqual(api.request("POST", "/api/scope", body)[0], 200)
        self.assertEqual(api.request("POST", "/api/scope", {"project": "sample", "kind": "auto"})[0], 200)
        progress = api.request("GET", "/api/progress?project=sample")[1]
        self.assertEqual(progress["tracking"]["savedGoals"]["items"][0]["title"], "Verify")

    def test_goal_estimates_do_not_overwrite_source_estimates(self):
        self.project.update(estimates={"A1": [2, 4]}, hoursPerDay=4)
        api, path = self.api()
        body = {"project": "sample", "kind": "goals", "items": [{"title": "Verify", "done": False}]}
        item = api.request("POST", "/api/scope", body)[1]["scope"]["items"][0]
        self.assertEqual(api.request("POST", "/api/estimates", {"project": "sample", "estimates": {item["id"]: [1, 2]}, "hoursPerDay": 2})[0], 200)
        saved = json.loads(path.read_text())["projects"][0]
        self.assertEqual(saved["estimates"], {"A1": [2, 4]})
        self.assertEqual(saved["hoursPerDay"], 4)
        result = self.read(saved)
        self.assertEqual(result["eta"]["hours"], [1, 2])
        self.assertEqual(result["hoursPerDay"], 2)

    def test_auto_reselection_does_not_reuse_old_scope_or_estimates(self):
        self.write("tasks.md", "# Release 0.1 completed\n- [x] A1 Old release\n")
        self.write("docs/current-plan.md", "# Current plan\n- [ ] A1 New feature\n")
        result = self.read({**self.project, "tasksFile": "tasks.md", "primaryIds": ["A1"], "estimates": {"A1": [1, 2]}})
        self.assertEqual(result["tracking"]["mode"], "tasks")
        self.assertEqual(result["estimates"], {})

    def test_auto_source_picker_matches_the_actual_selected_source(self):
        self.write("tasks.md", "# Release 0.1 completed\n- [x] A1 Old release\n")
        self.write("docs/current-plan.md", "# Current plan\n- [ ] B1 New release\n")
        self.project["tasksFile"] = "tasks.md"
        api, _ = self.api()
        self.assertEqual(api.request("GET", "/api/sources?project=sample")[1]["selected"], "docs/current-plan.md")

    def test_defined_scope_for_structured_tasks_uses_its_own_denominator(self):
        self.write("tasks.md", "# Work\n## Search\n### SEARCH-01: Query\n- Status: delivered\n### SEARCH-02: Verify\n- Status: in progress\n")
        api, _ = self.api()
        code, _ = api.request("POST", "/api/scope", {"project": "sample", "kind": "checklist", "source": "tasks.md", "title": "Search module"})
        self.assertEqual(code, 200)
        result = api.request("GET", "/api/progress?project=sample")[1]
        self.assertEqual(result["tracking"]["mode"], "measured")
        self.assertEqual(result["overall"]["percent"], 50)
