# -*- coding: utf-8 -*-
"""阶段 12 测试：导入课表（读教务系统导出的 xlsx，铺到各周）。

用 fixtures.timetable_xlsx() 现场合成一个 xlsx 来测，不依赖任何真实课表文件，
合成数据里的学校、课程、人名、教室全是虚构的。
"""
import base64
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'app'))
from helpers import STATIC_DIR, ServerTestCase  # noqa: E402
import fixtures  # noqa: E402
import timetable as tt  # noqa: E402

REAL = fixtures.timetable_xlsx()


class TestWeekParsing(unittest.TestCase):

    def test_ranges(self):
        self.assertEqual(tt.parse_weeks('1-2周'), [1, 2])
        self.assertEqual(tt.parse_weeks('4-17周'), list(range(4, 18)))
        self.assertEqual(tt.parse_weeks('18-18周'), [18])
        self.assertEqual(tt.parse_weeks('1-3周'), [1, 2, 3])

    def test_lists_and_singles(self):
        self.assertEqual(tt.parse_weeks('1,3,5周'), [1, 3, 5])
        self.assertEqual(tt.parse_weeks('第1、3、5周'), [1, 3, 5])
        self.assertEqual(tt.parse_weeks('7周'), [7])

    def test_odd_even(self):
        self.assertEqual(tt.parse_weeks('1-6周(单)'), [1, 3, 5])
        self.assertEqual(tt.parse_weeks('1-6周(双)'), [2, 4, 6])
        self.assertEqual(tt.parse_weeks('1-6周单周'), [1, 3, 5])

    def test_reversed_and_junk(self):
        self.assertEqual(tt.parse_weeks('17-4周'), list(range(4, 18)), '写反了也要认')
        self.assertEqual(tt.parse_weeks(''), [])
        self.assertEqual(tt.parse_weeks(None), [])
        self.assertEqual(tt.parse_weeks('待定'), [])
        self.assertEqual(tt.parse_weeks('1-99周'), list(range(1, 31)), '超范围的要截掉')


class TestCourseLine(unittest.TestCase):

    def test_full_line(self):
        one = tt.parse_course_line('测试课程甲(考试)(必修课)测试专业251{4-17周 张老师 A-101}')
        self.assertEqual(one['name'], '测试课程甲')
        self.assertEqual(one['className'], '测试专业251')
        self.assertEqual(one['teacher'], '张老师')
        self.assertEqual(one['room'], 'A-101')
        self.assertEqual(one['weeks'], list(range(4, 18)))

    def test_name_is_not_eaten_by_class(self):
        one = tt.parse_course_line('测试课程甲测试专业251{1-2周 张老师 A-101}')
        self.assertEqual(one['name'], '测试课程甲')
        self.assertEqual(one['className'], '测试专业251')

    def test_name_keeps_parentheses_hours(self):
        # 括号里的课时数要留在课程名里（全角括号统一成半角，显示更整齐）
        one = tt.parse_course_line('测试课程乙（64）(考试)(必修课)测试专业251{1-2周 张老师 A-101}')
        self.assertEqual(one['name'], '测试课程乙(64)')
        self.assertEqual(one['className'], '测试专业251')

    def test_fullwidth_parens_do_not_break_class_split(self):
        # 最后一个括号后面才是班级；全角半角混用时也要切对
        one = tt.parse_course_line('测试课程丙（三）(考查)(必修课)测试专业251{1-2周 张老师 A-101}')
        self.assertEqual(one['name'], '测试课程丙(三)')
        self.assertEqual(one['className'], '测试专业251')

    def test_class_list_with_commas(self):
        one = tt.parse_course_line('测试课程丁(考查)(必修课)测试专业251,测试专业252{1-2周 张老师 A-101}')
        self.assertEqual(one['name'], '测试课程丁')
        self.assertEqual(one['className'], '测试专业251,测试专业252')

    def test_class_split_by_last_paren(self):
        # 课程名里本身带「技术」，不能被当成班级的开头
        one = tt.parse_course_line('电力电子技术(考查)(必修课)电气自动化技术251{1-3周 宋老师 1#102}')
        self.assertEqual(one['name'], '电力电子技术')
        self.assertEqual(one['className'], '电气自动化技术251')

    def test_room_with_building_name(self):
        one = tt.parse_course_line('测试课程丙(考查)(必修课)测试专业251{1-17周 朱老师 笃学楼-308}')
        self.assertEqual(one['teacher'], '朱老师')
        self.assertEqual(one['room'], '笃学楼-308')

    def test_teacher_only_no_room(self):
        one = tt.parse_course_line('测试课程丁(考查)(必修课)测试专业251{1-2周 李老师}')
        self.assertEqual(one['teacher'], '李老师')
        self.assertEqual(one['room'], '')

    def test_no_class_no_room(self):
        one = tt.parse_course_line('测试课程戊(考查)(必修课){1-2周 王老师}')
        self.assertEqual(one['name'], '测试课程戊')
        self.assertEqual(one['className'], '')
        self.assertEqual(one['teacher'], '王老师')
        self.assertEqual(one['room'], '')

    def test_blank_and_junk(self):
        self.assertIsNone(tt.parse_course_line(''))
        self.assertIsNone(tt.parse_course_line('   '))
        one = tt.parse_course_line('体育{3-4周 赵老师 操场}')
        self.assertEqual(one['name'], '体育')
        self.assertEqual(one['weeks'], [3, 4])


class TestParseTimetable(unittest.TestCase):

    def setUp(self):
        self.parsed = tt.parse_timetable(REAL)

    def test_sheet_and_header(self):
        self.assertEqual(self.parsed['sheet'], '学生课表')
        self.assertIn('测试职业学院', self.parsed['title'])
        self.assertIn('测试同学', self.parsed['student'])

    def test_course_count(self):
        self.assertEqual(len(self.parsed['courses']), 4)

    def test_merged_two_periods_becomes_span(self):
        got = [c for c in self.parsed['courses'] if c['name'] == '测试课程甲'][0]
        self.assertEqual(got['day'], 1)
        self.assertEqual(got['periodFrom'], '1')
        self.assertEqual(got['periodTo'], '2', '两节合并的课要占两个节次')
        self.assertEqual(got['weeks'], [1, 2])
        self.assertEqual(got['room'], 'A-101')

    def test_single_row_course_has_no_span(self):
        got = [c for c in self.parsed['courses'] if c['name'] == '测试课程乙'][0]
        self.assertEqual(got['day'], 2)
        self.assertEqual(got['periodFrom'], '3')
        self.assertEqual(got['periodTo'], '3', '没合并的课只占一节')
        self.assertEqual(got['room'], 'B-202')

    def test_two_courses_in_one_cell(self):
        names = sorted(c['name'] for c in self.parsed['courses'] if c['day'] == 3)
        self.assertEqual(names, ['测试课程丁', '测试课程丙'], '一个格子里的两门课都要读出来')
        bing = [c for c in self.parsed['courses'] if c['name'] == '测试课程丙'][0]
        self.assertEqual(bing['weeks'], [1])
        ding = [c for c in self.parsed['courses'] if c['name'] == '测试课程丁'][0]
        self.assertEqual(ding['weeks'], [2, 3])

    def test_dirty_row_is_skipped_with_warning(self):
        self.assertNotIn('测试课程戊', [c['name'] for c in self.parsed['courses']])
        self.assertEqual(len(self.parsed['warnings']), 1)
        self.assertIn('没写周次', self.parsed['warnings'][0])

    def test_period_labels_only_used_and_in_row_order(self):
        self.assertEqual(tt.period_labels(self.parsed), ['1', '2', '3'])
        self.assertEqual([tt.period_label_text(l) for l in tt.period_labels(self.parsed)],
                         ['第 1 节', '第 2 节', '第 3 节'])

    def test_totals(self):
        self.assertEqual(tt.total_lessons(self.parsed), 7)
        self.assertEqual(tt.week_span(self.parsed), [1, 2, 3])

    def test_label_text(self):
        self.assertEqual(tt.period_label_text('1'), '第 1 节')
        self.assertEqual(tt.period_label_text('中午1'), '中午1')
        self.assertEqual(tt.period_label_text(''), '')


class TestMergedCellsStoredTwice(unittest.TestCase):
    """有的教务系统把合并区的值在每个格子都存一遍，不能读成两遍。"""

    def setUp(self):
        self.raw = fixtures.timetable_xlsx_filled()
        self.parsed = tt.parse_timetable(self.raw)

    def test_not_double_counted(self):
        self.assertEqual(len(self.parsed['courses']), 4)
        self.assertEqual(tt.total_lessons(self.parsed), 7)

    def test_span_still_right(self):
        jia = [c for c in self.parsed['courses'] if c['name'] == '测试课程甲'][0]
        self.assertEqual((jia['periodFrom'], jia['periodTo']), ('1', '2'))

    def test_same_result_as_normal_file(self):
        plain = tt.parse_timetable(fixtures.timetable_xlsx())
        keys = ('day', 'periodFrom', 'periodTo', 'name', 'teacher', 'room', 'weeks')
        self.assertEqual([tuple(c[k] for k in keys) for c in self.parsed['courses']],
                         [tuple(c[k] for k in keys) for c in plain['courses']])


class TestBadFiles(unittest.TestCase):

    def test_not_a_zip(self):
        with self.assertRaises(tt.TimetableError):
            tt.parse_timetable(b'this is not an xlsx at all')

    def test_empty_bytes(self):
        with self.assertRaises(tt.TimetableError):
            tt.parse_timetable(b'')

    def test_zip_without_sheets(self):
        import io
        import zipfile
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w') as z:
            z.writestr('hello.txt', 'hi')
        with self.assertRaises(tt.TimetableError):
            tt.read_xlsx(buf.getvalue())

    def test_no_header(self):
        raw = fixtures.xlsx_bytes([['随便', '写点', '东西'], ['没有', '表头', '']])
        with self.assertRaises(tt.TimetableError) as ctx:
            tt.parse_timetable(raw)
        self.assertIn('表头', str(ctx.exception))

    def test_header_but_no_courses(self):
        raw = fixtures.xlsx_bytes([['时间', '节次', '星期一'], ['上午', '1', '']])
        with self.assertRaises(tt.TimetableError):
            tt.parse_timetable(raw)


class TestImportApi(ServerTestCase):

    def snapshot(self):
        out = {}
        for name in ('settings', 'courses', 'notes', 'weather_cache'):
            p = self.srv.data_dir / (name + '.json')
            out[name] = p.read_text(encoding='utf-8') if p.exists() else ''
        return out

    def preview(self, raw=None):
        return self.srv.ok('/api/import/preview', 'POST',
                           {'content': base64.b64encode(raw if raw is not None else REAL).decode('ascii')})

    def do_import(self, mode='merge', raw=None):
        return self.srv.ok('/api/import', 'POST', {
            'content': base64.b64encode(raw if raw is not None else REAL).decode('ascii'),
            'mode': mode})

    def week_total(self, week):
        return self.srv.ok('/api/courses?week=%d' % week)['total']

    # ---------- 预览 ----------
    def test_preview_shape(self):
        plan = self.preview()
        self.assertEqual(plan['sheet'], '学生课表')
        self.assertEqual(plan['courseCount'], 4)
        self.assertEqual(plan['totalLessons'], 7)
        self.assertEqual(plan['weeks'], [1, 2, 3])
        self.assertEqual(plan['newPeriods'], ['第 1 节', '第 2 节', '第 3 节'])
        self.assertEqual(plan['reusePeriods'], [])
        self.assertEqual(len(plan['courses']), 4)
        first = plan['courses'][0]
        for key in ('day', 'dayText', 'periodFrom', 'periodTo', 'name', 'teacher',
                    'room', 'weekText', 'weeks', 'lessonCount'):
            self.assertIn(key, first, '预览缺字段 ' + key)

    def test_preview_writes_nothing(self):
        before = self.snapshot()
        self.preview()
        self.assertEqual(before, self.snapshot(), '预览阶段不能写任何数据')

    def test_preview_reports_reusable_periods(self):
        self.srv.ok('/api/settings/period', 'POST', {'label': '第 1 节'})
        plan = self.preview()
        self.assertIn('第 1 节', plan['reusePeriods'])
        self.assertEqual(plan['newPeriods'], ['第 2 节', '第 3 节'])

    # ---------- 导入 ----------
    def test_import_creates_periods_and_lessons(self):
        r = self.do_import('merge')
        self.assertEqual(r['added'], 7)
        self.assertEqual(r['weeks'], [1, 2, 3])
        self.assertEqual(r['createdPeriods'], ['第 1 节', '第 2 节', '第 3 节'])
        periods = self.srv.ok('/api/settings')['periods']
        self.assertEqual([p['label'] for p in periods], ['第 1 节', '第 2 节', '第 3 节'])
        for p in periods:
            self.assertEqual(p['start'], '', '导入不替用户猜作息，时间留空')
            self.assertEqual(p['end'], '')

    def test_lessons_land_in_every_week_of_range(self):
        self.do_import('merge')
        # 甲(1-2周) 乙(1-2周) 丙(1周) 丁(2-3周)
        self.assertEqual(self.week_total(1), 3)
        self.assertEqual(self.week_total(2), 3)
        self.assertEqual(self.week_total(3), 1)
        self.assertEqual(self.week_total(4), 0)

    def test_lesson_fields(self):
        self.do_import('merge')
        week1 = self.srv.ok('/api/courses?week=1')['list']
        jia = [c for c in week1 if c['name'] == '测试课程甲'][0]
        self.assertEqual(jia['day'], 1)
        self.assertEqual(jia['location'], 'A-101')
        self.assertEqual(jia['teacher'], '张老师')
        periods = {p['id']: p['label'] for p in self.srv.ok('/api/settings')['periods']}
        self.assertEqual(periods[jia['slot']], '第 1 节')
        self.assertEqual(periods[jia['spanEnd']], '第 2 节', '两节合并的课要写到 spanEnd')
        yi = [c for c in week1 if c['name'] == '测试课程乙'][0]
        self.assertEqual(yi['spanEnd'], '', '单节的课不该有 spanEnd')

    def test_merge_keeps_existing_courses(self):
        p = self.srv.ok('/api/settings/period', 'POST', {'label': '第 1 节'})
        self.srv.ok('/api/courses', 'POST', {'name': '我自己的课', 'week': 1, 'day': 5, 'slot': p['id']})
        self.do_import('merge')
        names = [c['name'] for c in self.srv.ok('/api/courses?week=1')['list']]
        self.assertIn('我自己的课', names, '追加导入不能删掉已有的课')
        self.assertIn('测试课程甲', names)
        self.assertEqual(len(names), 4)

    def test_overwrite_replaces_target_weeks_only(self):
        p = self.srv.ok('/api/settings/period', 'POST', {'label': '第 1 节'})
        self.srv.ok('/api/courses', 'POST', {'name': '我自己的课', 'week': 1, 'day': 5, 'slot': p['id']})
        self.srv.ok('/api/courses', 'POST', {'name': '第9周的课', 'week': 9, 'day': 5, 'slot': p['id']})
        self.do_import('overwrite')
        names = [c['name'] for c in self.srv.ok('/api/courses?week=1')['list']]
        self.assertNotIn('我自己的课', names)
        self.assertEqual(self.week_total(1), 3)
        self.assertEqual(self.week_total(9), 1, '没被导入涉及的周不能动')

    def test_import_twice_appends(self):
        self.do_import('merge')
        again = self.do_import('merge')
        self.assertEqual(again['added'], 7)
        self.assertEqual(self.week_total(1), 6, 'merge 语义是追加')

    def test_import_filled_merge_file_gives_same_lessons(self):
        """合并区重复存值的文件，导入结果要和普通文件一致。"""
        self.do_import('merge', raw=fixtures.timetable_xlsx_filled())
        self.assertEqual(self.week_total(1), 3)
        self.assertEqual(self.week_total(2), 3)
        self.assertEqual(self.week_total(3), 1)

    def test_import_makes_backup(self):
        self.do_import()
        backups = list((self.srv.data_dir / 'backups').glob('*.zip'))
        self.assertTrue(backups, '导入前应该自动备份一份')

    def test_import_persists_across_restart(self):
        from helpers import TestServer
        self.do_import()
        data_dir = str(self.srv.data_dir)
        self.srv.proc.terminate()
        self.srv.proc.wait(timeout=10)
        revived = TestServer(data_dir=data_dir)
        revived.start()
        try:
            self.assertEqual(len(revived.ok('/api/courses?week=1')['list']), 3)
            self.assertEqual([p['label'] for p in revived.ok('/api/settings')['periods']],
                             ['第 1 节', '第 2 节', '第 3 节'])
        finally:
            revived.stop()
        self.srv.proc = None

    def test_import_feeds_home(self):
        self.srv.ok('/api/settings', 'PUT', {'week1Monday': '2026-08-31'})
        self.do_import()
        home = self.srv.ok('/api/home')
        self.assertIsInstance(home['todayCount'], int)

    # ---------- 坏输入 ----------
    def test_bad_file_reports_cleanly(self):
        res = self.srv.request('/api/import', 'POST',
                               {'content': base64.b64encode(b'not a zip').decode('ascii'),
                                'mode': 'merge'})
        self.assertEqual(res['status'], 200)
        self.assertFalse(res['json']['ok'])
        self.assertEqual(res['json']['code'], 'bad_timetable')
        self.assertTrue(res['json']['error'])

    def test_missing_content_is_400(self):
        res = self.srv.request('/api/import', 'POST', {'mode': 'merge'})
        self.assertEqual(res['status'], 400)
        res = self.srv.request('/api/import/preview', 'POST', {})
        self.assertEqual(res['status'], 400)

    def test_unknown_mode_is_400(self):
        res = self.srv.request('/api/import', 'POST',
                               {'content': base64.b64encode(REAL).decode('ascii'),
                                'mode': 'whatever'})
        self.assertEqual(res['status'], 400)
        self.assertEqual(res['json']['code'], 'bad_request')

    def test_data_uri_prefix_is_tolerated(self):
        payload = 'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,' + \
                  base64.b64encode(REAL).decode('ascii')
        plan = self.srv.ok('/api/import/preview', 'POST', {'content': payload})
        self.assertEqual(plan['courseCount'], 4)

    def test_failed_import_leaves_data_untouched(self):
        before = self.snapshot()
        self.srv.request('/api/import', 'POST',
                         {'content': base64.b64encode(b'junk').decode('ascii'), 'mode': 'merge'})
        self.assertEqual(before, self.snapshot(), '解析失败不能动数据')


class TestImportFrontend(unittest.TestCase):

    def test_button_exists(self):
        html = (STATIC_DIR / 'index.html').read_text(encoding='utf-8')
        self.assertIn('id="importTt"', html)
        self.assertIn('导入课表', html)

    def test_frontend_uses_import_api(self):
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        self.assertIn("api('/api/import/preview'", js)
        self.assertIn("api('/api/import'", js)
        for fn in ('function pickTimetableFile', 'function showImportDialog', 'function finishImport'):
            self.assertIn(fn, js, 'app.js 缺少 ' + fn)
        # 课表导入同时收 xlsx 和 PDF（教务系统两种都会给）
        self.assertIn("accept = '.xlsx,.pdf'", js, '文件选择器要限定 xlsx / pdf')

    def test_import_refreshes_ui(self):
        js = (STATIC_DIR / 'app.js').read_text(encoding='utf-8')
        body = js[js.index('function finishImport'):]
        body = body[:body.index('\n}\n') + 3]
        self.assertIn('reloadSettings', body, '导完要刷新设置里的节次')
        self.assertIn('renderCourses', body, '导完要刷新课程表')


if __name__ == '__main__':
    unittest.main(verbosity=2)
