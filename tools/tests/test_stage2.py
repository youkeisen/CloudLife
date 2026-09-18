# -*- coding: utf-8 -*-
"""阶段 2 测试：设置读写、节次增删改排序、被占用节次的删除保护。"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import ServerTestCase  # noqa: E402


def write_json(path, obj):
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')


class TestStage2(ServerTestCase):

    def add(self, label='节次', start='08:00', end='09:00'):
        return self.srv.ok('/api/settings/period', 'POST',
                           {'label': label, 'start': start, 'end': end})

    def settings(self):
        return self.srv.ok('/api/settings')

    def test_add_period(self):
        p1 = self.add('第一节')
        self.assertEqual(p1['id'], 'p1')
        p2 = self.add('第二节')
        self.assertEqual(p2['id'], 'p2')
        periods = self.settings()['periods']
        self.assertEqual([p['id'] for p in periods], ['p1', 'p2'])
        on_disk = json.loads((self.srv.data_dir / 'settings.json').read_text(encoding='utf-8'))
        self.assertEqual(on_disk['periods'][0]['label'], '第一节')

    def test_rapid_add_ids_unique(self):
        ids = [self.add('p%d' % i)['id'] for i in range(5)]
        self.assertEqual(len(ids), len(set(ids)), '连续添加时 id 不能重复')

    def test_update_period(self):
        p = self.add('旧名字')
        self.srv.ok('/api/settings/period', 'PUT',
                    {'id': p['id'], 'label': '新名字', 'start': '10:00', 'end': '11:40'})
        got = self.settings()['periods'][0]
        self.assertEqual(got['label'], '新名字')
        self.assertEqual(got['start'], '10:00')
        self.assertEqual(got['end'], '11:40')

    def test_move_period(self):
        a = self.add('A')
        b = self.add('B')
        res = self.srv.ok('/api/settings/period/move', 'POST', {'id': b['id'], 'direction': 'up'})
        self.assertTrue(res['moved'])
        self.assertEqual([p['id'] for p in self.settings()['periods']], [b['id'], a['id']])
        # 已在最顶端时不能再上移，且不能报错
        res = self.srv.ok('/api/settings/period/move', 'POST', {'id': b['id'], 'direction': 'up'})
        self.assertFalse(res['moved'])

    def test_update_settings_keeps_periods(self):
        self.add('A')
        self.srv.ok('/api/settings', 'PUT', {'displayName': '小明'})
        periods = self.settings()['periods']
        self.assertEqual(len(periods), 1, '改基本设置不能丢掉节次')
        self.assertEqual(self.settings()['displayName'], '小明')

    def test_delete_unused_period(self):
        p = self.add('A')
        res = self.srv.ok('/api/settings/period', 'DELETE', {'id': p['id'], 'mode': 'cancel'})
        self.assertTrue(res['deleted'])
        self.assertEqual(self.settings()['periods'], [])

    def seed_course_on(self, period_id, week='1'):
        write_json(self.srv.data_dir / 'courses.json', {
            'version': 1,
            'weeks': {week: [
                {'id': 'c1', 'day': 1, 'slot': period_id, 'spanEnd': '',
                 'name': '某课', 'location': 'A 楼', 'teacher': '', 'note': '', 'color': ''}
            ]}
        })

    def test_delete_used_period_needs_confirm(self):
        p = self.add('A')
        self.add('B')
        self.seed_course_on(p['id'])
        res = self.srv.ok('/api/settings/period', 'DELETE', {'id': p['id'], 'mode': 'cancel'})
        self.assertEqual(res['used'], 1)
        self.assertTrue(res['needConfirm'])
        self.assertFalse(res['deleted'])
        self.assertEqual(len(self.settings()['periods']), 2, '未确认前不能删')

    def test_delete_used_period_move(self):
        p = self.add('A')
        b = self.add('B')
        self.seed_course_on(p['id'])
        res = self.srv.ok('/api/settings/period', 'DELETE', {'id': p['id'], 'mode': 'move'})
        self.assertTrue(res['deleted'])
        self.assertEqual([x['id'] for x in self.settings()['periods']], [b['id']])
        raw = json.loads((self.srv.data_dir / 'courses.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['weeks']['1'][0]['slot'], b['id'], '课程应改挂到剩余节次')

    def test_delete_used_period_drop(self):
        p = self.add('A')
        self.add('B')
        self.seed_course_on(p['id'])
        res = self.srv.ok('/api/settings/period', 'DELETE', {'id': p['id'], 'mode': 'drop'})
        self.assertTrue(res['deleted'])
        raw = json.loads((self.srv.data_dir / 'courses.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['weeks']['1'], [], '课程应被一并删除')

    def test_theme_and_week_start_persist(self):
        self.srv.ok('/api/settings', 'PUT', {'theme': 'dark', 'weekStartsOn': 7})
        s = self.settings()
        self.assertEqual(s['theme'], 'dark')
        self.assertEqual(s['weekStartsOn'], 7)

    def test_missing_id_is_bad_request(self):
        res = self.srv.request('/api/settings/period', 'DELETE', {})
        self.assertEqual(res['status'], 200)
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'bad_request')


if __name__ == '__main__':
    unittest.main(verbosity=2)
