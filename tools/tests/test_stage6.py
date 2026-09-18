# -*- coding: utf-8 -*-
"""阶段 6 测试：首页聚合 —— 今日课程状态、天气三种态、备忘速览顺序。"""
import sys
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import ServerTestCase  # noqa: E402
import weather as wx  # noqa: E402
import fixtures  # noqa: E402
import server as srv_mod  # noqa: E402

CST = timezone(timedelta(hours=8))


class TestLessonStates(unittest.TestCase):
    """纯函数用例：给定「当前分钟数」，验证状态、排序、下一节（不依赖真实时间）。"""

    def build(self):
        periods = [
            {'id': 'p1', 'label': '上午', 'start': '08:10', 'end': '09:50'},
            {'id': 'p2', 'label': '中午', 'start': '12:20', 'end': '13:50'},
            {'id': 'p3', 'label': '晚上', 'start': '18:30', 'end': '20:10'},
        ]
        lessons = [
            {'id': 'c1', 'day': 1, 'slot': 'p3', 'spanEnd': '', 'name': '晚课'},
            {'id': 'c2', 'day': 1, 'slot': 'p1', 'spanEnd': '', 'name': '早课'},
            {'id': 'c3', 'day': 1, 'slot': 'p2', 'spanEnd': '', 'name': '午课'},
        ]
        return lessons, periods

    def states(self, now_min):
        lessons, periods = self.build()
        return {x['lesson']['name']: x for x in srv_mod.compute_lesson_states(lessons, periods, now_min)}

    def test_order_always_by_time(self):
        lessons, periods = self.build()
        for now_min in (0, 8 * 60 + 15, 12 * 60 + 30, 19 * 60, 23 * 60 + 59):
            got = [x['lesson']['name'] for x in srv_mod.compute_lesson_states(lessons, periods, now_min)]
            self.assertEqual(got, ['早课', '午课', '晚课'], '排序错了 @%d' % now_min)

    def test_before_all(self):
        st = self.states(6 * 60)
        self.assertEqual(st['早课']['status'], 'upcoming')
        self.assertTrue(st['早课']['next'])
        self.assertFalse(st['午课']['next'], '只标记最近的一节')

    def test_during_first(self):
        st = self.states(8 * 60 + 20)
        self.assertEqual(st['早课']['status'], 'now')
        self.assertEqual(st['午课']['status'], 'upcoming')
        self.assertTrue(st['午课']['next'])
        self.assertEqual(st['晚课']['status'], 'upcoming')

    def test_between(self):
        st = self.states(10 * 60)
        self.assertEqual(st['早课']['status'], 'done')
        self.assertEqual(st['午课']['status'], 'upcoming')
        self.assertEqual(st['晚课']['status'], 'upcoming')

    def test_after_all(self):
        st = self.states(21 * 60)
        self.assertEqual([st[k]['status'] for k in ('早课', '午课', '晚课')],
                         ['done', 'done', 'done'])
        self.assertFalse(any(st[k]['next'] for k in st))

    def test_missing_time_goes_last(self):
        periods = [{'id': 'p1', 'label': '没填时间', 'start': '', 'end': ''},
                   {'id': 'p2', 'label': '上午', 'start': '08:10', 'end': '09:50'}]
        lessons = [{'id': 'c1', 'slot': 'p1', 'name': '没时间的课'},
                   {'id': 'c2', 'slot': 'p2', 'name': '有时间的课'}]
        got = srv_mod.compute_lesson_states(lessons, periods, 9 * 60)
        self.assertEqual([x['lesson']['name'] for x in got], ['有时间的课', '没时间的课'])
        self.assertEqual(got[1]['status'], 'unknown')
        self.assertEqual(got[1]['periodRange'], '时间未设置')

    def test_span_uses_end_period_time(self):
        periods = [{'id': 'p1', 'label': '中午', 'start': '12:20', 'end': '13:50'},
                   {'id': 'p2', 'label': '下午', 'start': '14:10', 'end': '15:50'}]
        lessons = [{'id': 'c1', 'slot': 'p1', 'spanEnd': 'p2', 'name': '连堂'}]
        got = srv_mod.compute_lesson_states(lessons, periods, 15 * 60)
        self.assertEqual(got[0]['status'], 'now', '跨节次课应算到结束节次')


class TestStage6(ServerTestCase):

    def set_week1(self, days_ago=7):
        start = (date.today() - timedelta(days=days_ago)).isoformat()
        self.srv.ok('/api/settings', 'PUT', {'week1Monday': start})
        return start

    def add_period(self, label, start, end):
        return self.srv.ok('/api/settings/period', 'POST',
                           {'label': label, 'start': start, 'end': end})

    def seed_weather_cache(self, name='测试城', hours_old=0, temp=26.4):
        import json
        when = datetime.now(CST) - timedelta(hours=hours_old)
        payload = wx.normalize(fixtures.forecast(), {'name': name, 'latitude': 31.0, 'longitude': 118.0})
        payload['current']['temp'] = temp
        obj = {'version': 1, 'fetchedAt': when.isoformat(timespec='seconds'),
               'city': {'name': name, 'latitude': 31.0, 'longitude': 118.0},
               'payload': payload}
        (self.srv.data_dir / 'weather_cache.json').write_text(
            json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')

    def add_course_today(self, name, slot_id):
        meta = self.srv.ok('/api/bootstrap')['weekMeta']
        return self.srv.ok('/api/courses', 'POST', {
            'name': name, 'week': meta['week'] or 1, 'day': meta['dow'], 'slot': slot_id})

    def test_home_basic_shape(self):
        data = self.srv.ok('/api/home')
        self.assertIn('meta', data)
        self.assertIn('todayLessons', data)
        self.assertIn('weather', data)
        self.assertIn('notesPreview', data)
        self.assertTrue(data['greeting'])

    def test_no_periods_state(self):
        data = self.srv.ok('/api/home')
        self.assertFalse(data['hasPeriods'])
        self.assertEqual(data['todayLessons'], [])

    def test_lessons_sorted_by_time(self):
        """接口层只验排序（不依赖当前时刻），状态逻辑由纯函数用例覆盖。"""
        self.set_week1(7)
        late = self.add_period('晚一点', '20:00', '21:00')
        early = self.add_period('早一点', '08:00', '09:00')
        noon = self.add_period('中间', '12:00', '13:00')
        self.add_course_today('晚课', late['id'])
        self.add_course_today('早课', early['id'])
        self.add_course_today('午课', noon['id'])
        data = self.srv.ok('/api/home')
        labels = [x['periodLabel'] for x in data['todayLessons']]
        self.assertEqual(labels, ['早一点', '中间', '晚一点'])
        self.assertEqual(data['todayCount'], 3)

    def test_lessons_only_today(self):
        self.set_week1(7)
        p = self.add_period('第一节', '08:00', '09:00')
        meta = self.srv.ok('/api/bootstrap')['weekMeta']
        self.srv.ok('/api/courses', 'POST', {'name': '今天的课', 'week': meta['week'],
                                             'day': meta['dow'], 'slot': p['id']})
        other_day = 1 if meta['dow'] != 1 else 2
        self.srv.ok('/api/courses', 'POST', {'name': '别的天', 'week': meta['week'],
                                             'day': other_day, 'slot': p['id']})
        data = self.srv.ok('/api/home')
        names = [x['lesson']['name'] for x in data['todayLessons']]
        self.assertEqual(names, ['今天的课'])

    def test_weather_no_city_state(self):
        data = self.srv.ok('/api/home')
        self.assertEqual(data['weather']['state'], 'no_city')

    def test_weather_ok_state(self):
        self.srv.ok('/api/settings', 'PUT', {
            'weatherCity': {'name': '测试城', 'latitude': 31.0, 'longitude': 118.0,
                            'timezone': 'Asia/Shanghai'},
            'refreshMinutes': 0})
        self.seed_weather_cache()
        data = self.srv.ok('/api/home')
        self.assertEqual(data['weather']['state'], 'ok')
        self.assertFalse(data['weather']['stale'])
        self.assertEqual(data['weather']['payload']['current']['temp'], 26.4)

    def test_weather_error_state_is_reported(self):
        # 越界坐标必然请求失败
        self.srv.ok('/api/settings', 'PUT', {
            'weatherCity': {'name': '不存在的地方', 'latitude': 9999.0, 'longitude': 9999.0,
                            'timezone': 'Asia/Shanghai'},
            'refreshMinutes': 30})
        data = self.srv.ok('/api/home')
        self.assertEqual(data['weather']['state'], 'error')

    def test_weather_stale_state(self):
        self.srv.ok('/api/settings', 'PUT', {
            'weatherCity': {'name': '测试城', 'latitude': 9999.0, 'longitude': 9999.0,
                            'timezone': 'Asia/Shanghai'},
            'refreshMinutes': 30})
        self.seed_weather_cache(hours_old=5)
        data = self.srv.ok('/api/home')
        self.assertEqual(data['weather']['state'], 'ok')
        self.assertTrue(data['weather']['stale'], '旧缓存应标记为过期')

    def test_notes_preview_order_and_limit(self):
        self.srv.ok('/api/notes', 'POST', {'title': '普通1', 'body': 'aaa'})
        self.srv.ok('/api/notes', 'POST', {'title': '普通2', 'body': 'bbb'})
        pinned = self.srv.ok('/api/notes', 'POST', {'title': '置顶的', 'body': 'ccc'})
        self.srv.ok('/api/notes', 'PUT', {'id': pinned['id'], 'pinned': True})
        archived = self.srv.ok('/api/notes', 'POST', {'title': '归档的'})
        self.srv.ok('/api/notes', 'PUT', {'id': archived['id'], 'archived': True})
        self.srv.ok('/api/notes', 'POST', {'title': '第四条', 'body': 'ddd'})
        data = self.srv.ok('/api/home')
        titles = [n['title'] for n in data['notesPreview']]
        self.assertEqual(len(titles), 3)
        self.assertEqual(titles[0], '置顶的', '置顶必须在最前')
        self.assertNotIn('归档的', titles, '归档不该出现在速览')

    def test_todo_preview_summary(self):
        self.srv.ok('/api/notes', 'POST', {
            'title': '清单', 'type': 'todo',
            'items': [{'text': 'a', 'done': True}, {'text': 'b', 'done': False},
                      {'text': 'c', 'done': False}, {'text': 'd', 'done': False}]})
        preview = self.srv.ok('/api/home')['notesPreview']
        self.assertEqual(preview[0]['summary'], '1/4 项完成')

    def test_greeting_changes_by_hour(self):
        data = self.srv.ok('/api/home')
        hour = datetime.now(CST).hour
        if hour < 6:
            expect = '还没睡'
        elif hour < 11:
            expect = '早上好'
        elif hour < 14:
            expect = '中午好'
        elif hour < 18:
            expect = '下午好'
        else:
            expect = '晚上好'
        self.assertEqual(data['greeting'], expect)


if __name__ == '__main__':
    unittest.main(verbosity=2)
