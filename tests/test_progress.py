import json
import tempfile
import os
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from progress import estimate_remaining, get_progress, parse_tasks, source_path
from read_summary import load_summary
from server import Handler, ThreadingHTTPServer


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.file = self.root / "tasks.md"
        self.file.write_text("# Project\n- [x] A1 Foundation\n- [ ] B1 Runtime\n## M1 First increment\n- [x] M1.1 Code\n- [ ] M1.2 Acceptance\n", encoding="utf-8")
        self.config = {"id": "sample", "name": "Sample", "root": str(self.root), "tasksFile": "tasks.md",
                       "primaryIds": ["A1", "B1"], "dependencies": {"B1": "Needs an account"}}

    def tearDown(self):
        self.directory.cleanup()

    def test_milestones_do_not_inflate_overall(self):
        result = get_progress(self.config)
        self.assertEqual(result["overall"], {"done": 1, "total": 2, "percent": 50})
        self.assertEqual(result["current"]["done"], 1)
        self.assertEqual(result["next"]["id"], "M1.2")
        self.assertEqual(result["dependencies"], 1)
        self.assertFalse(result["eta"]["available"])

    def test_reads_new_task_state_without_restart(self):
        before = get_progress(self.config)
        self.file.write_text(self.file.read_text().replace("[ ] B1", "[x] B1"))
        after = get_progress(self.config)
        self.assertEqual(after["overall"]["percent"], 100)
        self.assertNotEqual(before["revision"], after["revision"])
        self.assertEqual(after["dependencies"], 0)

    def test_missing_primary_task_fails_instead_of_silently_changing_denominator(self):
        self.config["primaryIds"].append("C1")
        with self.assertRaisesRegex(ValueError, "主任务清单已变化"):
            get_progress(self.config)

    def test_duplicate_ids_rejected(self):
        self.file.write_text("- [x] A1 One\n- [ ] A1 Duplicate\n- [ ] B1 Two\n")
        with self.assertRaisesRegex(ValueError, "重复"):
            get_progress(self.config)

    def test_generic_markdown_and_fenced_examples(self):
        result = parse_tasks("## Build\n- [X] First thing\n```md\n- [x] Fake\n```\n- [ ] 第二件事\n")
        self.assertEqual(len(result), 2)
        self.assertTrue(result[0]["done"])
        self.assertEqual(result[1]["title"], "第二件事")

    def test_no_estimated_deadline_from_partial_estimates(self):
        tasks = [{"id": "A1", "done": False}, {"id": "B1", "done": False}]
        result = estimate_remaining(tasks, {"estimates": {"A1": [1, 3]}})
        self.assertFalse(result["available"])
        self.assertEqual(result["missing"], ["B1"])

    def test_estimates_sum_remaining_work_only(self):
        tasks = [{"id": "A1", "done": True}, {"id": "B1", "done": False}]
        result = estimate_remaining(tasks, {"estimates": {"A1": [50, 100], "B1": [4, 8]}, "hoursPerDay": 4})
        self.assertEqual(result["days"], [1, 2])
        self.assertEqual(result["hours"], [4, 8])

    def test_path_escape_and_symlink_escape_rejected(self):
        with self.assertRaises(ValueError):
            source_path(self.root, "../outside.md")
        (self.root / "escape.md").symlink_to("/tmp/outside.md")
        with self.assertRaises(ValueError):
            source_path(self.root, "escape.md")

    def test_empty_file_is_not_zero_percent_success(self):
        self.file.write_text("# No tasks")
        with self.assertRaises(ValueError):
            get_progress(self.config)

    def test_lightweight_read_skips_git_and_handoff(self):
        self.config["handoffFile"] = "../do-not-read.md"
        with patch("progress.git_activity", side_effect=AssertionError("Git must stay idle")):
            result = get_progress(self.config, include_context=False)
        self.assertEqual(result["overall"]["percent"], 50)
        self.assertIsNone(result["handoff"])
        self.assertEqual(result["activity"], [])

    def test_native_summary_preserves_selected_project_and_current_stage(self):
        config_path = self.root / "projects.json"
        config_path.write_text(json.dumps({"projects": [self.config]}))
        with patch("progress.git_activity", side_effect=AssertionError("No background Git")):
            result = load_summary(config_path, "sample")
        self.assertEqual(result["project"]["id"], "sample")
        self.assertEqual(result["project"]["overall"]["percent"], 50)
        self.assertEqual(result["project"]["current"]["title"], "M1 First increment")
        self.assertNotIn("tasks", result["project"]["current"])
        self.assertEqual(result["language"], "auto")

    def test_native_summary_uses_saved_interface_language(self):
        config_path = self.root / "projects.json"
        for language in ("en", "zh", "fr"):
            config_path.write_text(json.dumps({"language": language, "projects": [self.config]}))
            result = load_summary(config_path)
            self.assertEqual(result["language"], language)
            self.assertEqual(result["project"]["overall"]["percent"], 50)

    def test_empty_native_summary_clears_stale_project(self):
        config_path = self.root / "projects.json"
        config_path.write_text(json.dumps({"language": "zh", "projects": []}))
        self.assertEqual(load_summary(config_path, "removed-project"), {"language": "zh", "projects": [], "project": None})


class APITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.root = Path(cls.directory.name)
        (cls.root / "tasks.md").write_text("- [x] A1 Done\n- [ ] B1 Remaining\n")
        cls.config_path = cls.root / "projects.json"
        cls.config_path.write_text(json.dumps({"projects": [{"id": "demo", "name": "Demo", "root": str(cls.root), "tasksFile": "tasks.md"}]}))
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.server.config_path = cls.config_path
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
        cls.directory.cleanup()

    def request(self, path, body=None, origin=True):
        headers = {"Content-Type": "application/json"}
        if origin:
            headers["Origin"] = self.url
        request = Request(self.url + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        with urlopen(request, timeout=5) as response:
            return json.load(response)

    def test_api_returns_file_backed_progress(self):
        self.assertEqual(self.request("/api/progress?project=demo")["overall"]["percent"], 50)

    def test_source_switch_preserves_settings_per_document_and_source_files(self):
        (self.root / "alternate-plan.md").write_text("## Release\n- [x] C1 Ship\n")
        added = self.request("/api/projects", {"name": "Scoped", "root": str(self.root), "tasksFile": "tasks.md"})
        identity = added["id"]
        self.request("/api/estimates", {"project": identity, "estimates": {"B1": [2, 4]}})
        before = (self.root / "tasks.md").read_bytes()
        self.request("/api/sources", {"project": identity, "file": "alternate-plan.md"})
        result = self.request("/api/progress?project=" + identity)
        self.assertEqual(result["overall"]["percent"], 100)
        self.assertEqual(result["estimates"], {})
        self.request("/api/sources", {"project": identity, "file": "tasks.md"})
        self.assertEqual(self.request("/api/progress?project=" + identity)["estimates"], {"B1": [2, 4]})
        self.assertEqual((self.root / "tasks.md").read_bytes(), before)
        choices = self.request("/api/sources?project=" + identity)
        self.assertEqual(choices["selected"], "tasks.md")
        self.assertTrue(any(c["file"] == "alternate-plan.md" for c in choices["choices"]))

    def test_source_errors_and_cross_origin_requests_preserve_configuration(self):
        before = self.config_path.read_bytes()
        (self.root / "empty.md").write_text("# No checkbox tasks\n")
        for file in ("../escape.md", "empty.md", "missing.md", None, [], "tasks.py"):
            with self.assertRaises(HTTPError) as raised:
                self.request("/api/sources", {"project": "demo", "file": file})
            self.assertEqual(raised.exception.code, 422)
            self.assertEqual(self.config_path.read_bytes(), before)
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/sources", {"project": "demo", "file": "tasks.md"}, origin=False)
        self.assertEqual(raised.exception.code, 403)

    def test_same_source_save_preserves_custom_primary_scope(self):
        path = self.root / "custom-scope.json"
        project = {"id": "custom", "name": "Custom", "root": str(self.root), "tasksFile": "tasks.md",
                   "primaryIds": ["B1"], "dependencies": {"B1": "Account"}, "estimates": {"B1": [3, 6]}}
        path.write_text(json.dumps({"projects": [project]}))
        self.server.config_path = path
        try:
            self.request("/api/sources", {"project": "custom", "file": "tasks.md"})
            saved = json.loads(path.read_text())["projects"][0]
            for key in ("primaryIds", "dependencies", "estimates"):
                self.assertEqual(saved[key], project[key])
        finally:
            self.server.config_path = self.config_path

    def test_automatic_source_estimates_survive_switching_and_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tasks.md").write_text("- [ ] A1 Work\n")
            (root / "plan.md").write_text("- [ ] B1 Release\n")
            added = self.request("/api/projects", {"name": "Auto", "root": directory})
            identity = added["id"]
            self.request("/api/estimates", {"project": identity, "estimates": {"A1": [1, 2]}})
            self.request("/api/sources", {"project": identity, "file": "plan.md"})
            self.request("/api/sources", {"project": identity, "file": "tasks.md"})
            self.assertEqual(self.request("/api/progress?project=" + identity)["estimates"], {"A1": [1, 2]})
            self.request("/api/projects/remove", {"project": identity})

    def test_document_reader_is_plain_text_and_confined_to_markdown_in_project(self):
        result = self.request("/api/document?project=demo&file=tasks.md")
        self.assertIn("[x] A1", result["text"])
        for file in ("../outside.md", "projects.json"):
            with self.assertRaises(HTTPError) as raised:
                self.request("/api/document?project=demo&file=" + file)
            self.assertEqual(raised.exception.code, 422)

    def test_manual_connection_can_start_without_a_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "README.md").write_text("# Product\n\nWork in progress.\n")
            added = self.request("/api/projects", {"name": "No plan", "root": directory, "tasksFile": ""})
            result = self.request("/api/progress?project=" + added["id"])
            self.assertEqual(result["state"], "no-plan")
            self.assertEqual(result["context"][0]["file"], "README.md")
            self.request("/api/projects/remove", {"project": added["id"]})

    def test_language_preference_persists_without_changing_projects(self):
        projects = json.loads(self.config_path.read_text())["projects"]
        for language in ("en", "zh", "fr", "auto"):
            self.assertEqual(self.request("/api/preferences", {"language": language}), {"language": language})
            self.assertEqual(self.request("/api/preferences"), {"language": language})
            saved = json.loads(self.config_path.read_text())
            self.assertEqual(saved["language"], language)
            self.assertEqual(saved["projects"], projects)

    def test_invalid_or_cross_origin_language_does_not_change_config(self):
        before = self.config_path.read_text()
        for value in ("de", "fr-CA", None, [], {"locale": "en"}):
            with self.assertRaises(HTTPError) as raised:
                self.request("/api/preferences", {"language": value})
            self.assertEqual(raised.exception.code, 422)
            self.assertEqual(self.config_path.read_text(), before)
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/preferences", {"language": "en"}, origin=False)
        self.assertEqual(raised.exception.code, 403)
        self.assertEqual(self.config_path.read_text(), before)

    def test_no_cross_origin_writes(self):
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/estimates", {"project": "demo", "estimates": {}}, origin=False)
        self.assertEqual(raised.exception.code, 403)

    def test_estimates_persist_and_change_api_result(self):
        self.request("/api/estimates", {"project": "demo", "estimates": {"B1": [4, 8]}, "hoursPerDay": 4})
        self.assertEqual(self.request("/api/progress?project=demo")["eta"]["days"], [1, 2])
        self.assertEqual(json.loads(self.config_path.read_text())["projects"][0]["estimates"]["B1"], [4, 8])

    def test_invalid_range_rejected(self):
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/estimates", {"project": "demo", "estimates": {"B1": [8, 4]}})
        self.assertEqual(raised.exception.code, 422)

    def test_add_second_project(self):
        result = self.request("/api/projects", {"name": "Second", "root": str(self.root), "tasksFile": "tasks.md"})
        self.assertIn(result["id"], [item["id"] for item in self.request("/api/projects")["projects"]])
        self.assertEqual(self.request("/api/progress?project=" + result["id"])["overall"]["total"], 2)

    def test_missing_source_shows_error(self):
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/projects", {"name": "Missing", "root": str(self.root), "tasksFile": "missing.md"})
        self.assertEqual(raised.exception.code, 422)

    def test_remove_connection_preserves_files_other_projects_and_preferences(self):
        added = self.request("/api/projects", {"name": "Remove me", "root": str(self.root), "tasksFile": "tasks.md"})
        before = json.loads(self.config_path.read_text())
        task_bytes = (self.root / "tasks.md").read_bytes()
        expected = dict(before, projects=[p for p in before["projects"] if p["id"] != added["id"]])
        result = self.request("/api/projects/remove", {"project": added["id"]})
        self.assertEqual(result["removed"], added["id"])
        self.assertEqual(result["projects"], [{"id": p["id"], "name": p["name"]} for p in expected["projects"]])
        self.assertEqual(json.loads(self.config_path.read_text()), expected)
        self.assertEqual((self.root / "tasks.md").read_bytes(), task_bytes)
        self.assertEqual(self.request("/api/progress?project=demo")["overall"]["percent"], 50)

    def test_removal_of_last_project_keeps_preferences_and_empty_summary(self):
        empty_path = self.root / "last-project.json"
        empty_path.write_text(json.dumps({"language": "zh", "projects": [{"id": "last", "name": "Last", "root": str(self.root), "tasksFile": "tasks.md"}]}))
        self.server.config_path = empty_path
        try:
            self.assertEqual(self.request("/api/projects/remove", {"project": "last"}), {"removed": "last", "projects": []})
            self.assertEqual(self.request("/api/projects"), {"projects": []})
            self.assertEqual(json.loads(empty_path.read_text()), {"language": "zh", "projects": []})
            self.assertIsNone(load_summary(empty_path, "last")["project"])
        finally:
            self.server.config_path = self.config_path

    def test_remove_unavailable_project_without_reading_its_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tasks.md").write_text("- [ ] A1 Work\n")
            added = self.request("/api/projects", {"name": "Gone", "root": str(root), "tasksFile": "tasks.md"})
        self.assertFalse(root.exists())
        self.assertEqual(self.request("/api/projects/remove", {"project": added["id"]})["removed"], added["id"])

    def test_invalid_cross_origin_or_get_removal_cannot_change_settings(self):
        before = self.config_path.read_bytes()
        for identity in (None, "", [], {}, False, "unknown-project"):
            with self.assertRaises(HTTPError) as raised:
                self.request("/api/projects/remove", {"project": identity})
            self.assertEqual(raised.exception.code, 422)
            self.assertEqual(self.config_path.read_bytes(), before)
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/projects/remove", {"project": "demo"}, origin=False)
        self.assertEqual(raised.exception.code, 403)
        with self.assertRaises(HTTPError) as raised:
            self.request("/api/projects/remove")
        self.assertEqual(raised.exception.code, 404)
        self.assertEqual(self.config_path.read_bytes(), before)

    def test_static_path_traversal_cannot_read_project_config(self):
        with self.assertRaises(HTTPError) as raised:
            self.request("/projects.json")
        self.assertEqual(raised.exception.code, 404)

    def test_discover_and_connect_api(self):
        codex = self.root / "codex"
        codex.mkdir(exist_ok=True)
        project = self.root / "imported"
        project.mkdir(exist_ok=True)
        (project / "tasks.md").write_text("- [ ] A1 Work\n")
        (codex / ".codex-global-state.json").write_text(json.dumps({"local-projects": {"id": {"name": "Imported", "rootPaths": [str(project)]}}}))
        with patch.dict(os.environ, {"CODEX_HOME": str(codex)}):
            candidates = self.request("/api/discovery?provider=codex")["projects"]
            selected = next(p for p in candidates if p["name"] == "Imported")
            response = self.request("/api/connections", {"provider": "codex", "project": selected["id"]})
            self.assertEqual(self.request("/api/progress?project=" + response["id"])["overall"]["total"], 1)
            again = self.request("/api/connections", {"provider": "codex", "project": selected["id"]})
            self.assertEqual(again["id"], response["id"])
            self.assertTrue(again["alreadyConnected"])
            self.request("/api/projects/remove", {"project": response["id"]})
            refreshed = self.request("/api/discovery?provider=codex")["projects"]
            self.assertFalse(next(p for p in refreshed if p["id"] == selected["id"])["connectedId"])
            reconnected = self.request("/api/connections", {"provider": "codex", "project": selected["id"]})
            self.assertFalse(reconnected.get("alreadyConnected", False))
            self.assertEqual(self.request("/api/progress?project=" + reconnected["id"])["overall"]["total"], 1)


if __name__ == "__main__":
    unittest.main()
