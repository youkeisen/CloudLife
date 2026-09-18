# -*- coding: utf-8 -*-
"""阶段 8 测试：前端产物体检、接口一致性、单实例锁、离线可用。"""
import json
import os
import re
import subprocess
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import (APP_ROOT, PYTHON, STATIC_DIR, ServerTestCase, TestServer, free_port)  # noqa: E402
import server as srv_mod  # noqa: E402

NODE = None
for candidate in (r'C:\Users\34480\.workbuddy\binaries\node\versions\22.22.2-3\node.exe',
                  'node'):
    if os.path.isfile(candidate):
        NODE = candidate
        break


class TestFrontendAssets(unittest.TestCase):

    def test_all_pages_and_containers_exist(self):
        html = (STATIC_DIR / 'index.html').read_text(encoding='utf-8')
        for page in ('home', 'courses', 'weather', 'notes', 'settings'):
            self.assertIn('id="p-%s"' % page, html)
        for elem in ('weekSel', 'addCourse', 'copyWeek', 'clearWeek', 'ttCard', 'perList',
                     'addPer', 'btnBackup', 'btnRestore', 'restoreFile', 'btnReset',
                     'btnFolder', 'noteDetail', 'notelist', 'citySel', 'homelessons',
                     'homewx', 'homenotes', 'toast', 'mask'):
            self.assertIn('id="%s"' % elem, html, '页面缺少元素 ' + elem)

    def test_no_external_cdn(self):
        for name in ('index.html', 'app.js', 'style.css'):
            text = (STATIC_DIR / name).read_text(encoding='utf-8')
            for bad in ('http://', 'https://cdn', '//cdn.', 'unpkg', 'jsdelivr'):
                self.assertNotIn(bad, text, name + ' 不应依赖外部资源：' + bad)

    def test_asset_size_reasonable(self):
        total = sum((STATIC_DIR / n).stat().st_size for n in ('index.html', 'app.js', 'style.css'))
        self.assertLess(total, 300 * 1024, '前端文件太大，首屏会变慢：%d 字节' % total)

    @unittest.skipUnless(NODE, '找不到 node，跳过 JS 语法检查')
    def test_js_syntax_valid(self):
        r = subprocess.run([NODE, '--check', str(STATIC_DIR / 'app.js')],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, 'app.js 语法有问题：\n' + r.stderr)

    def test_no_todo_or_placeholder_left(self):
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        self.assertNotIn('TODO', js)
        self.assertNotIn('FIXME', js)

    def test_every_api_used_by_frontend_exists(self):
        """前端调用的每个接口，后端必须真的实现了。"""
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        used = set(re.findall(r"api\('(/api/[^'\"`]+)'", js))
        used.add('/api/health')
        used.add('/api/bootstrap')
        known = {path for (_m, path) in srv_mod.ROUTES.keys()}
        # 前端里带查询串的写法，去掉 ? 之后的部分再比对
        unknown = sorted(p for p in used if p.split('?')[0] not in known)
        self.assertEqual(unknown, [], '前端用了后端没有的接口：%s' % unknown)

    def test_static_files_declared(self):
        for name in ('app.js', 'style.css', 'favicon.ico'):
            self.assertIn(('GET', '/' + name), srv_mod.ROUTES)


class TestRobustness(ServerTestCase):

    def test_bad_json_body_does_not_crash(self):
        """请求体不是 JSON 时不能把服务干掉。"""
        import urllib.request
        req = urllib.request.Request(self.srv.base + '/api/settings', data=b'not json',
                                     method='PUT', headers={'Content-Type': 'application/json'})
        try:
            urllib.request.urlopen(req, timeout=10).read()
        except Exception:
            pass
        self.assertTrue(self.srv.ok('/api/health')['version'], '服务应仍然活着')

    def test_unknown_ids_never_500(self):
        for path, body in (('/api/courses', {'id': 'nope'}),
                           ('/api/notes', {'id': 'nope'}),
                           ('/api/settings/period', {'id': 'nope'})):
            res = self.srv.request(path, 'DELETE', body)
            self.assertNotEqual(res['status'], 500, path + ' 不应 500')
        res = self.srv.request('/api/courses', 'PUT', {'id': 'nope', 'name': 'x'})
        self.assertIn(res['status'], (200, 400))
        self.assertFalse(res['json']['ok'])

    def test_bad_week_param(self):
        res = self.srv.request('/api/courses?week=abc')
        self.assertEqual(res['status'], 400)
        self.assertEqual(res['json']['code'], 'bad_request')

    def test_cache_header_disabled(self):
        res = self.srv.get('/app.js', raw=True)
        control = res['headers'].get('Cache-Control', '')
        self.assertIn('no-store', control)

    def test_single_instance_lock(self):
        """同一份数据目录再开一个实例时，应识趣退出而不是抢端口。"""
        proc = subprocess.Popen(
            [PYTHON, str(APP_ROOT / 'app' / 'server.py'), '--data', str(self.srv.data_dir),
             '--port', str(free_port()), '--no-browser'],
            cwd=str(APP_ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            startupinfo=getattr(subprocess, 'STARTUPINFO', lambda: None)() if os.name == 'nt' else None)
        try:
            deadline = time.time() + 20
            out = ''
            while time.time() < deadline:
                if proc.poll() is not None:
                    out = proc.stdout.read().decode('utf-8', 'replace')
                    break
                time.sleep(0.2)
            self.assertIsNotNone(out, '第二个实例应该自己退出')
            self.assertIn('已经在运行', out, '应提示已在运行：' + out[:200])
        finally:
            if proc.poll() is None:
                proc.kill()

    def test_restart_same_directory_keeps_data(self):
        """关掉进程再用同一目录启动，数据必须还在（重启/关机的核心保证）。"""
        self.srv.ok('/api/settings', 'PUT', {'displayName': '重启验证'})
        p = self.srv.ok('/api/settings/period', 'POST', {'label': '第一节', 'start': '08:00', 'end': '09:00'})
        meta = self.srv.ok('/api/bootstrap')['weekMeta']
        self.srv.ok('/api/courses', 'POST', {'name': '重启后的课', 'week': meta['week'] or 1,
                                             'day': meta['dow'], 'slot': p['id']})
        self.srv.ok('/api/notes', 'POST', {'title': '重启后的笔记'})
        data_dir = str(self.srv.data_dir)
        self.srv.proc.terminate()
        self.srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            self.assertEqual(revived.ok('/api/settings')['displayName'], '重启验证')
            self.assertEqual(revived.ok('/api/settings')['periods'][0]['label'], '第一节')
            week = revived.ok('/api/bootstrap')['weekMeta']['week'] or 1
            got = revived.ok('/api/courses?week=%d' % week)
            self.assertEqual([c['name'] for c in got['list']], ['重启后的课'])
            self.assertEqual([n['title'] for n in revived.ok('/api/notes')['notes']],
                             ['重启后的笔记'])
        finally:
            revived.stop()
        # 原 TestServer 已经停了，避免 tearDown 再停一次报错
        self.srv.proc = None

    def test_no_browser_flag_keeps_console_clean(self):
        res = self.srv.get('/', raw=True)
        self.assertEqual(res['status'], 200)


class TestNoPresetData(unittest.TestCase):
    """零预置原则：源码和数据里不能出现任何真实个人信息。"""

    BANNED = ['单片机', '电力电子', '工程制图', '劳动教育', '笃学楼', '文昌', '老师 YAML',
              '08:10', '12:20', '13:50', '18:30', '安徽应用技术职业大学', '1#102', '1#104',
              '1#303', '凯森', '杨成川', '习近平']

    def iter_files(self):
        app = APP_ROOT / 'app'
        for p in list(app.rglob('*.py')) + list((APP_ROOT / 'app' / 'static').rglob('*')):
            if p.is_file():
                yield p

    def test_no_personal_data_in_code(self):
        hits = []
        for p in self.iter_files():
            try:
                text = p.read_text(encoding='utf-8')
            except UnicodeDecodeError:
                continue
            for bad in self.BANNED:
                if bad in text:
                    hits.append('%s -> %s' % (p.name, bad))
        self.assertEqual(hits, [], '代码里出现了预置个人信息：%s' % hits)

    def test_default_settings_are_empty(self):
        defaults = json.dumps(srv_mod.store.DEFAULTS, ensure_ascii=False)
        for bad in ('1#', '笃学楼', '08:10', '单片机', '芜湖', '08:00'):
            self.assertNotIn(bad, defaults, '默认设置里不该有：' + bad)


if __name__ == '__main__':
    unittest.main(verbosity=2)
