# -*- coding: utf-8 -*-
"""阶段 15 测试：首页备忘录速览里显示清单内容和勾选状态。

背景（凯森要求）：首页那张「备忘录速览」卡片，清单型笔记要能看到每一项的内容
和勾没勾，而不是只写「1/2 项完成」。
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import ServerTestCase, decls_for, fn_body, read_static  # noqa: E402
import server as srv_mod  # noqa: E402


def read_js():
    return read_static('app.js')


class TestPreviewPayload(ServerTestCase):

    def make(self, title, **kw):
        body = {'title': title}
        body.update(kw)
        return self.srv.ok('/api/notes', 'POST', body)

    def preview_of(self, nid):
        hits = [p for p in self.srv.ok('/api/home')['notesPreview'] if p['id'] == nid]
        self.assertTrue(hits, '首页速览里没有这条备忘录')
        return hits[0]

    def test_todo_items_come_with_checked_state(self):
        n = self.make('作业', type='todo',
                      items=[{'text': '写作业', 'done': True}, {'text': '交作业', 'done': False}])
        p = self.preview_of(n['id'])
        self.assertEqual([i['text'] for i in p['items']], ['写作业', '交作业'])
        self.assertEqual([i['done'] for i in p['items']], [True, False])
        self.assertEqual(p['itemsTotal'], 2)
        self.assertEqual(p['itemsDone'], 1)
        self.assertEqual(p['moreItems'], 0)
        self.assertEqual(p['summary'], '1/2 项完成')

    def test_text_note_carries_no_items(self):
        n = self.make('随手记', type='text', body='第一行\n第二行')
        p = self.preview_of(n['id'])
        self.assertEqual(p['items'], [])
        self.assertEqual(p['itemsTotal'], 0)
        self.assertEqual(p['moreItems'], 0)
        self.assertEqual(p['summary'], '第一行')

    def test_long_list_is_cut_with_a_hint(self):
        items = [{'text': '第%d件事' % i, 'done': i % 2 == 0} for i in range(12)]
        n = self.make('长清单', type='todo', items=items)
        p = self.preview_of(n['id'])
        self.assertEqual(p['itemsTotal'], 12)
        self.assertEqual(len(p['items']), srv_mod.PREVIEW_ITEMS)
        self.assertEqual(p['moreItems'], 12 - srv_mod.PREVIEW_ITEMS)
        self.assertEqual(p['items'][0]['text'], '第0件事')
        self.assertEqual(p['itemsDone'], 6)

    def test_empty_todo(self):
        n = self.make('空清单', type='todo')
        p = self.preview_of(n['id'])
        self.assertEqual(p['items'], [])
        self.assertEqual(p['summary'], '0/0 项完成')

    def test_preview_keeps_only_a_few_notes(self):
        for i in range(srv_mod.PREVIEW_NOTES + 2):
            self.make('第%d条' % i, type='text', body='x')
        preview = self.srv.ok('/api/home')['notesPreview']
        self.assertEqual(len(preview), srv_mod.PREVIEW_NOTES)


class TestToggleEndpoint(ServerTestCase):

    def make(self, items):
        return self.srv.ok('/api/notes', 'POST', {'title': '清单', 'type': 'todo', 'items': items})

    def read_items(self, nid):
        note = [x for x in self.srv.ok('/api/notes?archived=1')['notes'] if x['id'] == nid][0]
        return note['items']

    def test_toggle_flips_one_item(self):
        n = self.make([{'text': 'a', 'done': False}, {'text': 'b', 'done': False}])
        saved = self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 1})
        self.assertEqual([i['done'] for i in saved['items']], [False, True])
        self.assertEqual([i['done'] for i in self.read_items(n['id'])], [False, True], '要落盘')
        self.assertEqual([i['text'] for i in self.read_items(n['id'])], ['a', 'b'], '内容不能被改')

    def test_toggle_twice_returns_to_original(self):
        n = self.make([{'text': 'a', 'done': False}])
        self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 0})
        self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 0})
        self.assertFalse(self.read_items(n['id'])[0]['done'])

    def test_toggle_does_not_lose_the_tail(self):
        """首页只带前几项，勾一项不能把没显示出来的项冲掉。"""
        items = [{'text': '第%d件事' % i, 'done': False} for i in range(12)]
        n = self.make(items)
        self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 0})
        got = self.read_items(n['id'])
        self.assertEqual(len(got), 12, '第 %d 项之后的清单项被弄丢了' % srv_mod.PREVIEW_ITEMS)
        self.assertEqual([i['text'] for i in got][-1], '第11件事')
        self.assertTrue(got[0]['done'])

    def test_toggle_keeps_note_title(self):
        n = self.make([{'text': 'a', 'done': False}])
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'title': '别被冲掉'})
        self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 0})
        note = [x for x in self.srv.ok('/api/notes?archived=1')['notes'] if x['id'] == n['id']][0]
        self.assertEqual(note['title'], '别被冲掉')
        self.assertNotIn('tags', note, '2026-09-22 起不再有标签字段')
        self.assertEqual(note['type'], 'todo')

    def test_home_summary_follows_toggle(self):
        n = self.make([{'text': 'a', 'done': False}, {'text': 'b', 'done': False}])
        self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 0})
        p = [x for x in self.srv.ok('/api/home')['notesPreview'] if x['id'] == n['id']][0]
        self.assertEqual(p['summary'], '1/2 项完成')
        self.assertEqual(p['itemsDone'], 1)

    def test_bad_input(self):
        n = self.make([{'text': 'a', 'done': False}])
        res = self.srv.request('/api/notes/toggle', 'POST', {'index': 0})
        self.assertEqual(res['status'], 400)
        res = self.srv.request('/api/notes/toggle', 'POST', {'id': n['id']})
        self.assertEqual(res['status'], 400)
        for body in ({'id': n['id'], 'index': 99}, {'id': n['id'], 'index': -1},
                     {'id': 'nope', 'index': 0}):
            res = self.srv.request('/api/notes/toggle', 'POST', body)
            self.assertNotEqual(res['status'], 500, str(body))
            self.assertFalse(res['json']['ok'])
            self.assertEqual(res['json']['code'], 'not_found')
        self.assertEqual(len(self.read_items(n['id'])), 1, '失败的操作不能改数据')

    def test_toggle_persists_across_restart(self):
        from helpers import TestServer
        n = self.make([{'text': 'a', 'done': False}])
        self.srv.ok('/api/notes/toggle', 'POST', {'id': n['id'], 'index': 0})
        data_dir = str(self.srv.data_dir)
        self.srv.proc.terminate()
        self.srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            note = [x for x in revived.ok('/api/notes?archived=1')['notes'] if x['id'] == n['id']][0]
            self.assertTrue(note['items'][0]['done'])
        finally:
            revived.stop()
        self.srv.proc = None


class TestHomeTodoFrontend(unittest.TestCase):

    def test_items_are_rendered(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('homeTodo', body)
        self.assertIn('homeTodoItem', body)
        self.assertIn('data-note-id', body)
        self.assertIn('data-item', body)

    def test_checked_state_is_visible(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn("it.done ? ' on' : ''", body)
        self.assertIn('✓', body)

    def test_truncated_hint(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('moreItems', body)
        self.assertIn('还有', body)

    def test_each_note_is_a_block(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('class="homeNote"', body)
        self.assertNotIn("style=\"padding:7px 0;border-bottom", body)

    def test_item_click_does_not_open_the_note(self):
        body = fn_body(read_js(), 'renderHomeNotes')
        self.assertIn('stopPropagation', body, '点勾选框不能把整条点开跳走')
        self.assertIn('toggleHomeItem', body)
        self.assertIn("go('notes')", body, '点整条还是要能跳备忘录')

    def test_toggle_uses_dedicated_endpoint(self):
        body = fn_body(read_js(), 'toggleHomeItem')
        self.assertIn("api('/api/notes/toggle'", body,
                      '只翻一项要用专用接口，不能整段回写（会丢没显示出来的项）')
        self.assertIn("method: 'POST'", body)
        self.assertNotIn("api('/api/notes', {", body)
        self.assertIn('renderHomeNotes', body, '勾完要重画')
        self.assertIn('itemsDone', body, '摘要要跟着更新')

    def test_failed_toggle_rolls_back(self):
        body = fn_body(read_js(), 'toggleHomeItem')
        self.assertIn('catch', body)
        self.assertIn('before', body, '失败要把界面改回去')

    def test_render_home_uses_render_home_notes(self):
        body = fn_body(read_js(), 'renderHome')
        self.assertIn('renderHomeNotes', body)


class TestHomeTodoCss(unittest.TestCase):

    def test_item_row_layout(self):
        decls = decls_for('.homeTodoItem')
        self.assertEqual(decls.get('display'), 'flex')

    def test_box_has_checked_state(self):
        decls = decls_for('.homeTodoItem .bx.on')
        self.assertIn('background', decls)
        self.assertNotEqual(decls.get('background'), 'transparent')

    def test_done_text_is_struck_through(self):
        self.assertEqual(decls_for('.homeTodoItem .tx.on').get('text-decoration'), 'line-through')

    def test_long_text_is_clipped(self):
        decls = decls_for('.homeTodoItem .tx')
        self.assertEqual(decls.get('text-overflow'), 'ellipsis')
        self.assertEqual(decls.get('white-space'), 'nowrap')


if __name__ == '__main__':
    unittest.main(verbosity=2)
