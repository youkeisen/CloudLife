# -*- coding: utf-8 -*-
"""阶段 0 测试：服务能起来、静态页正常、路由存在、不会 500。"""
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import APP_ROOT, ServerTestCase, TestServer  # noqa: E402


class TestStage0(ServerTestCase):

    def test_health(self):
        data = self.srv.ok('/api/health')
        self.assertTrue(data['version'])
        self.assertTrue(data['time'])
        self.assertEqual(str(data['dataDir']), str(self.srv.data_dir))

    def test_index_page(self):
        res = self.srv.get('/', raw=True)
        self.assertEqual(res['status'], 200)
        html = res['body'].decode('utf-8')
        self.assertIn('id="p-home"', html)
        for page in ('home', 'courses', 'weather', 'notes', 'settings'):
            self.assertIn('id="p-%s"' % page, html, '缺少页面容器 ' + page)

    def test_static_assets(self):
        for name, needle in (('/app.js', 'function api'), ('/style.css', '--accent')):
            res = self.srv.get(name, raw=True)
            self.assertEqual(res['status'], 200, name + ' 取不到')
            self.assertIn(needle, res['body'].decode('utf-8'), name + ' 内容不对')
            self.assertIn('no-store', res['headers'].get('Cache-Control', ''), name + ' 没有禁用缓存')

    def test_unknown_route_is_json_404(self):
        res = self.srv.get('/api/not-exist')
        self.assertEqual(res['status'], 404)
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'not_found')

    def test_unknown_static_404(self):
        res = self.srv.get('/evil.js')
        self.assertEqual(res['status'], 404)

    def test_startup_files_exist(self):
        self.assertTrue((APP_ROOT / 'app' / 'server.py').is_file())
        self.assertTrue((APP_ROOT / 'app' / 'static' / 'index.html').is_file())
        self.assertTrue((APP_ROOT / 'app' / 'static' / 'app.js').is_file())
        self.assertTrue((APP_ROOT / 'app' / 'static' / 'style.css').is_file())
        self.assertTrue((APP_ROOT / '启动 MyDay.bat').is_file())
        self.assertTrue((APP_ROOT / 'DEV-PLAN.md').is_file())

    def test_port_conflict_falls_back(self):
        """端口被占用时应自动换端口继续可用，而不是崩掉。"""
        blocked = TestServer()
        blocked.start()
        try:
            first_port = blocked.ok('/api/health')['port']
            second = TestServer(port=first_port)
            second.start()
            try:
                data = second.ok('/api/health')
                self.assertTrue(data['version'])
                self.assertNotEqual(data['port'], first_port,
                                    '端口冲突时没有自动换端口')
            finally:
                second.stop()
        finally:
            blocked.stop()

    def test_console_startup_message(self):
        """用 --no-browser 启动，控制台应打印可用地址。"""
        import subprocess
        import tempfile
        import time
        # 用一份独立数据目录，避免被单实例锁拦住（那份行为由 stage8 单独验证）
        solo = tempfile.mkdtemp(prefix='myday-solo-')
        proc = subprocess.Popen(
            [sys.executable, str(APP_ROOT / 'app' / 'server.py'),
             '--data', solo, '--port', '8999', '--no-browser'],
            cwd=str(APP_ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        time.sleep(2.0)
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except Exception:
            proc.kill()
        try:
            out = proc.stdout.read().decode('utf-8', 'replace')
        except Exception:
            out = ''
        self.assertIn('MyDay is running at http://127.0.0.1:', out, '启动信息没打印出来')
        self.assertIn('数据目录', out, '应打印数据目录位置')


if __name__ == '__main__':
    unittest.main(verbosity=2)
