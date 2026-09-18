# -*- coding: utf-8 -*-
"""阶段 7 测试：备份 zip 内容与留存、还原、非法备份拒绝、清空前强制备份。"""
import base64
import io
import json
import sys
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import ServerTestCase  # noqa: E402


class TestStage7(ServerTestCase):

    def seed_data(self):
        self.srv.ok('/api/settings', 'PUT', {'displayName': '备份用户', 'campus': '测试校区'})
        self.srv.ok('/api/settings/period', 'POST', {'label': '第一节', 'start': '08:00', 'end': '09:00'})
        p = self.srv.ok('/api/settings')['periods'][0]
        meta = self.srv.ok('/api/bootstrap')['weekMeta']
        self.srv.ok('/api/courses', 'POST', {'name': '备份的课', 'week': meta['week'] or 1,
                                             'day': meta['dow'], 'slot': p['id']})
        self.srv.ok('/api/notes', 'POST', {'title': '备份的笔记', 'body': '内容'})

    def do_backup(self):
        res = self.srv.get('/api/backup', raw=True)
        self.assertEqual(res['status'], 200)
        self.assertIn('attachment', res['headers'].get('Content-Disposition', ''))
        return res['body']

    def test_backup_contains_all_files_and_manifest(self):
        self.seed_data()
        raw = self.do_backup()
        zf = zipfile.ZipFile(io.BytesIO(raw))
        names = zf.namelist()
        for name in ('settings.json', 'courses.json', 'notes.json', 'weather_cache.json', 'manifest.json'):
            self.assertIn(name, names)
        manifest = json.loads(zf.read('manifest.json').decode('utf-8'))
        self.assertEqual(manifest['app'], 'MyDay')
        self.assertTrue(manifest['exportedAt'])
        on_disk = json.loads(zf.read('courses.json').decode('utf-8'))
        week = str(self.srv.ok('/api/bootstrap')['weekMeta']['week'] or 1)
        self.assertEqual(on_disk['weeks'][week][0]['name'], '备份的课')

    def test_backup_kept_on_disk(self):
        self.seed_data()
        self.do_backup()
        zips = list((self.srv.data_dir / 'backups').glob('*.zip'))
        self.assertTrue(zips, '本机应留存一份备份')
        self.assertTrue(zips[0].name.startswith('MyDay-backup-'))

    def test_roundtrip_restore(self):
        self.seed_data()
        raw = self.do_backup()
        b64 = base64.b64encode(raw).decode('ascii')
        # 先改乱数据
        self.srv.ok('/api/reset-all', 'POST', {})
        self.assertEqual(self.srv.ok('/api/settings')['displayName'], '')
        self.assertEqual(self.srv.ok('/api/courses?week=1')['total'], 0)
        self.assertEqual(self.srv.ok('/api/notes')['total'], 0)
        res = self.srv.ok('/api/restore', 'POST', {'content': b64})
        self.assertEqual(len(res['restored']), 4)
        self.assertEqual(self.srv.ok('/api/settings')['displayName'], '备份用户')
        self.assertEqual(self.srv.ok('/api/settings')['periods'][0]['label'], '第一节')
        week = self.srv.ok('/api/bootstrap')['weekMeta']['week'] or 1
        self.assertEqual(self.srv.ok('/api/courses?week=%d' % week)['list'][0]['name'], '备份的课')
        notes = self.srv.ok('/api/notes')['notes']
        self.assertEqual([n['title'] for n in notes], ['备份的笔记'])

    def test_restore_empty_content(self):
        res = self.srv.request('/api/restore', 'POST', {})
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'bad_request')

    def test_restore_rejects_garbage(self):
        res = self.srv.request('/api/restore', 'POST',
                               {'content': base64.b64encode(b'not a zip').decode('ascii')})
        self.assertFalse(res['json']['ok'])
        self.assertTrue(res['json']['error'])

    def test_restore_rejects_zip_without_manifest(self):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w') as zf:
            zf.writestr('hello.txt', 'hi')
        res = self.srv.request('/api/restore', 'POST',
                               {'content': base64.b64encode(buf.getvalue()).decode('ascii')})
        self.assertFalse(res['json']['ok'])
        self.assertIn('manifest', res['json']['error'])

    def test_reset_all_backs_up_first(self):
        self.seed_data()
        res = self.srv.ok('/api/reset-all', 'POST', {})
        self.assertTrue(res['backupFile'].startswith('MyDay-backup-'))
        zips = list((self.srv.data_dir / 'backups').glob('*.zip'))
        self.assertTrue(zips)
        # 数据确实被清空了
        self.assertEqual(self.srv.ok('/api/settings')['displayName'], '')
        self.assertEqual(self.srv.ok('/api/settings')['periods'], [])
        self.assertEqual(self.srv.ok('/api/notes')['total'], 0)
        raw = json.loads((self.srv.data_dir / 'courses.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['weeks'], {})

    def test_reset_all_is_not_destructive_silently(self):
        """清空产生的备份必须能还原回来。"""
        self.seed_data()
        self.srv.ok('/api/reset-all', 'POST', {})
        zips = sorted((self.srv.data_dir / 'backups').glob('*.zip'))
        b64 = base64.b64encode(zips[-1].read_bytes()).decode('ascii')
        self.srv.ok('/api/restore', 'POST', {'content': b64})
        self.assertEqual(self.srv.ok('/api/settings')['displayName'], '备份用户')

    def test_open_folder_returns_path_without_opening(self):
        res = self.srv.ok('/api/open-folder', 'POST', {})
        self.assertEqual(str(res['path']), str(self.srv.data_dir))


if __name__ == '__main__':
    unittest.main(verbosity=2)
