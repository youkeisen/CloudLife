# -*- coding: utf-8 -*-
"""阶段 13 测试：备忘录的保存键，以及左边列表「未分类」这个误导人的标签。

背景（凯森反馈）：
    1. 备忘录编辑区没有保存键，想要一个。
    2. 左边列表显示「未分类」，但这条笔记的类别明明就是「笔记」——
       原来那行是拿「标签」当类别显示，没标签就写「未分类」，看着像没归类。
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import STATIC_DIR, ServerTestCase  # noqa: E402


def read_js():
    return (STATIC_DIR / 'app.js').read_text(encoding='utf-8')


def read_html():
    return (STATIC_DIR / 'index.html').read_text(encoding='utf-8')


def fn_body(js, name):
    """取一个顶层函数的函数体（顶层函数的收尾 } 一定在行首）。"""
    start = js.index('function ' + name)
    end = js.index('\n}\n', start)
    return js[start:end + 3]


class TestNoMisleadingCategory(unittest.TestCase):

    def test_uncategorized_literal_is_gone(self):
        js = read_js()
        self.assertNotIn("'未分类'", js, '不该再把「未分类」当类别显示')
        self.assertNotIn('"未分类"', js)
        self.assertNotIn('未分类', read_html())

    def test_sub_line_builder_exists(self):
        js = read_js()
        for fn in ('function noteSubLine', 'function noteSummary', 'function noteTypeText'):
            self.assertIn(fn, js)
        body = fn_body(js, 'noteSubLine')
        self.assertIn('noteTypeText', body, '第二行要以「类型」开头')
        self.assertIn('tags', body, '有标签时再带上标签')

    def test_type_text_mapping(self):
        js = read_js()
        body = fn_body(js, 'noteTypeText')
        self.assertIn("'清单'", body)
        self.assertIn("'笔记'", body)

    def test_list_row_uses_sub_line(self):
        js = read_js()
        body = fn_body(js, 'renderNotesList')
        self.assertIn('noteSubLine', body)
        self.assertIn("class=\"p\"", body)

    def test_home_preview_uses_type_when_no_tags(self):
        js = read_js()
        body = fn_body(js, 'homeNotesHtml')
        self.assertIn('noteTypeText', body)
        self.assertNotIn('未分类', body)


class TestSaveButton(unittest.TestCase):

    def test_save_button_in_detail_panel(self):
        js = read_js()
        body = fn_body(js, 'renderNoteDetail')
        self.assertIn('id="saveNote"', body, '编辑区要有保存键')
        self.assertIn('>保存<', body)
        self.assertIn('id="noteStatus"', body, '要有个已保存/有改动的状态提示')
        self.assertIn("$('saveNote').addEventListener", body, '保存键要真的绑上事件')

    def test_save_flushes_pending_debounce(self):
        js = read_js()
        body = fn_body(js, 'renderNoteDetail')
        save_block = body[body.index("$('saveNote').addEventListener"):]
        save_block = save_block[:save_block.index('});') + 3]
        self.assertIn('clearTimeout(saveTimer)', save_block, '点保存要先取消待执行的自动保存')
        self.assertIn('saveCurrentNote', save_block)
        self.assertIn('refreshNoteRow', save_block, '存完要顺手刷新左边那一行')

    def test_autosave_still_kept(self):
        js = read_js()
        body = fn_body(js, 'scheduleNoteSave')
        self.assertIn('saveTimer', body, '自动保存要保留，不能只靠手动点')

    def test_status_tracks_dirty_state(self):
        js = read_js()
        self.assertIn('function renderNoteStatus', js)
        sched = fn_body(js, 'scheduleNoteSave')
        self.assertIn('noteDirty = true', sched)
        self.assertIn('renderNoteStatus', sched)
        save = fn_body(js, 'saveCurrentNote')
        self.assertIn('noteDirty = false', save)
        self.assertIn('renderNoteStatus', save)

    def test_switching_note_flushes_before_leaving(self):
        """刚敲完就点另一条，改动不能丢。"""
        js = read_js()
        body = fn_body(js, 'renderNotesList')
        click_block = body[body.index("querySelectorAll('#notelist .nrow')"):]
        self.assertIn('clearTimeout(saveTimer)', click_block)
        self.assertIn('saveCurrentNote', click_block)
        self.assertIn('curNoteId', click_block)

    def test_row_refresh_does_not_rebuild_detail(self):
        """刷新列表那一行时不能重建编辑区，否则输入框会掉焦点。"""
        js = read_js()
        body = fn_body(js, 'refreshNoteRow')
        self.assertIn("querySelector('#notelist .nrow", body)
        self.assertNotIn('renderNoteDetail', body)
        self.assertNotIn('innerHTML', body)


class TestNoteApiContract(ServerTestCase):
    """保存键依赖的后端契约：字段要能原样存进去、原样读回来。"""

    def test_round_trip_all_fields(self):
        n = self.srv.ok('/api/notes', 'POST', {'title': '标题', 'type': 'text'})
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'title': '改过的标题',
                                          'type': 'text', 'body': '第一行\n第二行',
                                          'tags': ['学习', '杂事'], 'pinned': True})
        got = [x for x in self.srv.ok('/api/notes')['notes'] if x['id'] == n['id']][0]
        self.assertEqual(got['title'], '改过的标题')
        self.assertEqual(got['body'], '第一行\n第二行')
        self.assertEqual(got['tags'], ['学习', '杂事'])
        self.assertTrue(got['pinned'])
        self.assertEqual(got['type'], 'text')

    def test_type_switch_persists(self):
        n = self.srv.ok('/api/notes', 'POST', {'title': '类型切换'})
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'type': 'todo',
                                          'items': [{'text': 'a', 'done': True},
                                                    {'text': 'b', 'done': False}]})
        got = [x for x in self.srv.ok('/api/notes')['notes'] if x['id'] == n['id']][0]
        self.assertEqual(got['type'], 'todo')
        self.assertEqual(len(got['items']), 2)

    def test_empty_note_has_no_tags(self):
        n = self.srv.ok('/api/notes', 'POST', {'title': ''})
        got = [x for x in self.srv.ok('/api/notes')['notes'] if x['id'] == n['id']][0]
        self.assertEqual(got['tags'], [], '新建的笔记没有标签——列表就该显示类型而不是「未分类」')
        self.assertEqual(got['type'], 'text')

    def test_home_preview_carries_type(self):
        self.srv.ok('/api/notes', 'POST', {'title': '甲', 'type': 'text', 'body': 'x'})
        todo = self.srv.ok('/api/notes', 'POST', {'title': '乙', 'type': 'todo',
                                                  'items': [{'text': 'a', 'done': True}]})
        preview = self.srv.ok('/api/home')['notesPreview']
        self.assertTrue(preview)
        for item in preview:
            self.assertIn('type', item, '首页速览要带上类型，才能显示「笔记/清单」而不是「未分类」')
        by_id = {p['id']: p for p in preview}
        self.assertEqual(by_id[todo['id']]['type'], 'todo')

    def test_preview_type_defaults_to_text(self):
        n = self.srv.ok('/api/notes', 'POST', {'title': '丙'})
        hit = [p for p in self.srv.ok('/api/home')['notesPreview'] if p['id'] == n['id']]
        self.assertTrue(hit)
        self.assertEqual(hit[0]['type'], 'text')


if __name__ == '__main__':
    unittest.main(verbosity=2)
