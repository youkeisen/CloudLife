/// 教学周计算。算法与电脑版 `app/store.py` 的 `week_of` / `monday_of` 完全一致。
library;

/// 只认 `yyyy-MM-dd`（和电脑版一样，不猜别的格式）。
DateTime? parseIsoDate(String value) {
  final s = value.trim();
  if (s.isEmpty) return null;
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  final date = DateTime(y, m, d);
  // 挡住 2026-02-30 这种「能构造但不存在」的日期
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}

String pad2(int n) => n < 10 ? '0$n' : '$n';

String isoOf(DateTime d) => '${d.year}-${pad2(d.month)}-${pad2(d.day)}';

/// 两个「日期」之间差几天（用 UTC 算，避开夏令时导致的小时误差）。
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 今天是第几教学周。没设「第 1 周周一」或日期早于它，返回 null。
int? weekOf(DateTime date, String week1Monday) {
  final start = parseIsoDate(week1Monday);
  if (start == null) return null;
  final delta = daysBetween(start, date);
  if (delta < 0) return null;
  return delta ~/ 7 + 1;
}

/// 第 N 周的周一日期（`yyyy-MM-dd`）。没设置或 N 不合法返回 null。
String? mondayOf(int week, String week1Monday) {
  final start = parseIsoDate(week1Monday);
  if (start == null || week < 1) return null;
  return isoOf(start.add(Duration(days: 7 * (week - 1))));
}

/// 星期几：1=周一 … 7=周日（和电脑版、和课程数据的 day 字段一致）。
int dayOfWeek(DateTime date) => date.weekday;

/// 第 N 周那七天的日期（周一起）。
List<String> datesOfWeek(int week, String week1Monday) {
  final monday = mondayOf(week, week1Monday);
  if (monday == null) return const <String>[];
  final start = parseIsoDate(monday);
  if (start == null) return const <String>[];
  return List<String>.generate(7, (i) => isoOf(start.add(Duration(days: i))));
}
