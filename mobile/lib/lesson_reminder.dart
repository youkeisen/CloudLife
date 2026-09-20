/// 上课提醒的纯逻辑（v1.6.0，需求文档第 1 条）：
/// 「给课程开始前添加提醒功能，提前多久提醒自定义」。
///
/// 这里只管算「什么时候该响、通知上写什么」，不碰通知插件、不碰文件，
/// 所以能直接拿测试喂日期算结果。真正排通知在 `notification_service.dart`。
///
/// 排的方式：**只排未来 7 天**。安卓的定时通知有数量上限（各家 ROM 从 50 到
/// 500 不等），一学期几十节课 × 十几周一下就爆了；7 天够日常用，而且每次
/// 打开 App / 改课表都会重排一遍，等于自动续上下一周。
library;

import 'models.dart';
import 'week.dart';

/// 提醒提前量的可选项（分钟）。界面上的下拉就是这几个。
/// `-1` 代表不提醒。
const List<int> remindLeadChoices = <int>[-1, 0, 5, 10, 15, 20, 30, 60];

/// 提前量给人看的文案。
String remindLeadLabel(int minutes) {
  if (minutes < 0) return '不提醒';
  if (minutes == 0) return '上课时提醒';
  if (minutes == 60) return '提前 1 小时';
  return '提前 $minutes 分钟';
}

/// 一条待排的提醒。
class LessonReminder {
  LessonReminder({
    required this.lessonId,
    required this.title,
    required this.body,
    required this.when,
  });

  final String lessonId;
  final String title;
  final String body;
  final DateTime when;

  /// 通知 id 用它（同一节课固定一个 id，重排时覆盖而不是堆一串）。
  int get noteId => 'lesson:$lessonId'.hashCode & 0x7fffffff;

  @override
  String toString() => 'LessonReminder($lessonId, $when, $title)';
}

/// 算出 [from] 起未来 [days] 天内该排的所有上课提醒。
///
/// - `settings.lessonRemindMinutes < 0` → 返回空（用户关了提醒）；
/// - 没设「第 1 周周一」或算不出教学周 → 返回空；
/// - 节次没填开始时间的那节课跳过（没时间就没法提醒）；
/// - 每节课只排**最早那一次**：同一周的同一节次只对应一个具体日期，
///   所以不会出现「一周排两次」。
List<LessonReminder> lessonReminders({
  required Settings settings,
  required Courses courses,
  DateTime? from,
  int days = 7,
}) {
  final lead = settings.lessonRemindMinutes;
  if (lead < 0) return const <LessonReminder>[];
  if (settings.week1Monday.isEmpty) return const <LessonReminder>[];

  final start = from ?? DateTime.now();
  final out = <LessonReminder>[];

  // 补齐节次表：id -> 开始分钟数
  final periodStart = <String, int>{};
  final periodLabel = <String, String>{};
  for (final p in settings.periods) {
    final m = minutesOfHhmm(p.start);
    if (m != null) periodStart[p.id] = m;
    periodLabel[p.id] = p.label;
  }

  final today = dateOnly(start);
  // 多算一天，把「提前量跨到前一天」的情况也带进来
  for (var i = -1; i <= days; i++) {
    final day = today.add(Duration(days: i));
    final week = weekOf(day, settings.week1Monday);
    if (week == null || week < 1) continue;
    for (final lesson in courses.week(week)) {
      if (lesson.day != day.weekday) continue;
      final begin = periodStart[lesson.slot];
      if (begin == null) continue;
      final classAt = DateTime(day.year, day.month, day.day,
          begin ~/ 60, begin % 60);
      final when = classAt.subtract(Duration(minutes: lead));
      if (!when.isAfter(start)) continue;
      final label = periodLabel[lesson.slot] ?? '';
      final name = lesson.name.isEmpty ? '有课' : lesson.name;
      final bits = <String>[
        if (label.isNotEmpty) label,
        lesson.location,
      ].where((s) => s.isNotEmpty).join(' · ');
      out.add(LessonReminder(
        lessonId: lesson.id,
        title: '${lead == 0 ? '该上课了' : '快要上课了'}：$name',
        body: bits.isEmpty
            ? (lead == 0 ? '现在开始上课' : '$lead 分钟后开始上课')
            : '$bits${lead == 0 ? ' · 现在开始' : ' · $lead 分钟后'}',
        when: when,
      ));
    }
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

/// `HH:MM` → 当天 0 点起的分钟数；解析不了返回 null。
/// （和 home_logic 的同名函数一个意思，这里独立一份免得纯逻辑模块互相依赖。）
int? minutesOfHhmm(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}
