// 课程模块纯逻辑的测试：星期顺序、周次范围文案、整周复制三种策略、课程名校验。
// 行为基准是电脑版：dayOrder / weekRangeText（app.js）、copy_week（store.py）。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/courses_logic.dart';
import 'package:my_day_phone/models.dart';

Lesson mkLesson(String id, {int day = 1, String slot = 'p1', String spanEnd = '',
    String name = '课', String color = ''}) {
  return Lesson(
    id: id,
    day: day,
    slot: slot,
    spanEnd: spanEnd,
    name: name,
    location: 'A101',
    teacher: '老师',
    note: '',
    color: color,
  )..extra['keepMe'] = '在';
}

void main() {
  group('星期的列顺序', () {
    test('周一开头（默认）', () {
      final days = dayOrder(1);
      expect(days.map((d) => d.num).toList(), <int>[1, 2, 3, 4, 5, 6, 7]);
      expect(days.first.name, '周一');
      expect(days.last.name, '周日');
    });

    test('周日开头（weekStartsOn = 7，和电脑版一致）', () {
      final days = dayOrder(7);
      expect(days.map((d) => d.num).toList(), <int>[7, 1, 2, 3, 4, 5, 6]);
      expect(days.first.name, '周日');
      expect(days[1].name, '周一');
    });
  });

  group('周次日期范围文案', () {
    const w1 = '2026-08-31';
    test('没设置第 1 周周一时提示', () {
      expect(weekRangeText(1, ''), '（先设置第 1 周周一才有日期）');
      expect(weekRangeText(3, '乱写的'), '（先设置第 1 周周一才有日期）');
    });

    test('格式是 M月D日 - M月D日（与电脑版一致）', () {
      expect(weekRangeText(1, w1), '8月31日 - 9月6日');
      expect(weekRangeText(2, w1), '9月7日 - 9月13日');
    });

    test('跨月也对', () {
      expect(weekRangeText(5, w1), '9月28日 - 10月4日');
    });
  });

  group('节次文案', () {
    test('有时间给时间，没时间给提示', () {
      expect(timeRange(Period(id: 'p', label: '第1节', start: '08:10', end: '08:50')),
          '08:10 - 08:50');
      expect(timeRange(Period(id: 'p', label: '第1节')), '时间未设置');
    });

    test('节次名空的显示未命名，找不到的也是未命名', () {
      final periods = <Period>[Period(id: 'p1', label: '')];
      expect(periodLabel('p1', periods), '未命名');
      expect(periodLabel('nope', periods), '未命名');
      expect(periodLabel('p1', <Period>[Period(id: 'x', label: '甲')]), '未命名');
    });
  });

  group('整周复制', () {
    late Courses courses;
    var counter = 0;
    String fakeNewId(String prefix) => '${prefix}id${counter++}';

    setUp(() {
      counter = 0;
      courses = Courses();
      courses.setWeek(1, <Lesson>[
        mkLesson('a', name: '课甲', color: 'red'),
        mkLesson('b', day: 2, slot: 'p2', name: '课乙'),
      ]);
      courses.setWeek(2, <Lesson>[mkLesson('old', name: '原有课')]);
    });

    test('覆盖：目标周整个换成复制来的课，id 换新、字段保留', () {
      final r = copyWeek(courses, 1, <int>[2], CopyMode.overwrite, fakeNewId);
      expect(r[2], 2);
      final got = courses.week(2);
      expect(got.length, 2);
      expect(got.every((l) => l.id != 'a' && l.id != 'b'), isTrue,
          reason: '复制过去的课必须换新 id');
      expect(got.map((l) => l.name).toSet(), <String>{'课甲', '课乙'});
      expect(got.first.color, 'red');
      expect(got.first.extra['keepMe'], '在', reason: 'extra 也要跟着复制');
      expect(courses.week(1).length, 2, reason: '来源周不能被动到');
    });

    test('合并：目标周原有的在前、复制的在后', () {
      copyWeek(courses, 1, <int>[2], CopyMode.merge, fakeNewId);
      final got = courses.week(2);
      expect(got.length, 3);
      expect(got.first.id, 'old', reason: '原有的排前面');
      expect(got.last.name, '课乙');
    });

    test('只填空的周：有课的周不动，空的周才铺', () {
      courses.setWeek(3, <Lesson>[]);
      copyWeek(courses, 1, <int>[2, 3], CopyMode.emptyOnly, fakeNewId);
      expect(courses.week(2).single.id, 'old', reason: '第 2 周有课，不动');
      expect(courses.week(3).length, 2, reason: '第 3 周是空的，铺进去');
    });

    test('目标周等于来源周时跳过', () {
      final r = copyWeek(courses, 1, <int>[1], CopyMode.overwrite, fakeNewId);
      expect(r, isEmpty);
      expect(courses.week(1).length, 2);
      expect(courses.week(1).map((l) => l.id).toSet(), <String>{'a', 'b'});
    });

    test('空的来源周也能复制（铺成空周）', () {
      courses.setWeek(4, <Lesson>[mkLesson('x')]);
      copyWeek(courses, 9, <int>[4], CopyMode.overwrite, fakeNewId);
      expect(courses.week(4), isEmpty);
      expect(courses.weeks.containsKey(4), isTrue,
          reason: '电脑版 save_week 语义：清空的周也保留键');
    });
  });

  group('课程名校验', () {
    test('空名字给电脑版同款报错文案', () {
      expect(validateCourseName(''), '课程名不能为空');
      expect(validateCourseName('   '), '课程名不能为空');
    });

    test('正常名字通过', () {
      expect(validateCourseName(' 高等数学 '), isNull);
    });
  });
}
