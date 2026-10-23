import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from api_service import LocalAPI
from read_summary import load_project_overview, load_summary


class ProjectOverviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.projects = []
        for name, tasks in [('One', '- [x] A1 Ready\n- [ ] A2 Ship\n'),
                            ('Two', '- [x] B1 Ready\n- [x] B2 Ship\n')]:
            root = self.base / name; root.mkdir()
            (root / 'tasks.md').write_text(tasks)
            self.projects.append({'id': name, 'name': name, 'root': str(root), 'tasksFile': 'tasks.md'})
        self.config = self.base / 'projects.json'
        self.save()

    def tearDown(self):
        self.temp.cleanup()

    def save(self):
        self.config.write_text(json.dumps({'language': 'fr', 'projects': self.projects}))

    def test_each_project_matches_the_widget_without_context_or_git(self):
        before = self.config.read_bytes()
        with patch('project_context.project_documents', side_effect=AssertionError('No documents')), \
             patch('progress.git_activity', side_effect=AssertionError('No Git')):
            overview = load_project_overview(self.config)
            self.assertEqual(overview['language'], 'fr')
            for row in overview['projects']:
                self.assertEqual(row['overall'], load_summary(self.config, row['id'])['project']['overall'])
        self.assertEqual([p['overall']['percent'] for p in overview['projects']], [50, 100])
        self.assertEqual(self.config.read_bytes(), before)

    def test_ungranted_project_is_never_inspected_and_does_not_block_others(self):
        api = LocalAPI(self.config, authorized_roots=[self.projects[0]['root']])
        from progress import get_progress
        with patch('read_summary.get_progress', wraps=get_progress) as read:
            code, overview = api.request('GET', '/api/project-overview')
        self.assertEqual(code, 200)
        self.assertEqual(read.call_count, 1)
        self.assertEqual(read.call_args.args[0]['id'], 'One')
        denied = overview['projects'][1]
        self.assertEqual(denied['state'], 'permission')
        self.assertIsNone(denied['overall'])
        self.assertNotIn('root', denied)

    def test_missing_source_keeps_the_other_project_readable(self):
        (self.base / 'One/tasks.md').unlink()
        overview = load_project_overview(self.config)
        self.assertEqual(overview['projects'][0]['state'], 'unavailable')
        self.assertIsNone(overview['projects'][0]['overall'])
        self.assertEqual(overview['projects'][1]['overall']['percent'], 100)

    def test_no_plan_does_not_invent_a_percentage_and_refresh_sees_changes(self):
        self.projects[1] = {**self.projects[1], 'autoTasks': True}
        del self.projects[1]['tasksFile']
        (self.base / 'Two/tasks.md').unlink()
        self.save()
        row = load_project_overview(self.config)['projects'][1]
        self.assertEqual(row['state'], 'no-plan')
        self.assertEqual(row['overall']['total'], 0)
        (self.base / 'Two/tasks.md').write_text('- [x] A1 Complete\n')
        row = load_project_overview(self.config)['projects'][1]
        self.assertEqual(row['state'], 'ready')
        self.assertEqual(row['overall']['percent'], 100)

    def test_revoking_a_grant_removes_previous_counts(self):
        api = LocalAPI(self.config, authorized_roots=[self.projects[0]['root']])
        self.assertEqual(api.request('GET', '/api/project-overview')[1]['projects'][0]['overall']['percent'], 50)
        revoked = LocalAPI(self.config, authorized_roots=[]).request('GET', '/api/project-overview')[1]
        self.assertTrue(all(row['state'] == 'permission' and row['overall'] is None for row in revoked['projects']))

    def test_empty_connections_and_invalid_configuration(self):
        self.projects = []; self.save()
        self.assertEqual(load_project_overview(self.config)['projects'], [])
        self.config.write_text('{bad json')
        self.assertEqual(LocalAPI(self.config).request('GET', '/api/project-overview')[0], 422)


if __name__ == '__main__':
    unittest.main()
