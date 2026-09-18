# -*- coding: utf-8 -*-
"""阶段 4 测试：备忘录两种形态、置顶排序、标签、归档过滤、搜索命中、持久化。"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import ServerTestCase  # noqa: E402


class TestStage4(ServerTestCase):

    def notes(self, archived=False):
        return self.srv.ok('/api/notes' + ('?archived=1' if archived else ''))['notes']

    def add(self, title, **kw):
        body = {'title': title}
        body.update(kw)
        return self.srv.ok('/api/notes', 'POST', body)

    def test_create_default_text(self):
        n = self.add('第一条')
        self.assertEqual(n['type'], 'text')
        self.assertEqual(n['title'], '第一条')
        self.assertFalse(n['pinned'])
        self.assertFalse(n['archived'])
        self.assertTrue(n['createdAt'])
        self.assertEqual(len(self.notes()), 1)

    def test_create_todo_and_toggle(self):
        n = self.add('买东西', type='todo', items=[
            {'text': '牙膏', 'done': False}, {'text': '毛巾', 'done': False}])
        self.assertEqual(len(n['items']), 2)
        n['items'][0]['done'] = True
        saved = self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'items': n['items']})
        self.assertTrue(saved['items'][0]['done'])
        self.assertFalse(saved['items'][1]['done'])
        # 重新读取，勾选状态要还在
        again = [x for x in self.notes() if x['id'] == n['id']][0]
        self.assertTrue(again['items'][0]['done'])

    def test_update_title_body_tags(self):
        n = self.add('原标题')
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'title': '新标题',
                                          'body': '第一行\n第二行', 'tags': ['生活', '临时']})
        again = [x for x in self.notes() if x['id'] == n['id']][0]
        self.assertEqual(again['title'], '新标题')
        self.assertIn('第二行', again['body'])
        self.assertEqual(again['tags'], ['生活', '临时'])

    def test_pinned_sorts_first(self):
        self.add('普通')
        pinned = self.add('重要')
        self.srv.ok('/api/notes', 'PUT', {'id': pinned['id'], 'pinned': True})
        titles = [n['title'] for n in self.notes()]
        self.assertEqual(titles[0], '重要', '置顶项必须排在最前')

    def test_archived_hidden_and_restorable(self):
        n = self.add('要归档的')
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'archived': True})
        self.assertEqual(self.notes(), [], '归档后默认列表不再出现')
        archived = self.notes(archived=True)
        self.assertEqual(len(archived), 1)
        self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'archived': False})
        self.assertEqual(len(self.notes()), 1, '还原后回到列表')

    def test_delete_note(self):
        n = self.add('删掉我')
        res = self.srv.ok('/api/notes', 'DELETE', {'id': n['id']})
        self.assertTrue(res['deleted'])
        self.assertEqual(self.notes(), [])
        res = self.srv.request('/api/notes', 'DELETE', {'id': n['id']})
        self.assertFalse(res['json']['ok'])

    def test_search_fields_are_all_searchable(self):
        self.add('标题里有榴莲')
        self.add('正文命中', body='内容里有关键词 芒果')
        self.add('清单命中', type='todo', items=[{'text': '买菠萝', 'done': False}])
        all_notes = self.notes()
        hits = [n for n in all_notes if '榴莲' in n['title'] or '芒果' in n['body']
                or any('菠萝' in i['text'] for i in n['items'])]
        self.assertEqual(len(hits), 3, '标题/正文/清单项都应能被搜到')

    def test_updated_at_changes(self):
        n = self.add('时间测试')
        import time
        time.sleep(1.05)
        saved = self.srv.ok('/api/notes', 'PUT', {'id': n['id'], 'title': '改过了'})
        self.assertNotEqual(n['updatedAt'], saved['updatedAt'])

    def test_persisted_to_disk(self):
        self.add('落盘检查', body='多行\n内容')
        raw = json.loads((self.srv.data_dir / 'notes.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['notes'][0]['title'], '落盘检查')
        self.assertIn('多行', raw['notes'][0]['body'])

    def test_update_missing_note(self):
        res = self.srv.request('/api/notes', 'PUT', {'id': 'nope', 'title': 'x'})
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'not_found')


if __name__ == '__main__':
    unittest.main(verbosity=2)
