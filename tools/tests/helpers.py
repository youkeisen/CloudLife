# -*- coding: utf-8 -*-
"""测试辅助：以临时数据目录启动真实的 MyDay 服务，通过 HTTP 打接口。"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOLS_DIR = TESTS_DIR.parent
APP_ROOT = TOOLS_DIR.parent
APP_DIR = APP_ROOT / 'app'
STATIC_DIR = APP_DIR / 'static'
SERVER_PY = APP_DIR / 'server.py'
PYTHON = sys.executable

_startupinfo = None
if os.name == 'nt':
    _startupinfo = subprocess.STARTUPINFO()
    _startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    port = s.getsockname()[1]
    s.close()
    return port


def read_json_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


class TestServer:
    """启动一次服务，供单个测试模块使用。"""

    def __init__(self, data_dir=None, port=None):
        self.tmp = None
        if data_dir is None:
            self.tmp = tempfile.mkdtemp(prefix='myday-test-')
            data_dir = self.tmp
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.port = port or free_port()
        self.port_file = self.data_dir / '_testport.txt'
        if self.port_file.exists():
            self.port_file.unlink()
        self.base = 'http://127.0.0.1:%d' % self.port
        self.proc = None
        self.log_lines = []

    def start(self):
        env = dict(os.environ)
        env['PYTHONIOENCODING'] = 'utf-8'
        self.proc = subprocess.Popen(
            [PYTHON, str(SERVER_PY), '--data', str(self.data_dir),
             '--port', str(self.port), '--no-browser',
             '--port-file', str(self.port_file)],
            cwd=str(APP_ROOT), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            startupinfo=_startupinfo)
        deadline = time.time() + 25
        last_err = None
        # 先等服务把最终端口写进 port-file（端口被占用时会顺延）
        while time.time() < deadline:
            if self.proc.poll() is not None:
                out = self.proc.stdout.read().decode('utf-8', 'replace') if self.proc.stdout else ''
                raise RuntimeError('服务提前退出：\n' + out)
            if self.port_file.exists():
                try:
                    actual = int(self.port_file.read_text(encoding='utf-8').strip())
                    if actual != self.port:
                        self.port = actual
                        self.base = 'http://127.0.0.1:%d' % actual
                    break
                except ValueError:
                    pass
            time.sleep(0.1)
        while time.time() < deadline:
            if self.proc.poll() is not None:
                out = self.proc.stdout.read().decode('utf-8', 'replace') if self.proc.stdout else ''
                raise RuntimeError('服务提前退出：\n' + out)
            try:
                data = self.ok('/api/health')
                if data.get('version'):
                    return self
            except Exception as exc:
                last_err = exc
            time.sleep(0.2)
        self.stop()
        raise RuntimeError('服务在 25 秒内没起来：%s' % last_err)

    def request(self, path, method='GET', body=None, raw=False):
        url = self.base + path
        data = None
        headers = {}
        if body is not None:
            data = json.dumps(body).encode('utf-8')
            headers['Content-Type'] = 'application/json'
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                payload = resp.read()
                ctype = resp.headers.get('Content-Type', '')
                headers = dict(resp.headers.items())
                if raw or not payload.startswith(b'{') and not payload.startswith(b'['):
                    if 'zip' in ctype or raw:
                        return {'status': resp.status, 'body': payload, 'headers': headers}
                return {'status': resp.status, 'json': json.loads(payload.decode('utf-8')),
                        'headers': headers, 'body': payload}
        except urllib.error.HTTPError as e:
            payload = e.read()
            try:
                j = json.loads(payload.decode('utf-8'))
            except Exception:
                j = None
            return {'status': e.code, 'json': j, 'headers': dict(e.headers.items()), 'body': payload}

    def get(self, path, raw=False):
        return self.request(path, 'GET', raw=raw)

    def post(self, path, body=None):
        return self.request(path, 'POST', body if body is not None else {})

    def put(self, path, body=None):
        return self.request(path, 'PUT', body if body is not None else {})

    def delete(self, path, body=None):
        return self.request(path, 'DELETE', body if body is not None else {})

    def ok(self, path, method='GET', body=None):
        res = self.request(path, method, body)
        assert res['status'] == 200, 'HTTP %s %s -> %s' % (method, path, res['status'])
        assert res['json'] is not None, '返回不是 JSON'
        assert res['json'].get('ok') is True, '接口返回失败：%s' % (res['json'],)
        return res['json']['data']

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=8)
            except Exception:
                self.proc.kill()
        if self.proc and self.proc.stdout:
            try:
                self.proc.stdout.close()
            except Exception:
                pass
        if self.tmp and os.path.isdir(self.tmp):
            shutil.rmtree(self.tmp, ignore_errors=True)


class ServerTestCase(unittest.TestCase):
    """每个测试模块拿到一个干净的服务实例。"""

    def setUp(self):
        self.srv = TestServer()
        self.srv.start()
        self.addCleanup(self.srv.stop)
