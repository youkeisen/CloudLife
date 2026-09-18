# -*- coding: utf-8 -*-
"""阶段 1 测试：四份数据文件的生成、原子写、损坏恢复、周次计算。"""
import json
import os
import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from helpers import ServerTestCase  # noqa: E402

FILES = ('settings.json', 'courses.json', 'notes.json', 'weather_cache.json')


class TestStage1(ServerTestCase):

    def file_names(self):
        return sorted(p.name for p in self.srv.data_dir.iterdir() if p.is_file())

    def test_files_created_with_defaults(self):
        for name in FILES:
            self.assertTrue((self.srv.data_dir / name).is_file(), '缺少 ' + name)
        data = self.srv.ok('/api/bootstrap')
        s = data['settings']
        self.assertEqual(s['version'], 1)
        self.assertEqual(s['periods'], [], '默认节次必须为空')
        self.assertEqual(s['week1Monday'], '', '默认不能预置第一周日期')
        self.assertEqual(s['weatherCity']['name'], '', '默认不能预置城市')
        self.assertEqual(s['displayName'], '', '默认不能预置称呼')
        self.assertEqual(data['weekMeta']['week'], None)
        self.assertFalse(data['warnings'], '全新启动不该有警告')

    def test_no_preset_courses_or_notes(self):
        raw = json.loads((self.srv.data_dir / 'courses.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['weeks'], {}, '课程数据必须为空')
        raw = json.loads((self.srv.data_dir / 'notes.json').read_text(encoding='utf-8'))
        self.assertEqual(raw['notes'], [], '备忘录必须为空')

    def test_settings_persist_to_disk(self):
        self.srv.ok('/api/settings', 'PUT', {
            'displayName': '小王',
            'semesterName': '2026-2027 第一学期',
            'week1Monday': '2026-08-31',
            'campus': '中心校区',
        })
        on_disk = json.loads((self.srv.data_dir / 'settings.json').read_text(encoding='utf-8'))
        self.assertEqual(on_disk['displayName'], '小王')
        self.assertEqual(on_disk['campus'], '中心校区')
        self.assertEqual(on_disk['week1Monday'], '2026-08-31')
        # 重新读接口，确认内存与磁盘一致
        again = self.srv.ok('/api/settings')
        self.assertEqual(again['displayName'], '小王')

    def test_atomic_write_leaves_no_temp(self):
        self.srv.ok('/api/settings', 'PUT', {'displayName': 'A'})
        leftovers = [p.name for p in self.srv.data_dir.iterdir()
                     if p.name.endswith('.tmp') or p.name.endswith('.tmp.json')]
        self.assertEqual(leftovers, [], '原子写后应无残留临时文件：%s' % leftovers)

    def test_corrupt_settings_recovers(self):
        target = self.srv.data_dir / 'settings.json'
        target.write_text('{"version": 1, "displayName": "坏掉了"', encoding='utf-8')
        data = self.srv.ok('/api/bootstrap')
        self.assertTrue(data['warnings'], '损坏后应给出警告')
        restored = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(restored['periods'], [], '应恢复为默认内容')
        self.assertEqual(restored['displayName'], '')
        broken = [p.name for p in self.srv.data_dir.iterdir() if 'corrupt' in p.name]
        self.assertTrue(broken, '应保留损坏副本')
        # 服务仍然可用
        self.assertTrue(self.srv.ok('/api/health')['version'])

    def test_corrupt_courses_recovers(self):
        """坏 JSON 必须在读取时被发现并恢复，且不影响接口。"""
        target = self.srv.data_dir / 'courses.json'
        target.write_text('not json at all', encoding='utf-8')
        warnings_seen = self.srv.ok('/api/bootstrap')['warnings']
        self.assertTrue(any('courses.json' in w['file'] for w in warnings_seen),
                        '警告里应说明是哪个文件坏了')
        restored = json.loads(target.read_text(encoding='utf-8'))
        self.assertEqual(restored['weeks'], {})

    def test_week_calculation(self):
        today = date.today()
        start = today - timedelta(days=21)
        self.srv.ok('/api/settings', 'PUT', {'week1Monday': start.isoformat()})
        meta = self.srv.ok('/api/bootstrap')['weekMeta']
        self.assertEqual(meta['week'], 4, '距起始日 21 天应为第 4 周')
        self.assertEqual(meta['today'], today.isoformat())
        expected_range_days = 6
        start_date = date.fromisoformat(meta['weekStart'])
        end_date = date.fromisoformat(meta['weekEnd'])
        self.assertEqual((end_date - start_date).days, expected_range_days)

    def test_week_before_start_is_none(self):
        future = date.today() + timedelta(days=30)
        self.srv.ok('/api/settings', 'PUT', {'week1Monday': future.isoformat()})
        meta = self.srv.ok('/api/bootstrap')['weekMeta']
        self.assertIsNone(meta['week'], '起始日还没到时应为空')

    def test_unicode_roundtrip(self):
        self.srv.ok('/api/settings', 'PUT', {'displayName': '张三🐾', 'campus': '文昌'})
        text = (self.srv.data_dir / 'settings.json').read_text(encoding='utf-8')
        self.assertIn('张三', text)
        loaded = json.loads(text)
        self.assertEqual(loaded['displayName'], '张三🐾')


if __name__ == '__main__':
    unittest.main(verbosity=2)
