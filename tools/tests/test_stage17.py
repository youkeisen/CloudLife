# -*- coding: utf-8 -*-
"""阶段 17 测试：电脑版对齐手机版（去掉标签 + 首页速览默认收起）。

背景（凯森 2026-09-22 要求「你把电脑版的补一下」）：
手机版这几轮把标签功能整个去掉了（连数据一起清）、首页速览内容改成默认收起，
电脑版还停在旧形态，这一轮把它拉齐。

前端是原生 JS，没法在 Python 里跑，所以前端那几条走**静态检查**
（读 app.js 的源码断言）—— 和这个项目里其它前端测试一个路子。
"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import (ServerTestCase, TestServer, fn_body,  # noqa: E402
                     read_json_file, read_static)


def read_js():
    return read_static('app.js')


# ---------------- 后端：数据里不再有 tags ----------------

class TestNotesHaveNoTags(ServerTestCase):

    def make(self, title, **kw):
        body = {'title': title}
        body.update(kw)
        return self.srv.ok('/api/notes', 'POST', body)

    def test_new_note_has_no_tags_field(self):
        n = self.make('随手记', body='内容')
        self.assertNotIn('tags', n, '新建的笔记不该再有 tags 字段')

    def test_update_ignores_tags_from_client(self):
        """就算前端硬塞 tags 过来也不该写进去（老页面缓存可能还会发）。"""
        n = self.make('随手记')
        saved = self.srv.ok('/api/notes', 'PUT',
                            {'id': n['id'], 'title': '改过', 'tags': ['学习']})
        self.assertEqual(saved['title'], '改过')
        self.assertNotIn('tags', saved)

    def test_home_preview_has_no_tags(self):
        """首页速览是 server.py 里单独拼的一份，容易漏（第一遍就漏了）。"""
        self.make('随手记', body='内容')
        preview = self.srv.ok('/api/home')['notesPreview']
        self.assertTrue(preview, '速览里应该有这条')
        for p in preview:
            self.assertNotIn('tags', p, '首页速览不该再带 tags（前端已不读它）')

    def test_stored_file_has_no_tags(self):
        self.make('随手记')
        raw = read_json_file(Path(self.srv.data_dir) / 'notes.json')
        self.assertNotIn('tags', raw['notes'][0])


# ---------------- 存量数据：启动时清理 ----------------

class TestLegacyTagsDropped(unittest.TestCase):
    """老数据里残留的 tags 要在服务启动时被清掉。

    只靠「不再解析 tags」清不掉 —— 用户没编辑过的笔记不会重写文件，
    那些字段会一直躺在 notes.json 里（凯森要求「数据一起清掉」）。
    """

    def legacy_notes_file(self, tmp):
        p = Path(tmp) / 'notes.json'
        p.write_text(json.dumps({
            'version': 1,
            'notes': [
                {'id': 'n1', 'title': '老的', 'type': 'text', 'body': '',
                 'items': [], 'tags': ['学习', '生活'], 'pinned': False,
                 'archived': False, 'createdAt': '2026-09-19T07:00:00+08:00',
                 'updatedAt': '2026-09-19T07:00:00+08:00'},
            ],
        }, ensure_ascii=False), encoding='utf-8')
        return p

    def test_legacy_tags_are_removed_on_start(self):
        tmp = tempfile.mkdtemp(prefix='myday-legacy-')
        self.addCleanup(shutil.rmtree, tmp, True)
        p = self.legacy_notes_file(tmp)

        srv = TestServer(data_dir=tmp)
        srv.start()
        self.addCleanup(srv.stop)

        raw = json.loads(p.read_text(encoding='utf-8'))
        note = raw['notes'][0]
        self.assertNotIn('tags', note, '启动时要把旧标签字段清掉')
        self.assertEqual(note['title'], '老的', '别的字段不能动')
        self.assertEqual(note['id'], 'n1')

    def test_not_rewritten_when_nothing_to_clean(self):
        """没有残留就别写文件 —— 否则每次启动都写一次。"""
        tmp = tempfile.mkdtemp(prefix='myday-clean-')
        self.addCleanup(shutil.rmtree, tmp, True)
        p = Path(tmp) / 'notes.json'
        p.write_text(json.dumps({
            'version': 1,
            'notes': [{'id': 'n1', 'title': '干净的', 'tags': []}][:0] or
                     [{'id': 'n1', 'title': '干净的', 'type': 'text', 'body': '',
                       'items': [], 'pinned': False, 'archived': False}],
        }, ensure_ascii=False), encoding='utf-8')

        before = p.stat().st_mtime_ns
        srv = TestServer(data_dir=tmp)
        srv.start()
        self.addCleanup(srv.stop)

        self.assertEqual(p.stat().st_mtime_ns, before,
                         '没有残留时不该重写 notes.json')

    def test_broken_notes_file_does_not_crash_start(self):
        """notes.json 坏掉时，清理不能把服务带崩（read() 有自己的兜底）。"""
        tmp = tempfile.mkdtemp(prefix='myday-broken-')
        self.addCleanup(shutil.rmtree, tmp, True)
        (Path(tmp) / 'notes.json').write_text('{ 这不是 json', encoding='utf-8')

        srv = TestServer(data_dir=tmp)
        srv.start()          # 起得来就算过
        self.addCleanup(srv.stop)
        self.assertTrue(srv.data_dir.exists())


# ---------------- 前端静态检查 ----------------

class TestFrontendDroppedTags(unittest.TestCase):

    def test_groups_have_no_tag_entries(self):
        body = fn_body(read_js(), 'noteGroupsHtml')
        self.assertNotIn("'tag:'", body, '分组里不该再拼 tag:xxx')
        self.assertNotIn('tags', body, '分组统计里不该再读 tags')
        self.assertIn("'all'", body)
        self.assertIn("'pinned'", body)
        self.assertIn("'archived'", body)

    def test_filter_has_no_tag_branch(self):
        # 断言要写具体到代码本身 —— 只写 'tag:' 会被注释里那句
        # 「认不出来的分组键（比如旧数据里的 tag:xxx）」命中，误报。
        body = fn_body(read_js(), 'filteredNotes')
        self.assertNotIn("indexOf('tag:')", body, '筛选里不该再有 tag: 分支')
        self.assertNotIn('n.tags', body)

    def test_subline_has_no_tags(self):
        body = fn_body(read_js(), 'noteSubLine')
        self.assertNotIn('tags', body, '列表副标题不该再拼标签')

    def test_editor_has_no_tag_input(self):
        js = read_js()
        self.assertNotIn('noteTags', js, '编辑页的标签输入框该删掉了')
        self.assertNotIn('标签（逗号分隔）', js)

    def test_save_does_not_send_tags(self):
        js = read_js()
        i = js.index('function saveCurrentNote')
        seg = js[i:i + 500]
        self.assertNotIn('tags', seg, '保存请求里不该再带 tags')

    def test_new_note_does_not_send_tags(self):
        js = read_js()
        i = js.index("api('/api/notes', { method: 'POST'")
        seg = js[i:i + 120]
        self.assertNotIn('tags', seg)

    def test_home_preview_is_collapsed_by_default(self):
        """首页速览的内容默认收起（凯森要求，和手机版一致）。"""
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('homeNoteOpen[n.id] === true', body,
                      '默认收起要写成「只有明确展开过才 true」')
        self.assertNotIn('!== false', body, '旧的默认展开写法不能留着')

    def test_home_preview_shows_type_not_tags(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertNotIn('n.tags', body, '首页速览不该再读标签')
        self.assertIn('noteTypeText(n)', body, '那行应该显示类型（笔记/清单）')

    def test_no_tags_left_anywhere_but_week_badge(self):
        """整个 app.js 里除了首页顶部的教学周圆牌，不该再出现 tags。"""
        js = read_js()
        # hometags 是首页顶部「第 N 教学周」那个 DOM，跟笔记标签无关
        left = [ln for ln in js.split('\n') if 'tags' in ln and 'hometags' not in ln]
        self.assertEqual(left, [], '还有没清干净的 tags：\n' + '\n'.join(left))


if __name__ == '__main__':
    unittest.main()
