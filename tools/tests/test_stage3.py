# -*- coding: utf-8 -*-
"""阶段 3 测试：课程的增删改、周隔离、整周复制三种策略、清空。"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import ServerTestCase  # noqa: E402


class TestStage3(ServerTestCase):

    def setUp(self):
        ServerTestCase.setUp(self)
        self.p1 = self.srv.ok('/api/settings/period', 'POST', {'label': '第一节', 'start': '08:00', 'end': '09:00'})
        self.p2 = self.srv.ok('/api/settings/period', 'POST', {'label': '第二节', 'start': '09:10', 'end': '10:00'})

    def add(self, name='某课', week=1, day=1, slot=None, **kw):
        body = {'name': name, 'week': week, 'day': day, 'slot': slot or self.p1['id']}
        body.update(kw)
        return self.srv.ok('/api/courses', 'POST', body)

    def week(self, n):
        return self.srv.ok('/api/courses?week=%d' % n)

    def test_add_and_list(self):
        item = self.add('高等数学', location='A 楼 302', teacher='李老师')
        got = self.week(1)
        self.assertEqual(got['total'], 1)
        self.assertEqual(got['list'][0]['name'], '高等数学')
        self.assertEqual(got['list'][0]['location'], 'A 楼 302')
        self.assertEqual(got['list'][0]['teacher'], '李老师')
        self.assertEqual(item['id'], got['list'][0]['id'])

    def test_empty_name_rejected(self):
        res = self.srv.request('/api/courses', 'POST',
                               {'name': '  ', 'week': 1, 'day': 1, 'slot': self.p1['id']})
        self.assertEqual(res['json']['code'], 'bad_request')
        self.assertEqual(self.week(1)['total'], 0)

    def test_missing_slot_rejected(self):
        res = self.srv.request('/api/courses', 'POST', {'name': 'x', 'week': 1, 'day': 1})
        self.assertEqual(res['json']['code'], 'bad_request')

    def test_update_course(self):
        item = self.add('旧名字')
        self.srv.ok('/api/courses', 'PUT', {'id': item['id'], 'name': '新名字', 'location': 'B 楼'})
        got = self.week(1)['list'][0]
        self.assertEqual(got['name'], '新名字')
        self.assertEqual(got['location'], 'B 楼')

    def test_update_move_to_other_week(self):
        item = self.add('要搬家的课', week=1)
        self.srv.ok('/api/courses', 'PUT', {'id': item['id'], 'week': 5, 'name': '要搬家的课'})
        self.assertEqual(self.week(1)['total'], 0, '原周不该还有它')
        got5 = self.week(5)
        self.assertEqual(got5['total'], 1)
        self.assertEqual(got5['list'][0]['id'], item['id'])

    def test_delete_course(self):
        item = self.add()
        res = self.srv.ok('/api/courses', 'DELETE', {'id': item['id']})
        self.assertTrue(res['deleted'])
        self.assertEqual(self.week(1)['total'], 0)
        res = self.srv.request('/api/courses', 'DELETE', {'id': item['id']})
        self.assertFalse(res['json']['ok'])

    def test_weeks_are_isolated(self):
        self.add('周一的课', week=1)
        self.assertEqual(self.week(2)['total'], 0)
        self.add('周二的课', week=2, day=2, slot=self.p2['id'])
        self.assertEqual(self.week(1)['total'], 1)
        self.assertEqual(self.week(2)['total'], 1)
        self.assertEqual(self.week(2)['list'][0]['name'], '周二的课')

    def test_span_course_stored(self):
        self.add('连堂课', spanEnd=self.p2['id'])
        got = self.week(1)['list'][0]
        self.assertEqual(got['spanEnd'], self.p2['id'])

    def test_copy_overwrite(self):
        self.add('A', week=1)
        self.add('B', week=1)
        self.add('旧的', week=3)
        res = self.srv.ok('/api/courses/copy', 'POST', {'from': 1, 'to': [3, 4], 'mode': 'overwrite'})
        self.assertEqual(res['result']['3'], 2)
        self.assertEqual(res['result']['4'], 2)
        names = sorted(c['name'] for c in self.week(3)['list'])
        self.assertEqual(names, ['A', 'B'], '覆盖后目标周应只剩复制来的课')
        self.assertEqual(self.week(1)['total'], 2, '源周不受影响')

    def test_copy_merge(self):
        self.add('A', week=1)
        self.add('旧的', week=3)
        res = self.srv.ok('/api/courses/copy', 'POST', {'from': 1, 'to': [3], 'mode': 'merge'})
        self.assertEqual(res['result']['3'], 2)
        names = sorted(c['name'] for c in self.week(3)['list'])
        self.assertEqual(names, ['A', '旧的'])

    def test_copy_empty_only(self):
        self.add('A', week=1)
        self.add('旧的', week=3)
        res = self.srv.ok('/api/courses/copy', 'POST', {'from': 1, 'to': [3, 4], 'mode': 'empty-only'})
        self.assertEqual(res['result']['3'], 1, '非空周应被跳过')
        self.assertEqual(res['result']['4'], 1, '空周应写入')
        self.assertEqual([c['name'] for c in self.week(3)['list']], ['旧的'])

    def test_copy_ids_unique(self):
        self.add('A', week=1)
        self.srv.ok('/api/courses/copy', 'POST', {'from': 1, 'to': [2, 3], 'mode': 'overwrite'})
        ids = [c['id'] for c in self.week(2)['list']] + [c['id'] for c in self.week(3)['list']]
        self.assertEqual(len(ids), len(set(ids)), '复制出的课程 id 必须唯一')

    def test_copy_bad_mode(self):
        res = self.srv.request('/api/courses/copy', 'POST', {'from': 1, 'to': [2], 'mode': 'nope'})
        self.assertEqual(res['json']['code'], 'bad_request')

    def test_clear_week(self):
        self.add('A', week=2)
        self.add('B', week=2)
        self.add('C', week=3)
        self.srv.ok('/api/courses/clear', 'POST', {'week': 2})
        self.assertEqual(self.week(2)['total'], 0)
        self.assertEqual(self.week(3)['total'], 1, '只清指定周')

    def test_persisted_to_disk(self):
        self.add('落盘检查', week=2)
        raw = json.loads((self.srv.data_dir / 'courses.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['weeks']['2'][0]['name'], '落盘检查')


if __name__ == '__main__':
    unittest.main(verbosity=2)
