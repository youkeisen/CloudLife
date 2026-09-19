// 教学周计算的测试。算法必须和电脑版 `app/store.py` 的 week_of / monday_of 一致，
// 否则手机和电脑算出来的「第几周」会不一样。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/week.dart';

void main() {
  const monday = '2026-08-31';

  group('解析日期', () {
    test('只认 yyyy-MM-dd', () {
      expect(parseIsoDate('2026-08-31')?.day, 31);
      expect(parseIsoDate('  2026-08-31 '), isNotNull, reason: '两头空格要容忍');
      expect(parseIsoDate(''), isNull);
      expect(parseIsoDate('2026/08/31'), isNull);
      expect(parseIsoDate('2026-8'), isNull);
      expect(parseIsoDate('abc-de-fg'), isNull);
    });

    test('不存在的日期挡掉', () {
      expect(parseIsoDate('2026-02-30'), isNull);
      expect(parseIsoDate('2026-13-01'), isNull);
      expect(parseIsoDate('2026-02-29'), isNull, reason: '2026 不是闰年');
      expect(parseIsoDate('2024-02-29')?.day, 29, reason: '2024 是闰年');
    });

    test('输出补零', () {
      expect(isoOf(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('第几教学周', () {
    test('第一周周一当天就是第 1 周', () {
      expect(weekOf(DateTime(2026, 8, 31), monday), 1);
    });

    test('第一周周日还是第 1 周，第二天进第 2 周', () {
      expect(weekOf(DateTime(2026, 9, 6), monday), 1);
      expect(weekOf(DateTime(2026, 9, 7), monday), 2);
      expect(weekOf(DateTime(2026, 9, 13), monday), 2);
      expect(weekOf(DateTime(2026, 9, 14), monday), 3);
    });

    test('跨月跨年也对', () {
      expect(weekOf(DateTime(2026, 12, 31), monday), 18);
      expect(weekOf(DateTime(2027, 1, 1), monday), 18);
      expect(weekOf(DateTime(2027, 1, 4), monday), 19);
    });

    test('早于第一周、或没设置日期都返回 null', () {
      expect(weekOf(DateTime(2026, 8, 30), monday), isNull);
      expect(weekOf(DateTime(2026, 9, 1), ''), isNull);
      expect(weekOf(DateTime(2026, 9, 1), '乱写的'), isNull);
    });

    test('时间部分不影响结果', () {
      expect(weekOf(DateTime(2026, 9, 7, 23, 59, 59), monday), 2);
      expect(weekOf(DateTime(2026, 9, 7, 0, 0, 1), monday), 2);
    });
  });

  group('第 N 周的周一', () {
    test('正着算（含跨年）', () {
      expect(mondayOf(1, monday), '2026-08-31');
      expect(mondayOf(2, monday), '2026-09-07');
      expect(mondayOf(18, monday), '2026-12-28');
      expect(mondayOf(19, monday), '2027-01-04');
    });

    test('和 weekOf 能对上（来回算）', () {
      for (var w = 1; w <= 21; w++) {
        final iso = mondayOf(w, monday)!;
        expect(weekOf(parseIsoDate(iso)!, monday), w, reason: '第 $w 周对不上');
      }
    });

    test('没设置或周次非法时返回 null', () {
      expect(mondayOf(1, ''), isNull);
      expect(mondayOf(0, monday), isNull);
      expect(mondayOf(-3, monday), isNull);
    });
  });

  group('一周的七天', () {
    test('从周一到周日', () {
      final days = datesOfWeek(2, monday);
      expect(days.first, '2026-09-07');
      expect(days.last, '2026-09-13');
      expect(days.length, 7);
      expect(dayOfWeek(parseIsoDate(days.first)!), 1, reason: '周一');
      expect(dayOfWeek(parseIsoDate(days.last)!), 7, reason: '周日');
    });

    test('没设置日期时是空的', () {
      expect(datesOfWeek(1, ''), isEmpty);
    });
  });

  group('天数差', () {
    test('跨月跨年', () {
      expect(daysBetween(DateTime(2026, 8, 31), DateTime(2026, 9, 1)), 1);
      expect(daysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
      expect(daysBetween(DateTime(2026, 9, 1), DateTime(2026, 8, 31)), -1);
    });
  });
}
