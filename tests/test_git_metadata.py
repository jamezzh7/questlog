import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from git_metadata import apply_delta, read_activity
from store_api import dispatch


@unittest.skipUnless(shutil.which('git'), 'Git is needed only to create test fixtures')
class GitMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.env = {**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                    'GIT_AUTHOR_NAME': 'Fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
                    'GIT_COMMITTER_NAME': 'Fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid'}
        self.git('init', '--quiet')
        for number in range(24):
            (self.root / 'tasks.md').write_text('# Tasks\n- [x] A1 Ready\n- [ ] A2 Ship\n' + '\n' * number)
            self.git('add', 'tasks.md')
            self.git('commit', '--quiet', '-m', 'Fixture commit ' + str(number))
        self.expected = [line.split('\t', 2) for line in self.git('log', '-5', '--first-parent', '--format=%h%x09%aI%x09%s').splitlines()]

    def tearDown(self): self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], env=self.env, text=True)

    def assert_commits(self):
        with patch('subprocess.run', side_effect=AssertionError('No external process')):
            result = read_activity(self.root)
        self.assertEqual([[p['commit'], p['date'], p['title']] for p in result], self.expected)

    def test_loose_commits_and_detached_head(self):
        self.assert_commits()
        self.git('checkout', '--quiet', '--detach')
        self.assert_commits()

    def test_packed_refs_and_delta_objects(self):
        self.git('pack-refs', '--all')
        self.git('repack', '-a', '-d', '-f', '--depth=50', '--window=50')
        self.git('prune-packed')
        self.assert_commits()

    def test_native_dispatch_never_launches_git(self):
        config = self.root / 'settings.json'
        config.write_text(json.dumps({'projects': [{'id':'fixture','name':'Fixture','root':str(self.root),'tasksFile':'tasks.md'}]}))
        request = {'path':'/api/progress?project=fixture', 'authorizedRoots':[str(self.root)]}
        with patch('subprocess.run', side_effect=AssertionError('No external process')):
            result = json.loads(dispatch(json.dumps(request), str(config)))
        self.assertEqual(result['status'], 200)
        self.assertEqual(len(result['body']['activity']), 5)

    def test_symlink_and_worktree_metadata_cannot_escape_selected_folder(self):
        project = self.root / 'nested'; project.mkdir()
        (project / '.git').symlink_to(self.root / '.git')
        self.assertEqual(read_activity(project), [])
        (project / '.git').unlink()
        (project / '.git').write_text('gitdir: ../.git')
        self.assertEqual(read_activity(project), [])

    def test_corrupt_or_large_objects_are_optional(self):
        head = self.git('rev-parse', 'HEAD').strip()
        object_file = self.root / '.git/objects' / head[:2] / head[2:]
        object_file.chmod(0o600)
        object_file.write_bytes(b'corrupt')
        self.assertEqual(read_activity(self.root), [])


class DeltaBoundsTests(unittest.TestCase):
    def test_valid_copy_and_insert(self):
        self.assertEqual(apply_delta(b'abcd', b'\x04\x05\x90\x03\x02XY'), b'abcXY')

    def test_truncated_oversized_and_invalid_ranges(self):
        for delta in [b'\x04\x01\x00', b'\x04\x05\x91\x03\x05', b'\x04\x02\x03x', b'\x04\xff\xff\xff\x7f']:
            with self.assertRaises((ValueError, IndexError)): apply_delta(b'abcd', delta)
