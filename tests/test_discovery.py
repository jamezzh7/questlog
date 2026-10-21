import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from discovery import connect_discovered, discover_projects, find_task_files
from progress import get_progress


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.home = Path(self.temporary.name).resolve()
        self.codex = self.home / ".codex"
        self.codex.mkdir()
        self.alpha = self.home / "alpha"
        self.alpha.mkdir()
        (self.alpha / "tasks.md").write_text("- [x] A1 Setup\n- [ ] B1 Verify\n")
        self.empty = self.home / "empty"
        self.empty.mkdir()
        self.config = {"projects": []}
        self.environment = patch.dict(os.environ, {"CODEX_HOME": str(self.codex), "CLAUDE_CONFIG_DIR": str(self.home / ".claude")})
        self.environment.start()
        self.write_codex()

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def write_codex(self):
        state = {"local-projects": {
            "alpha": {"name": "Alpha", "rootPaths": [str(self.alpha)]},
            "empty": {"name": "Empty", "rootPaths": [str(self.empty)]},
            "missing": {"name": "Removed", "rootPaths": [str(self.home / "missing")]},
        }, "electron-saved-workspace-roots": [str(self.alpha), "ssh://remote/project"]}
        (self.codex / ".codex-global-state.json").write_text(json.dumps(state))

    def discover(self, provider="codex"):
        return discover_projects(provider, self.config, home=self.home)["projects"]

    def test_codex_current_registry_deduplicates_and_finds_tasks(self):
        rows = self.discover()
        self.assertEqual([p["name"] for p in rows], ["Alpha", "Empty", "Removed"])
        self.assertEqual(rows[0]["tasksFile"], "tasks.md")
        self.assertIsNone(rows[1]["tasksFile"])
        self.assertFalse(rows[2]["available"])

    def test_existing_connection_keeps_custom_scope(self):
        existing = {"id": "existing", "root": str(self.alpha), "primaryIds": ["B1"], "estimates": {"B1": [1, 2]}}
        self.config["projects"].append(existing)
        result = connect_discovered(self.config, "codex", self.discover()[0]["id"], home=self.home)
        self.assertEqual(result["id"], "existing")
        self.assertEqual(len(self.config["projects"]), 1)
        self.assertEqual(existing["primaryIds"], ["B1"])
        self.assertEqual(existing["estimates"]["B1"], [1, 2])

    def test_one_click_connection_uses_discovered_plan(self):
        row = self.discover()[0]
        result = connect_discovered(self.config, "codex", row["id"], home=self.home)
        project = self.config["projects"][0]
        self.assertEqual(project["id"], result["id"])
        self.assertEqual(get_progress(project, include_context=False)["overall"]["percent"], 50)

    def test_project_without_plan_connects_and_detects_plan_later(self):
        row = self.discover()[1]
        self.assertTrue(connect_discovered(self.config, "codex", row["id"], home=self.home)["awaitingPlan"])
        config = self.config["projects"][0]
        result = get_progress(config, include_context=False)
        self.assertEqual(result["state"], "no-plan")
        self.assertEqual(result["overall"]["total"], 0)
        self.assertFalse(result["eta"]["available"])
        (self.empty / "TODO.md").write_text("- [x] A1 Done\n- [ ] B1 Next\n")
        self.assertEqual(get_progress(config, include_context=False)["overall"]["percent"], 50)
        self.assertIsNone(config["tasksFile"])

    def test_arbitrary_and_deleted_project_ids_cannot_connect(self):
        for identity in ["invented", self.discover()[2]["id"]]:
            with self.assertRaises(ValueError):
                connect_discovered(self.config, "codex", identity, home=self.home)
        self.assertEqual(self.config["projects"], [])

    def test_claude_registry_and_index_without_transcript_reads(self):
        (self.home / ".claude.json").write_text(json.dumps({"projects": {str(self.alpha): {"private": "ignored"}}}))
        index = self.home / ".claude" / "projects" / "encoded-path"
        index.mkdir(parents=True)
        (index / "sessions-index.json").write_text(json.dumps({"originalPath": str(self.empty)}))
        (index / "session.jsonl").write_text("invalid transcript that must never be parsed")
        self.assertEqual({p["root"] for p in self.discover("claude")}, {str(self.alpha), str(self.empty)})

    def test_task_search_avoids_dependencies_and_external_symlinks(self):
        dependency = self.empty / "node_modules" / "package"
        dependency.mkdir(parents=True)
        (dependency / "tasks.md").write_text("- [x] Fake task\n")
        (self.empty / "tasks.md").symlink_to(self.alpha / "tasks.md")
        self.assertEqual(find_task_files(self.empty), [])

    def test_primary_milestones_are_not_double_counted(self):
        (self.alpha / "tasks.md").write_text("- [x] A1 Setup\n- [ ] B1 Runtime\n## Milestone\n- [x] M1.1 Part\n")
        row = self.discover()[0]
        self.assertEqual(row["primaryIds"], ["A1", "B1"])

    def test_missing_provider_installation_is_empty(self):
        self.assertEqual(self.discover("claude"), [])
        with self.assertRaises(ValueError):
            self.discover("unknown")

    def test_corrupt_registry_is_reported(self):
        (self.codex / ".codex-global-state.json").write_text("{corrupt")
        with self.assertRaisesRegex(ValueError, "无法读取"):
            self.discover()
