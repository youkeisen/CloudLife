/// 记账的纯逻辑：汇总、按日期分组、金额格式化。
///
/// 全部是纯函数 / 无副作用的类，能脱离手机单测。界面只负责画。
library;

import 'models.dart';
import 'week.dart' show pad2;

/// 月份键：`YYYY-MM`。
String monthKeyOf(DateTime d) => '${d.year}-${pad2(d.month)}';

/// 日期键：`YYYY-MM-DD`。
String dateKeyOf(DateTime d) => '${d.year}-${pad2(d.month)}-${pad2(d.day)}';

/// 从 `YYYY-MM-DD` 解析出 DateTime；解不出返回 null。
DateTime? parseDateKey(String s) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, mo, d);
  // 拦掉 2 月 31 这种「语法合法但日子不存在」的
  if (dt.month != mo || dt.day != d) return null;
  return dt;
}

/// 某个月的第一天 / 上个月 / 下个月。月份切换用。
DateTime firstDayOfMonth(int year, int month) => DateTime(year, month, 1);

DateTime shiftMonth(DateTime first, int delta) {
  final total = first.year * 12 + (first.month - 1) + delta;
  return DateTime(total ~/ 12, total % 12 + 1, 1);
}

/// 金额显示：两位小数、带千分位。
///
/// `486.5` → `486.50`；`1234567.891` → `1,234,567.89`。
String formatAmount(double v) {
  final neg = v < 0;
  final abs = v.abs();
  // 先按分四舍五入，避免 0.1+0.2 这类浮点尾巴显示成 0.30000000000000004
  final cents = (abs * 100).round();
  final yuan = cents ~/ 100;
  final frac = cents % 100;
  final y = yuan.toString();
  final buf = StringBuffer();
  for (var i = 0; i < y.length; i++) {
    if (i > 0 && (y.length - i) % 3 == 0) buf.write(',');
    buf.write(y[i]);
  }
  return '${neg ? '-' : ''}$buf.${pad2(frac)}';
}

/// 一个月的合计。
class MonthSummary {
  const MonthSummary({
    required this.expense,
    required this.income,
    required this.count,
    required this.days,
  });

  /// 总支出（正数）
  final double expense;

  /// 总收入（正数）
  final double income;

  /// 笔数
  final int count;

  /// 有记账的天数（用来算日均）
  final int days;

  double get balance => income - expense;

  /// 日均支出。没有记账的天返回 0。
  double get dailyExpense => days == 0 ? 0 : expense / days;
}

/// 算某个月的合计。month 是 `YYYY-MM`。
///
/// 「天数」按**有记账的不同日期**算，不是自然月天数——这样月中才开始
/// 记账时，日均不会因为前面空着而虚低。
MonthSummary summarizeMonth(List<LedgerRecord> records, String month) {
  var expense = 0.0;
  var income = 0.0;
  var count = 0;
  final days = <String>{};
  for (final r in records) {
    if (!r.date.startsWith(month)) continue;
    count++;
    days.add(r.date);
    if (r.isIncome) {
      income += r.amount;
    } else {
      expense += r.amount;
    }
  }
  return MonthSummary(
    expense: expense,
    income: income,
    count: count,
    days: days.length,
  );
}

/// 某个月里最大的一笔支出。
double maxExpenseOf(List<LedgerRecord> records, String month) {
  var best = 0.0;
  for (final r in records) {
    if (!r.date.startsWith(month)) continue;
    if (r.isIncome) continue;
    if (r.amount > best) best = r.amount;
  }
  return best;
}

/// 一个日期分组：同一天的账 + 当日小计。
class DayGroup {
  DayGroup({required this.date, required this.records, required this.dayTotal});

  /// `YYYY-MM-DD`
  final String date;

  /// 这天的账，按录入时间倒序（新的在上）
  final List<LedgerRecord> records;

  /// 当日净额（收入 - 支出）。全支出时是负数。
  final double dayTotal;

  /// 当日支出合计（正数）
  double get dayExpense => records
      .where((r) => !r.isIncome)
      .fold<double>(0, (a, r) => a + r.amount);
}

/// 把某个月的账按日期分组，日期倒序（今天在最上面），
/// 组内按创建时间倒序。
List<DayGroup> groupByDay(List<LedgerRecord> records, String month) {
  final byDate = <String, List<LedgerRecord>>{};
  for (final r in records) {
    if (!r.date.startsWith(month)) continue;
    byDate.putIfAbsent(r.date, () => <LedgerRecord>[]).add(r);
  }
  final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
  return <DayGroup>[
    for (final d in dates)
      DayGroup(
        date: d,
        records: (byDate[d]!..sort((a, b) => b.createdAt.compareTo(a.createdAt))),
        dayTotal: byDate[d]!.fold<double>(0, (a, r) => a + r.signed),
      ),
  ];
}

/// 日期显示：`09月19日 · 周六`。解析不出来就原样显示。
String dayLabel(String date) {
  final d = parseDateKey(date);
  if (d == null) return date;
  const wd = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return '${pad2(d.month)}月${pad2(d.day)}日 · ${wd[d.weekday - 1]}';
}

/// 月份显示：`2026年9月`。
String monthLabel(String month) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(month.trim());
  if (m == null) return month;
  return '${m.group(1)}年${int.parse(m.group(2)!)}月';
}

/// 校验分类名。返回错误文案，没问题返回 null。
///
/// 空名字不行、超过 6 个字不行（设计稿写的是「≤6 字」，格子就那么点大）。
String? validateCategoryName(String name, {String? selfId, List<LedgerCategory>? all}) {
  final t = name.trim();
  if (t.isEmpty) return '分类名不能为空';
  if (t.length > 6) return '分类名最多 6 个字';
  if (all != null) {
    for (final c in all) {
      if (c.id == selfId) continue;
      if (c.name.trim() == t) return '已经有同名分类了';
    }
  }
  return null;
}

/// 校验金额。返回错误文案，没问题返回 null。
String? validateAmount(double? amount) {
  if (amount == null) return '请输入金额';
  if (amount <= 0) return '金额要大于 0';
  if (amount > 9999999) return '金额太大了';
  return null;
}

/// 把分类按 sort 排好（界面统一走这里，别各自排）。
List<LedgerCategory> sortedCategories(List<LedgerCategory> cats) {
  final out = List<LedgerCategory>.from(cats);
  out.sort((a, b) {
    if (a.sort != b.sort) return a.sort.compareTo(b.sort);
    return a.name.compareTo(b.name);
  });
  return out;
}

/// 某个分类下还有多少条账（删分类前要提示）。
int recordCountOf(List<LedgerRecord> records, String categoryId) =>
    records.where((r) => r.categoryId == categoryId).length;

/// 按 id 找分类；找不到返回 null。
///
/// **返回 null 是正常情况，不是错误**：分类被删掉之后，原来指向它的账
/// 还在数据里（金额、日期都不动），界面显示成「未分类」。
/// 所以这里不要 try / 不要兜底造一个假分类，让调用方自己决定怎么显示。
LedgerCategory? findCategory(List<LedgerCategory> cats, String id) {
  for (final c in cats) {
    if (c.id == id) return c;
  }
  return null;
}
