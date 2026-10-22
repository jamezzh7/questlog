import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from api_service import LocalAPI
from discovery import discover_projects
from store_api import dispatch


class NativeAPITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'project'; self.root.mkdir()
        (self.root / 'tasks.md').write_text('# Tasks\n- [x] A1 Ready\n- [ ] A2 Ship\n')
        self.settings = self.base / 'projects.json'
        self.project = {'id':'sample','name':'Sample','root':str(self.root),'tasksFile':'tasks.md','primaryIds':[]}
        self.settings.write_text(json.dumps({'projects':[self.project],'language':'fr'}))
        self.api = LocalAPI(self.settings, authorized_roots=[str(self.root)])

    def tearDown(self): self.temp.cleanup()

    def test_widget_and_details_have_same_counts(self):
        with patch('progress.git_activity', return_value=[]):
            code, detail = self.api.request('GET', '/api/progress?project=sample')
        code2, summary = self.api.request('GET','/api/summary?project=sample')
        self.assertEqual((code,code2),(200,200))
        self.assertEqual(detail['overall'],summary['project']['overall'])
        self.assertEqual(detail['overall']['percent'],50)
        self.assertEqual(summary['language'],'fr')

    def test_ungranted_project_cannot_be_read_or_modified(self):
        api=LocalAPI(self.settings,authorized_roots=[])
        before=self.settings.read_bytes()
        with patch('api_service.get_progress',side_effect=AssertionError('Must not inspect project')):
            for path in ['/api/progress?project=sample','/api/document?project=sample&file=tasks.md','/api/sources?project=sample','/api/summary']:
                self.assertEqual(api.request('GET',path)[0],403,path)
            self.assertEqual(api.request('POST','/api/estimates',{'project':'sample','estimates':{}})[0],403)
            self.assertEqual(api.request('POST','/api/projects',{'name':'Other','root':str(self.root)})[0],403)
        self.assertEqual(before,self.settings.read_bytes())

    def test_revoked_connection_can_be_removed_without_reading(self):
        api=LocalAPI(self.settings,authorized_roots=[])
        self.assertEqual(api.request('POST','/api/projects/remove',{'project':'sample'})[0],200)
        self.assertEqual(api.request('GET','/api/summary')[1]['projects'],[])

    def test_discovery_does_not_read_registry_without_grant(self):
        with patch('discovery.registry_json',side_effect=AssertionError('No implicit registry read')):
            result=LocalAPI(self.settings,authorized_roots=[]).request('GET','/api/discovery?provider=codex')
        self.assertTrue(result[1]['needsPermission'])

    def test_registry_grant_does_not_grant_project_access(self):
        registry=self.base/'registry.json'
        registry.write_text(json.dumps({'local-projects':[{'rootPaths':[str(self.root)]}]}))
        api=LocalAPI(self.settings,authorized_roots=[],registries={'codex':str(registry)})
        with patch('discovery.find_task_files',side_effect=AssertionError('No ungranted scans')):
            code,catalog=api.request('GET','/api/discovery?provider=codex')
            candidate=catalog['projects'][0]
            self.assertTrue(candidate['requiresAuthorization'])
            self.assertEqual(api.request('POST','/api/connections',{'provider':'codex','project':candidate['id']})[0],403)
        target=api.request('GET','/api/native/connection-target?provider=codex&project='+candidate['id'])
        self.assertEqual(target[1]['root'],str(self.root))

    def test_invalid_estimate_keeps_settings_unchanged(self):
        before=self.settings.read_bytes()
        with patch('progress.git_activity',return_value=[]):
            code,_=self.api.request('POST','/api/estimates',{'project':'sample','estimates':{'A2':[4,1]}})
        self.assertEqual(code,422);self.assertEqual(before,self.settings.read_bytes())

    def test_symlink_source_cannot_escape_grant(self):
        other=self.base/'outside.md';other.write_text('private')
        (self.root/'escape.md').symlink_to(other)
        result=self.api.request('GET','/api/document?project=sample&file=escape.md')
        self.assertEqual(result[0],422)

    def test_bridge_returns_errors_and_rejects_foreign_urls(self):
        for method,path in [('DELETE','/api/projects'),('GET','https://example.invalid/api/projects')]:
            result=json.loads(dispatch(json.dumps({'method':method,'path':path,'authorizedRoots':[]}),str(self.settings)))
            self.assertGreaterEqual(result['status'],400)

    def test_new_connection_and_preferences_use_same_mutations(self):
        self.settings.write_text('{"projects":[]}')
        with patch('progress.git_activity',return_value=[]):
            code,result=self.api.request('POST','/api/projects',{'name':'New','root':str(self.root),'tasksFile':'tasks.md'})
        self.assertEqual(code,200)
        self.assertEqual(self.api.request('POST','/api/preferences',{'language':'zh'})[0],200)
        self.assertEqual(json.loads(self.settings.read_text())['language'],'zh')
        self.assertEqual(self.api.request('GET','/api/projects')[1]['projects'][0]['id'],result['id'])
