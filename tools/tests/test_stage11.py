# -*- coding: utf-8 -*-
"""阶段 11 测试：节次「+ 添加节次」点一下加一条，且界面真的能看到。

背景（本次要解决的问题）：
    点「添加节次」和「生成若干空白节次」都不出东西。
    根因在前端：addPeriod 保存成功后只调 renderPeriods() 重画，
    而 renderPeriods 是从 State.settings 里读的——State.settings 压根没刷新，
    所以列表还是旧内容，看起来「点了没反应」。
    另外同一处还有一个更隐蔽的 bug：防抖保存里调了根本没定义的 render()。

    凯森同时要求：去掉「生成若干空白节次」按钮，只留「添加节次」，点一下加一个。
"""
import json
import os
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import STATIC_DIR, ServerTestCase  # noqa: E402

# 关键字与浏览器/JS 内置，做「未定义函数」静态扫描时排除
KEYWORDS = {
    'if', 'for', 'while', 'switch', 'catch', 'return', 'function', 'typeof', 'new',
    'do', 'else', 'try', 'delete', 'in', 'of', 'case', 'throw', 'void', 'await',
    'yield', 'class', 'super', 'instanceof', 'with', 'finally', 'break', 'continue',
}
BUILTINS = {
    'fetch', 'document', 'window', 'navigator', 'location', 'history', 'localStorage',
    'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'requestAnimationFrame',
    'JSON', 'String', 'Number', 'Boolean', 'Array', 'Object', 'Math', 'Date', 'RegExp',
    'Promise', 'Error', 'Symbol', 'Map', 'Set', 'isNaN', 'isFinite', 'parseFloat',
    'parseInt', 'encodeURIComponent', 'decodeURIComponent', 'encodeURI', 'decodeURI',
    'URL', 'Blob', 'File', 'FileReader', 'FormData', 'Headers', 'Request', 'Response',
    'console', 'alert', 'confirm', 'prompt', 'btoa', 'atob', 'getComputedStyle',
    'matchMedia', 'structuredClone', 'queueMicrotask', 'Uint8Array', 'TextDecoder',
    'addEventListener', 'removeEventListener', 'dispatchEvent',
}
# 这些名字只出现在 CSS 字符串里（grid-template-columns:repeat(4,1fr)、var(--line)），
# 不是 JS 调用；真正的 String#repeat 是 .repeat() 形式，前面有点号，本来就被排除了。
CSS_ARTIFACTS = {'repeat', 'var'}


def read_js():
    return (STATIC_DIR / 'app.js').read_text(encoding='utf-8')


def read_html():
    return (STATIC_DIR / 'index.html').read_text(encoding='utf-8')


class TestPeriodApi(ServerTestCase):
    """后端契约：一次请求加一条，加完能从设置里读到。"""

    def periods(self):
        return self.srv.ok('/api/settings')['periods']

    def add(self, **body):
        body.setdefault('label', '')
        body.setdefault('start', '')
        body.setdefault('end', '')
        return self.srv.ok('/api/settings/period', 'POST', body)

    def test_one_click_adds_one(self):
        self.assertEqual(self.periods(), [], '一开始不该有条目')
        self.add()
        got = self.periods()
        self.assertEqual(len(got), 1, '点一下必须只加一条')
        self.assertTrue(got[0]['id'])

    def test_add_five_times_gives_five(self):
        for _ in range(5):
            self.add()
        got = self.periods()
        self.assertEqual(len(got), 5, '连点 5 次应该正好 5 条')

    def test_new_period_is_readable_right_after(self):
        """前端加完要立刻重新拉设置才能看见，这里保证拉得到。"""
        item = self.add(label='第一节', start='08:00', end='08:45')
        fresh = self.periods()
        self.assertEqual(len(fresh), 1)
        self.assertEqual(fresh[0]['id'], item['id'])
        self.assertEqual(fresh[0]['label'], '第一节')
        self.assertEqual(fresh[0]['start'], '08:00')
        self.assertEqual(fresh[0]['end'], '08:45')

    def test_blank_label_allowed(self):
        """点一下就是一条空白节次，名称时间都由用户后填。"""
        item = self.add()
        self.assertEqual(item['label'], '')
        self.assertEqual(item['start'], '')
        self.assertEqual(item['end'], '')
        self.assertEqual(len(self.periods()), 1)

    def test_ids_unique_and_increasing(self):
        ids = [self.add()['id'] for _ in range(6)]
        self.assertEqual(len(set(ids)), 6, 'id 不能重复：%s' % ids)
        self.assertEqual(ids, ['p1', 'p2', 'p3', 'p4', 'p5', 'p6'])

    def test_add_does_not_wipe_existing(self):
        a = self.add(label='甲')
        b = self.add(label='乙')
        got = self.periods()
        self.assertEqual([p['id'] for p in got], [a['id'], b['id']])

    def test_label_is_trimmed(self):
        item = self.add(label='  第一节  ')
        self.assertEqual(item['label'], '第一节')

    def test_added_period_shows_up_in_bootstrap(self):
        self.add(label='第一节')
        self.assertEqual(len(self.srv.ok('/api/bootstrap')['settings']['periods']), 1)

    def test_update_and_delete_still_work(self):
        first = self.add(label='甲')
        second = self.add(label='乙')
        self.srv.ok('/api/settings/period', 'PUT',
                    {'id': first['id'], 'label': '甲改', 'start': '09:00', 'end': '09:45'})
        got = self.periods()
        self.assertEqual(got[0]['label'], '甲改')
        self.assertEqual(got[0]['start'], '09:00')
        self.srv.ok('/api/settings/period', 'DELETE', {'id': first['id']})
        self.assertEqual([p['id'] for p in self.periods()], [second['id']])

    def test_add_period_persists_across_restart(self):
        from helpers import TestServer
        self.add(label='重启也要在')
        data_dir = str(self.srv.data_dir)
        self.srv.proc.terminate()
        self.srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            periods = revived.ok('/api/settings')['periods']
            self.assertEqual([p['label'] for p in periods], ['重启也要在'])
        finally:
            revived.stop()
        self.srv.proc = None


class TestPeriodButtonFrontend(unittest.TestCase):
    """界面契约：只剩「添加节次」，而且加完必须刷新状态。"""

    def test_only_add_button_left(self):
        html = read_html()
        self.assertIn('id="addPer"', html)
        self.assertIn('添加节次', html)
        self.assertNotIn('genPer', html, '「生成若干空白节次」按钮应该已经去掉')
        self.assertNotIn('生成若干', html)
        self.assertNotIn('空白节次', html)

    def test_js_has_no_trace_of_generator(self):
        js = read_js()
        self.assertNotIn('genPer', js, 'app.js 里不该再绑 genPer')
        self.assertNotIn('生成若干', js)

    def test_add_period_refreshes_state_before_rendering(self):
        """就是这次的 bug：保存后必须重新拉设置，否则界面上看不到新节次。"""
        js = read_js()
        body = js[js.index('function addPeriod'):]
        body = body[:body.index('\n}\n') + 3]
        self.assertIn("api('/api/settings/period'", body)
        self.assertIn('reloadSettings', body,
                      'addPeriod 保存后必须 reloadSettings，不能只 renderPeriods')

    def test_no_render_periods_without_refresh_in_add_path(self):
        js = read_js()
        body = js[js.index('function addPeriod'):]
        body = body[:body.index('\n}\n') + 3]
        self.assertNotIn('renderPeriods()', body,
                         'addPeriod 里不该直接 renderPeriods（会画旧状态）')


class TestNoUndefinedCalls(unittest.TestCase):
    """app.js 里调用的每个函数都必须在文件里定义过。

    这条是防「render() 这种没定义的函数被调用」这一类 bug——
    它跑在 promise 里，出错也不报，只会表现为「点了没反应」。
    """

    def test_all_called_functions_are_defined(self):
        js = read_js()
        defined = set(re.findall(r'function\s+([A-Za-z_$][\w$]*)\s*\(', js))
        defined |= set(re.findall(r'var\s+([A-Za-z_$][\w$]*)\s*=', js))
        defined |= set(re.findall(r'([A-Za-z_$][\w$]*)\s*=\s*(?:function|\([\w,\s]*\)\s*=>)', js))
        # 形参也在作用域里，算「已定义」
        for group in re.findall(r'function\s*[\w$]*\s*\(([^)]*)\)', js) + \
                re.findall(r'\(([^)]*)\)\s*=>', js):
            for name in group.split(','):
                name = name.strip()
                if re.fullmatch(r'[A-Za-z_$][\w$]*', name):
                    defined.add(name)
        called = set(re.findall(r'(?<![\w$.])([A-Za-z_$][\w$]*)\s*\(', js))
        unknown = sorted(n for n in called
                         if n not in defined and n not in KEYWORDS
                         and n not in BUILTINS and n not in CSS_ARTIFACTS)
        self.assertEqual(unknown, [], 'app.js 调用了没定义的函数：%s' % unknown)

    def test_boot_is_called_exactly_once_without_strays(self):
        """boot() 是唯一入口：多一个不存在的调用就会让整个 App 启动不了。"""
        js = read_js()
        self.assertNotIn('bootStage0', js, 'bootStage0 未定义，会让 boot() 执行不到')
        calls = re.findall(r'(?m)^\s*boot\(\)\s*;', js)
        self.assertEqual(len(calls), 1, '启动调用应该只有一次 boot();实际 %d 次' % len(calls))
        self.assertIn('function boot()', js)

    def test_known_undefined_name_is_gone(self):
        js = read_js()
        self.assertNotIn('{ render(); }', js, 'render() 未定义，必须换成 reloadSettings()')

    def test_js_syntax_valid(self):
        import subprocess
        node = None
        for candidate in (r'C:\Users\34480\.workbuddy\binaries\node\versions\22.22.2-3\node.exe',
                          'node'):
            if os.path.isfile(candidate):
                node = candidate
                break
        if not node:
            self.skipTest('找不到 node')
        r = subprocess.run([node, '--check', str(STATIC_DIR / 'app.js')],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, 'app.js 语法有问题：\n' + r.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
