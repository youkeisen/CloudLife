# -*- coding: utf-8 -*-
"""阶段 14 测试：清单（待办）每条一行能看清、能输入。

背景（凯森反馈的截图）：
    清单里每条只剩一个小方块和一个 ×，内容框看不见也打不进字。
    根因是 CSS：`.field input{width:100%}` 把勾选框和内容框都撑成 100% 宽，
    三者挤在一个 flex 行里抢宽度，内容框被压成 0 宽。
    另外要求内容排在「清单」这两个字的下面。
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import STATIC_DIR, ServerTestCase  # noqa: E402


def read_css():
    return (STATIC_DIR / 'style.css').read_text(encoding='utf-8')


def read_js():
    return (STATIC_DIR / 'app.js').read_text(encoding='utf-8')


def css_rules():
    """把 style.css 拆成 [(选择器, {声明})]；本文件里没有 @media，够用。"""
    text = re.sub(r'/\*.*?\*/', '', read_css(), flags=re.S)
    rules = []
    for selector, body in re.findall(r'([^{}]+)\{([^{}]*)\}', text):
        decls = {}
        for part in body.split(';'):
            if ':' in part:
                key, value = part.split(':', 1)
                decls[key.strip().lower()] = value.strip()
        rules.append((' '.join(selector.split()), decls))
    return rules


def decls_for(selector):
    for sel, decls in css_rules():
        if sel == selector:
            return decls
    raise AssertionError('style.css 里找不到规则：' + selector)


def specificity(selector):
    selector = re.sub(r'\[[^\]]*\]', ' [] ', selector)
    ids = classes = types = 0
    for token in re.findall(r'#[\w-]+|\.[\w-]+|\[\]|[a-zA-Z][\w-]*|::?[\w-]+', selector):
        if token == '[]' or token.startswith('.') or token.startswith(':'):
            classes += 1
        elif token.startswith('#'):
            ids += 1
        else:
            types += 1
    return (ids, classes, types)


class TestTodoLayoutCss(unittest.TestCase):

    def test_field_input_default_is_still_full_width(self):
        """这条是祸根本身，确认它还在——下面的覆盖才有意义。"""
        decls = decls_for('.field input,.field select,.field textarea')
        self.assertEqual(decls.get('width'), '100%')

    def test_checkbox_does_not_take_full_width(self):
        sel = '.field input[type=checkbox]'
        decls = decls_for(sel)
        self.assertIn('width', decls)
        self.assertNotIn('%', decls['width'], '勾选框不能用百分比宽度')
        self.assertEqual(decls.get('flex'), 'none', '勾选框不该参与拉伸')
        self.assertIn('height', decls, '要写死尺寸，不然会被拉伸或压扁')
        self.assertGreater(specificity(sel), specificity('.field input'),
                           '要压过 .field input 的 width:100%')

    def test_todo_text_input_takes_the_rest(self):
        sel = '.todoitem input[type=text]'
        decls = decls_for(sel)
        self.assertEqual(decls.get('width'), 'auto', '必须显式回到 auto，否则还是 100%')
        self.assertEqual(decls.get('flex'), '1', '内容框要吃掉剩下的宽度')
        self.assertIn('min-width', decls, 'min-width:0 才能让 flex 真的收得住')
        self.assertGreater(specificity(sel), specificity('.field input'))

    def test_todo_row_is_a_left_aligned_flex_row(self):
        decls = decls_for('.todoitem')
        self.assertEqual(decls.get('display'), 'flex')
        self.assertNotIn('justify-content', decls, '默认左对齐，别把内容推到右边')

    def test_delete_button_does_not_shrink(self):
        decls = decls_for('.todoitem .del')
        self.assertEqual(decls.get('flex'), 'none')


def fn_body(js, name):
    """取一个顶层函数的函数体（顶层函数的收尾 } 一定在行首）。"""
    start = js.index('function ' + name)
    end = js.index('\n}\n', start)
    return js[start:end + 3]


class TestTodoMarkup(unittest.TestCase):

    def todo_markup(self):
        body = fn_body(read_js(), 'renderNoteDetail')
        return body[body.index("n.type === 'todo'"):]

    def test_list_sits_under_the_label(self):
        chunk = self.todo_markup()
        self.assertIn('<label>清单</label>', chunk)
        self.assertLess(chunk.index('<label>清单</label>'),
                        chunk.index('id="todoList"'),
                        '清单内容要排在「清单」两个字的下面')

    def test_every_row_has_checkbox_text_and_delete(self):
        chunk = self.todo_markup()
        self.assertIn('type="checkbox"', chunk)
        self.assertIn('type="text"', chunk)
        self.assertIn('class="del"', chunk)
        self.assertEqual(chunk.count('class="todoitem"'), 1, '每行一个 todoitem，模板只写一次')

    def test_text_input_has_placeholder(self):
        chunk = self.todo_markup()
        self.assertIn('placeholder=', chunk, '空行要有个提示，不然看不出哪里能打字')

    def test_add_row_button_kept(self):
        chunk = self.todo_markup()
        self.assertIn('id="addTodo"', chunk)
        body = read_js()
        self.assertIn("$('addTodo').addEventListener", body)


class TestTodoApiContract(ServerTestCase):
    """输入框存下去的内容要能原样读回来。"""

    def test_todo_items_round_trip(self):
        n = self.srv.ok('/api/notes', 'POST', {'title': '作业', 'type': 'todo'})
        items = [{'text': '第一件事', 'done': False}, {'text': '第二件事', 'done': True}]
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'type': 'todo', 'items': items})
        got = [x for x in self.srv.ok('/api/notes')['notes'] if x['id'] == n['id']][0]
        self.assertEqual([i['text'] for i in got['items']], ['第一件事', '第二件事'])
        self.assertEqual([i['done'] for i in got['items']], [False, True])

    def test_todo_progress_shows_up(self):
        n = self.srv.ok('/api/notes', 'POST', {'title': '进度', 'type': 'todo',
                                               'items': [{'text': 'a', 'done': True},
                                                         {'text': 'b', 'done': False}]})
        preview = [p for p in self.srv.ok('/api/home')['notesPreview'] if p['id'] == n['id']]
        self.assertTrue(preview)
        self.assertEqual(preview[0]['summary'], '1/2 项完成')


if __name__ == '__main__':
    unittest.main(verbosity=2)
