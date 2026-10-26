import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from api_service import LocalAPI
from remote_snapshot import display_text, load_sync_snapshot


class RemoteSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / 'Orbit'; self.root.mkdir()
        (self.root / 'tasks.md').write_text('- [x] A1 Prototype\n- [ ] A2 Verify\n')
        self.project = {'id': 'local-id', 'name': 'Orbit', 'root': str(self.root), 'tasksFile': 'tasks.md'}
        self.config = self.base / 'config.json'; self.save()

    def tearDown(self): self.temp.cleanup()

    def save(self): self.config.write_text(json.dumps({'projects': [self.project], 'language': 'zh'}))

    def test_empty_selection_never_reads_any_project(self):
        with patch('remote_snapshot.get_progress', side_effect=AssertionError('unselected read')):
            self.assertEqual(load_sync_snapshot(self.config, [])['projects'], [])

    def test_unknown_or_removed_selection_is_not_replaced_by_first_project(self):
        with patch('remote_snapshot.get_progress', side_effect=AssertionError('unselected read')):
            self.assertEqual(load_sync_snapshot(self.config, ['removed'])['projects'], [])

    def test_only_whitelisted_fields_are_exported_and_config_is_unchanged(self):
        before = self.config.read_bytes()
        row = load_sync_snapshot(self.config, ['local-id'])['projects'][0]
        self.assertEqual(set(row), {'id','name','state','mode','scope','counts','percent','signals','needsReview'})
        self.assertEqual(row['mode'], 'measured'); self.assertEqual(row['percent'], 50)
        encoded = json.dumps(row)
        self.assertNotIn(str(self.root), encoded)
        for key in ('root', 'file', 'line', 'modified', 'watchFiles', 'savedGoals', 'git'):
            self.assertNotIn('"' + key + '"', encoded)
        self.assertEqual(before, self.config.read_bytes())

    def test_partial_tasks_never_export_a_percentage(self):
        self.project['autoTasks'] = True; del self.project['tasksFile']; self.save()
        row = load_sync_snapshot(self.config, ['local-id'])['projects'][0]
        self.assertEqual(row['mode'], 'tasks'); self.assertIsNone(row['percent'])
        self.assertEqual(row['counts']['total'], 2)

    def status_project(self):
        (self.root / 'tasks.md').unlink()
        (self.root / 'STATUS.md').write_text('# Current\nCurrent: Validating the export\nBlocker: Waiting for sample\nNext: Review /Users/example/private/report.csv\n')
        self.project['autoTasks'] = True; del self.project['tasksFile']; self.save()

    def test_status_text_is_off_by_default(self):
        self.status_project()
        row = load_sync_snapshot(self.config, ['local-id'])['projects'][0]
        self.assertEqual(row['mode'], 'status'); self.assertEqual(row['signals'], []); self.assertIsNone(row['percent'])
        self.assertNotIn('Validating', json.dumps(row))

    def test_opted_in_text_omits_attribution_paths_and_redacts_inline_paths(self):
        self.status_project()
        row = load_sync_snapshot(self.config, ['local-id'], True)['projects'][0]
        self.assertTrue(row['signals'])
        self.assertTrue(all(set(s) == {'kind', 'text'} for s in row['signals']))
        self.assertNotIn('/Users/example', json.dumps(row)); self.assertNotIn('STATUS.md', json.dumps(row))

    def test_explicit_project_state_uses_the_remote_status_kind(self):
        self.status_project()
        (self.root / 'STATUS.md').write_text('# Current\nProject status: In progress\n')
        row = load_sync_snapshot(self.config, ['local-id'], True)['projects'][0]
        self.assertEqual(row['signals'][0]['kind'], 'status')

    def test_revocation_replaces_previous_counts_and_never_reads_files(self):
        with patch('remote_snapshot.get_progress', side_effect=AssertionError('ungranted read')):
            status, body = LocalAPI(self.config, authorized_roots=[]).request('GET', '/api/sync-snapshot?project=local-id&text=1')
        self.assertEqual(status, 200); row = body['projects'][0]
        self.assertEqual(row['state'], 'permission'); self.assertIsNone(row['counts']); self.assertIsNone(row['percent']); self.assertEqual(row['signals'], [])

    def test_unreadable_project_does_not_retain_progress(self):
        (self.root / 'tasks.md').unlink()
        row = load_sync_snapshot(self.config, ['local-id'])['projects'][0]
        self.assertEqual(row['state'], 'unavailable'); self.assertIsNone(row['counts'])

    def test_sync_reader_does_not_read_git_or_detailed_context(self):
        with patch('progress.git_activity', side_effect=AssertionError('Git read')), patch('project_context.project_documents', side_effect=AssertionError('Detailed context read')):
            self.assertEqual(load_sync_snapshot(self.config, ['local-id'])['projects'][0]['percent'], 50)

    def test_selection_is_bounded_and_validated(self):
        for ids in ('local-id', [None], ['x'] * 51, ['x' * 201], ['']):
            with self.assertRaises(ValueError): load_sync_snapshot(self.config, ids)

    def test_duplicate_selection_does_not_duplicate_rows(self):
        self.assertEqual(len(load_sync_snapshot(self.config, ['local-id', 'local-id'])['projects']), 1)

    def test_text_is_bounded_and_common_paths_are_redacted(self):
        self.assertEqual(len(display_text('a' * 500, 240)), 240)
        self.assertNotIn('secret', display_text(r'file:///tmp/secret C:\private\secret /Users/example/secret', 240))


if __name__ == '__main__': unittest.main()
