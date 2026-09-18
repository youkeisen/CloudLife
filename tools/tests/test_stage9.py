# -*- coding: utf-8 -*-
"""阶段 9 交付验收：按 PRD 第 10 节可自动化的部分逐条走一遍完整用户旅程。"""
import base64
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import APP_ROOT, PYTHON, STATIC_DIR, ServerTestCase, TestServer  # noqa: E402

NET = os.environ.get('MYDAY_NET') == '1'


class TestAcceptance(ServerTestCase):

    def setUp(self):
        ServerTestCase.setUp(self)
        today = __import__('datetime').date.today().isoformat()
        self.srv.ok('/api/settings', 'PUT', {'week1Monday': today, 'displayName': '验收',
                                             'campus': '我的校区'})
        self.p1 = self.srv.ok('/api/settings/period', 'POST',
                               {'label': '第一节', 'start': '08:00', 'end': '09:00'})
        self.p2 = self.srv.ok('/api/settings/period', 'POST',
                               {'label': '第二节', 'start': '09:10', 'end': '10:00'})
        self.meta = self.srv.ok('/api/bootstrap')['weekMeta']
        self.week = self.meta['week'] or 1

    def test_journey_course_to_home(self):
        self.srv.ok('/api/courses', 'POST', {'name': '今天的课', 'week': self.week,
                                             'day': self.meta['dow'], 'slot': self.p1['id']})
        other_day = 1 if self.meta['dow'] != 1 else 2
        self.srv.ok('/api/courses', 'POST', {'name': '不是今天的课', 'week': self.week,
                                             'day': other_day, 'slot': self.p2['id']})
        home = self.srv.ok('/api/home')
        self.assertEqual(home['todayCount'], 1)
        self.assertEqual(home['todayLessons'][0]['lesson']['name'], '今天的课')
        self.assertEqual(home['meta']['displayName'], '验收')
        self.assertEqual(self.srv.ok('/api/courses?week=%d' % self.week)['total'], 2)

    def test_journey_copy_then_clear(self):
        for i in range(3):
            day = (i % 7) + 1
            self.srv.ok('/api/courses', 'POST', {'name': '课%d' % i, 'week': self.week,
                                                 'day': day, 'slot': self.p1['id']})
        targets = [w for w in range(1, 21) if w != self.week]
        self.srv.ok('/api/courses/copy', 'POST', {'from': self.week, 'to': targets,
                                                  'mode': 'overwrite'})
        for w in targets:
            self.assertEqual(self.srv.ok('/api/courses?week=%d' % w)['total'], 3,
                             '第 %d 周复制结果不对' % w)
        self.srv.ok('/api/courses/clear', 'POST', {'week': targets[0]})
        self.assertEqual(self.srv.ok('/api/courses?week=%d' % targets[0])['total'], 0)
        self.assertEqual(self.srv.ok('/api/courses?week=%d' % targets[1])['total'], 3)

    def test_journey_notes(self):
        todo = self.srv.ok('/api/notes', 'POST', {'title': '清单', 'type': 'todo',
                                                  'tags': ['生活'],
                                                  'items': [{'text': '一件', 'done': False},
                                                            {'text': '两件', 'done': False}]})
        self.srv.ok('/api/notes', 'PUT', {'id': todo['id'], 'items': [
            {'text': '一件', 'done': True}, {'text': '两件', 'done': False}]})
        self.srv.ok('/api/notes', 'POST', {'title': '笔记', 'body': '第一行\n第二行'})
        preview = self.srv.ok('/api/home')['notesPreview']
        self.assertEqual(len(preview), 2)
        notes = self.srv.ok('/api/notes')['notes']
        done = [n for n in notes if n['title'] == '清单'][0]
        self.assertTrue(done['items'][0]['done'])
        self.assertFalse(done['items'][1]['done'])
        # 归档后不再出现在速览
        self.srv.ok('/api/notes', 'PUT', {'id': notes[0]['id'], 'archived': True})
        titles = [n['title'] for n in self.srv.ok('/api/home')['notesPreview']]
        self.assertNotIn(notes[0]['title'], titles)

    def test_journey_backup_reset_restore(self):
        self.srv.ok('/api/courses', 'POST', {'name': '要备份的课', 'week': self.week,
                                             'day': self.meta['dow'], 'slot': self.p1['id']})
        self.srv.ok('/api/notes', 'POST', {'title': '要备份的笔记'})
        raw = self.srv.get('/api/backup', raw=True)['body']
        self.srv.ok('/api/reset-all', 'POST', {})
        self.assertEqual(self.srv.ok('/api/notes')['total'], 0)
        self.assertEqual(self.srv.ok('/api/courses?week=%d' % self.week)['total'], 0)
        self.srv.ok('/api/restore', 'POST', {'content': base64.b64encode(raw).decode('ascii')})
        self.assertEqual([n['title'] for n in self.srv.ok('/api/notes')['notes']],
                         ['要备份的笔记'])
        self.assertEqual(self.srv.ok('/api/courses?week=%d' % self.week)['list'][0]['name'],
                         '要备份的课')
        self.assertEqual(self.srv.ok('/api/settings')['displayName'], '验收')

    def test_journey_restart_keeps_everything(self):
        self.srv.ok('/api/courses', 'POST', {'name': '重启验证课', 'week': self.week,
                                             'day': self.meta['dow'], 'slot': self.p1['id']})
        self.srv.ok('/api/notes', 'POST', {'title': '重启验证笔记'})
        data_dir = str(self.srv.data_dir)
        self.srv.proc.terminate()
        self.srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            self.assertEqual(revived.ok('/api/settings')['displayName'], '验收')
            self.assertEqual(len(revived.ok('/api/settings')['periods']), 2)
            got = revived.ok('/api/courses?week=%d' % self.week)
            self.assertEqual([c['name'] for c in got['list']], ['重启验证课'])
            self.assertEqual([n['title'] for n in revived.ok('/api/notes')['notes']],
                             ['重启验证笔记'])
            self.assertEqual(revived.ok('/api/home')['todayCount'], 1)
        finally:
            revived.stop()
        self.srv.proc = None

    def test_data_survives_browser_storage_cleared(self):
        """数据不依赖浏览器：前端代码不允许使用 localStorage。"""
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        html = (STATIC_DIR / 'index.html').read_text(encoding='utf-8')
        for bad in ('localStorage', 'sessionStorage', 'indexedDB', 'document.cookie'):
            self.assertNotIn(bad, js, '前端不该用 ' + bad)
            self.assertNotIn(bad, html, '前端不该用 ' + bad)

    def test_other_modules_work_while_weather_down(self):
        """天气接口挂掉时，其余模块照常可用。"""
        self.srv.ok('/api/settings', 'PUT', {
            'weatherCity': {'name': '取不到的地方', 'latitude': 9999.0, 'longitude': 9999.0,
                            'timezone': 'Asia/Shanghai'}})
        self.assertEqual(self.srv.request('/api/weather')['json']['code'], 'weather_error')
        self.assertTrue(self.srv.ok('/api/home')['meta'])
        self.assertTrue(self.srv.ok('/api/bootstrap')['version'])
        self.assertTrue(self.srv.ok('/api/courses?week=1')['total'] == 0)
        self.assertTrue(self.srv.ok('/api/notes')['total'] == 0)

    @unittest.skipUnless(NET, '需要联网，运行 run_tests.py all net 才会执行')
    def test_journey_real_weather(self):
        self.srv.ok('/api/settings', 'PUT', {
            'weatherCity': {'name': '芜湖', 'latitude': 31.34, 'longitude': 118.38,
                            'timezone': 'Asia/Shanghai'}})
        res = self.srv.request('/api/weather?refresh=1')
        self.assertTrue(res['json']['ok'], str(res['json'])[:200])
        payload = res['json']['data']['payload']
        self.assertIsInstance(payload['current']['temp'], (int, float))
        self.assertTrue(payload['current']['text'])
        self.assertEqual(len(payload['daily']), 7)
        self.assertEqual(len(payload['hourly']), 24)
        home_weather = self.srv.ok('/api/home')['weather']
        self.assertEqual(home_weather['state'], 'ok')


class TestDeliverables(unittest.TestCase):

    def test_startup_bat_and_docs_exist(self):
        for name in ('启动 MyDay.bat', 'PRD.md', 'DEV-PLAN.md',
                     'app/server.py', 'app/store.py', 'app/weather.py', 'app/backup.py',
                     'tools/run_tests.py', 'tools/smoke_test.py'):
            self.assertTrue((APP_ROOT / name).is_file(), '缺少交付物 ' + name)

    def test_bat_can_find_python(self):
        r = subprocess.run(['cmd', '/c', 'where py'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, '系统里找不到 py 启动器，双击 bat 会起不来')

    def test_smoke_script_runs(self):
        r = subprocess.run([PYTHON, str(APP_ROOT / 'tools' / 'smoke_test.py')],
                           capture_output=True, text=True, cwd=str(APP_ROOT),
                           env=dict(os.environ, PYTHONIOENCODING='utf-8'))
        self.assertEqual(r.returncode, 0, '冒烟脚本没通过：\n' + r.stdout[-1500:])


if __name__ == '__main__':
    unittest.main(verbosity=2)
