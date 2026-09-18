# -*- coding: utf-8 -*-
"""阶段 16 测试：首页速览里正文也要显示，并且正文/清单都能收放。

背景（凯森要求）：笔记的正文也要加到首页速览里；正文和清单都要有一个
像小三角那样的收放开关。
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


class TestPreviewCarriesBody(ServerTestCase):

    def make(self, title, **kw):
        body = {'title': title}
        body.update(kw)
        return self.srv.ok('/api/notes', 'POST', body)

    def preview_of(self, nid):
        hits = [p for p in self.srv.ok('/api/home')['notesPreview'] if p['id'] == nid]
        self.assertTrue(hits, '首页速览里没有这条备忘录')
        return hits[0]

    def test_short_body_comes_whole(self):
        n = self.make('随手记', type='text', body='第一行\n第二行')
        p = self.preview_of(n['id'])
        self.assertEqual(p['body'], '第一行\n第二行')
        self.assertFalse(p['bodyCut'])

    def test_long_body_is_cut_and_flagged(self):
        long_text = '啊' * (srv_mod.PREVIEW_BODY + 80)
        n = self.make('长笔记', type='text', body=long_text)
        p = self.preview_of(n['id'])
        self.assertEqual(len(p['body']), srv_mod.PREVIEW_BODY)
        self.assertTrue(p['bodyCut'], '截断了要告诉前端，好在末尾加省略号')

    def test_empty_body(self):
        n = self.make('空的', type='text')
        p = self.preview_of(n['id'])
        self.assertEqual(p['body'], '')
        self.assertFalse(p['bodyCut'])

    def test_todo_carries_body_too(self):
        n = self.make('作业', type='todo', body='说明文字',
                      items=[{'text': 'a', 'done': False}])
        p = self.preview_of(n['id'])
        self.assertEqual(p['body'], '说明文字')
        self.assertEqual(len(p['items']), 1)


class TestHomeNoteCollapseFrontend(unittest.TestCase):

    def test_caret_is_rendered(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('class="caret', body)
        self.assertIn('data-caret=', body)
        self.assertIn('homeNoteTitle', body)

    def test_caret_state_matches_open_flag(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn("homeNoteOpen[n.id] !== false", body, '默认展开')
        self.assertIn("(open ? '' : ' closed')", body)

    def test_body_is_rendered(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('homeBody', body)
        self.assertIn('esc(n.body)', body)
        self.assertIn('bodyCut', body, '被截断时要补省略号')

    def test_detail_area_can_be_hidden(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('homeNoteBody', body)

    def test_caret_click_does_not_open_the_note(self):
        body = fn_body(read_js(), 'renderHomeNotes')
        self.assertIn('data-caret', body)
        self.assertIn('stopPropagation', body, '点小三角不能跳走')
        self.assertIn('toggleHomeNote', body)

    def test_toggle_flips_and_rerenders(self):
        body = fn_body(read_js(), 'toggleHomeNote')
        self.assertIn('homeNoteOpen[noteId]', body)
        self.assertIn('renderHomeNotes', body)

    def test_state_is_kept_outside_the_data(self):
        """收放状态要存在外面，勾一下清单重画时不能把展开状态弄丢。"""
        js = read_js()
        self.assertIn('var homeNoteOpen = {}', js)
        body = fn_body(js, 'toggleHomeItem')
        self.assertNotIn('homeNoteOpen = {}', body, '勾选不该重置收放状态')

    def test_items_still_rendered(self):
        body = fn_body(read_js(), 'homeNotesHtml')
        self.assertIn('homeTodoItem', body)
        self.assertIn('data-item', body)


class TestHomeNoteCollapseCss(unittest.TestCase):

    def test_caret_style(self):
        decls = decls_for('.caret')
        self.assertEqual(decls.get('cursor'), 'pointer')

    def test_closed_caret_rotates(self):
        open_dec = decls_for('.caret::before').get('transform')
        closed_dec = decls_for('.caret.closed::before').get('transform')
        self.assertTrue(open_dec and closed_dec)
        self.assertNotEqual(open_dec, closed_dec, '收起时小三角要转个方向')

    def test_closed_body_is_hidden(self):
        self.assertEqual(decls_for('.homeNoteBody.closed').get('display'), 'none')

    def test_body_is_clamped(self):
        decls = decls_for('.homeBody')
        self.assertIn('line-clamp', ','.join(decls.keys()))
        self.assertEqual(decls.get('overflow'), 'hidden')


if __name__ == '__main__':
    unittest.main(verbosity=2)
