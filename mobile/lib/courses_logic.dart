/// 课程模块的纯逻辑：星期顺序、周次日期范围、整周复制、课程名校验。
///
/// 行为与电脑版对齐：星期顺序 / 周次范围文案见 `app/static/app.js` 的
/// `dayOrder` / `weekRangeText`，整周复制见 `app/store.py` 的 `copy_week`。
/// 这里不碰文件、不碰界面，纯函数好测。
library;

import 'models.dart';
import 'week.dart';

/// 课表里「星期」的一列。
class CourseDay {
  const CourseDay(this.num, this.name);

  final int num;
  final String name;
}

/// 星期列的顺序。weekStartsOn == 7 时周日排最前（和电脑版 dayOrder 一致）。
List<CourseDay> dayOrder(int weekStartsOn) {
  const names = <int, String>{
    1: '周一',
    2: '周二',
    3: '周三',
    4: '周四',
    5: '周五',
    6: '周六',
    7: '周日',
  };
  final nums = weekStartsOn == 7
      ? <int>[7, 1, 2, 3, 4, 5, 6]
      : <int>[1, 2, 3, 4, 5, 6, 7];
  return <CourseDay>[for (final n in nums) CourseDay(n, names[n]!)];
}

/// 第 N 周的日期范围文案（M月D日 - M月D日），没设置第 1 周周一时给提示。
String weekRangeText(int week, String week1Monday) {
  final monday = mondayOf(week, week1Monday);
  if (monday == null) return '（先设置第 1 周周一才有日期）';
  final start = parseIsoDate(monday)!;
  final end = start.add(const Duration(days: 6));
  String f(DateTime d) => '${d.month}月${d.day}日';
  return '${f(start)} - ${f(end)}';
}

/// 节次时间文案，没设时间时给提示（和电脑版 timeRange 一致）。
String timeRange(Period p) =>
    (p.start.isNotEmpty && p.end.isNotEmpty) ? '${p.start} - ${p.end}' : '时间未设置';

/// 节次显示名：空名字显示「未命名」（和电脑版 periodLabel 一致）。
String periodLabel(String id, List<Period> periods) {
  for (final p in periods) {
    if (p.id == id) return p.label.isEmpty ? '未命名' : p.label;
  }
  return '未命名';
}

/// 整周复制的三种策略。值与电脑版一致（'empty-only' 带连字符，别写错）。
class CopyMode {
  static const String overwrite = 'overwrite';
  static const String merge = 'merge';
  static const String emptyOnly = 'empty-only';

  static String label(String mode) {
    switch (mode) {
      case CopyMode.merge:
        return '保留两边（合并）';
      case CopyMode.emptyOnly:
        return '只填空的周';
      default:
        return '覆盖目标周';
    }
  }
}

/// 整周复制：把第 srcWeek 周的课铺到 targets 各周。
///
/// 与电脑版 `copy_week` 逐字对齐：
/// - 目标周等于来源周时跳过；
/// - 铺过去的课全部换新 id（`newId('c') + 序号`），其他字段（含 extra）原样带过去；
/// - overwrite：目标周整个换成复制的课；
/// - merge：目标周原有的在前、复制的在后；
/// - empty-only：目标周是空的才铺，有课就不动。
///
/// 返回 {目标周: 复制后那周的课数}。只改内存里的 courses，落盘由调用方负责。
Map<int, int> copyWeek(
  Courses courses,
  int srcWeek,
  List<int> targets,
  String mode,
  String Function(String prefix) newId,
) {
  final source = courses.week(srcWeek);
  final result = <int, int>{};
  for (final t in targets) {
    if (t == srcWeek) continue;
    final dest = courses.week(t);
    final fresh = <Lesson>[];
    for (final c in source) {
      fresh.add(c.copyWith(id: '${newId('c')}${fresh.length}'));
    }
    List<Lesson> finalList;
    if (mode == CopyMode.merge) {
      finalList = <Lesson>[...dest, ...fresh];
    } else if (mode == CopyMode.emptyOnly) {
      finalList = dest.isEmpty ? fresh : dest;
    } else {
      finalList = fresh;
    }
    courses.setWeek(t, finalList);
    result[t] = finalList.length;
  }
  return result;
}

/// 课程名校验。返回错误文案（与电脑版 add_course 的报错一致），通过返回 null。
String? validateCourseName(String name) =>
    name.trim().isEmpty ? '课程名不能为空' : null;
