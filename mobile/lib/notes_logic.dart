/// 备忘录模块的纯逻辑：分组、过滤、搜索、列表副标题。
///
/// 行为基准是电脑版 `D:\App\MyDay\app\static\app.js` 里的
/// `noteGroupsHtml` / `filteredNotes` / `noteSubLine`，文案保持一致。
/// 不碰界面、不碰 Store，方便单测。
///
/// v1.9.1：**标签功能去掉**（凯森 2026-09-21「把笔记里的标签删除」），
/// 所以这里不再有标签分组、标签筛选、标签解析。
library;

import 'models.dart';

/// 侧栏的一个分组：key 用于过滤（all / pinned / archived / tag:xxx）。
class NoteGroup {
  const NoteGroup(this.key, this.label, this.count);

  final String key;
  final String label;
  final int count;
}

/// 分组统计：全部 = 未归档；置顶 = 未归档且置顶；归档 = 已归档。
///
/// 以前这里还会按标签生成分组（`tag:xxx`），v1.9.1 起标签功能去掉了 ——
/// 凯森 2026-09-21：「把笔记里的标签删除」。分组就剩这三个。
/// 新建一条空笔记并加进 [notes]（**不落盘**，调用方自己 saveNotes）。
/// 备忘录页的「新建」和功能页的「写备忘」共用这一份。
Note newEmptyNote(Notes notes, {required String id, required String nowIso}) {
  final n = Note(
    id: id,
    title: '',
    type: NoteType.text,
    createdAt: nowIso,
    updatedAt: nowIso,
  );
  notes.notes.add(n);
  return n;
}

List<NoteGroup> noteGroups(List<Note> notes) {
  final visible = notes.where((n) => !n.archived).toList();
  return <NoteGroup>[
    NoteGroup('all', '全部', visible.length),
    NoteGroup('pinned', '置顶', visible.where((n) => n.pinned).length),
    NoteGroup('archived', '归档', notes.where((n) => n.archived).length),
  ];
}

/// 拼搜索用的全文（和电脑版一致：标题 + 正文 + 每条清单项，空格相连）。
String noteHaystack(Note n) =>
    <String>[n.title, n.body, ...n.items.map((i) => i.text)].join(' ').toLowerCase();

/// 按分组 + 搜索词过滤。搜索在分组过滤之后做；
/// 认不出来的分组键返回全部（电脑版兜底 return true）。
///
/// 以前还有个 `tag:xxx` 分支，v1.9.1 去掉标签功能时一起删了。
List<Note> filteredNotes(List<Note> notes, String groupKey, String query) {
  Iterable<Note> list = notes;
  if (groupKey == 'all') {
    list = list.where((n) => !n.archived);
  } else if (groupKey == 'pinned') {
    list = list.where((n) => !n.archived && n.pinned);
  } else if (groupKey == 'archived') {
    list = list.where((n) => n.archived);
  }
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List<Note>.from(list);
  return list.where((n) => noteHaystack(n).contains(q)).toList();
}

/// 列表第二行：类型 · 摘要。
///
/// v1.9.1 去掉标签功能后不再拼标签（凯森要求删掉）。
/// 也没写「未分类」——免得看着像这条笔记缺了什么。
String noteSubLine(Note n) {
  final bits = <String>[NoteType.label(n.type)];
  final summary = noteSummaryText(n);
  if (summary.isNotEmpty) bits.add(summary);
  return bits.join(' · ');
}

/// 摘要：清单给「x/y 项完成」，笔记给正文第一行（电脑版截 20 个字符）。
String noteSummaryText(Note n) {
  if (n.isTodo) {
    return n.items.isEmpty ? '' : '${n.itemsDone}/${n.itemsTotal} 项完成';
  }
  final first = n.body.split('\n').first.trim();
  if (first.length > 20) return first.substring(0, 20);
  return first;
}

// ---------- 定时提醒（v1.8.2 起，v1.9.1 加「N 天后」） ----------

/// 提醒文案。三种方式一眼能分清，空字符串 = 没设提醒。
///
/// - 单次：`今天 08:05` / `明天 08:05`（过了今天的点就自动算明天）
/// - 每天：`每天 08:05`
/// - N 天后：`3 天后 08:05`
String remindLabel(Note n, {DateTime? now}) {
  if (n.remindAt.isEmpty) return '';
  final dt = DateTime.tryParse(n.remindAt);
  if (dt == null) return '';
  final hm = '${_two(dt.hour)}:${_two(dt.minute)}';
  if (n.remindDaily) return '每天 $hm';
  if (n.remindAfterDays) {
    // 0 天就是今天、1 天就是明天，比写「0 天后」顺眼
    if (n.remindDays <= 0) return '今天 $hm';
    if (n.remindDays == 1) return '明天 $hm';
    return '${n.remindDays} 天后 $hm';
  }
  // 单次：说的是「最近的那一次」，所以按现在判断是今天还是明天
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day, dt.hour, dt.minute);
  return today.isAfter(at) ? '今天 $hm' : '明天 $hm';
}

/// 「每天 hh:mm」的**下一次**提醒时刻。
///
/// 为什么要有它：每天重复的提醒，存的那个时刻早就过去了（比如昨天设的 08:00），
/// 但插件排程时要求给一个**未来的**时刻才会真的排进去 —— 光靠
/// `matchDateTimeComponents` 不会把过去的时刻救回来。
///
/// 所以每次重排都现算一次：今天的那个点还没到就用今天，过了就顺延到明天。
/// 用 `DateTime(年, 月, 日 + 1, ...)` 而不是 `add(Duration(days: 1))`，
/// 跨月/跨年让 DateTime 自己进位，也别踩夏令时的坑（虽然国内没有）。
DateTime nextDailyOccurrence(DateTime base, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, base.hour, base.minute);
  if (today.isAfter(now)) return today;
  return DateTime(
      now.year, now.month, now.day + 1, base.hour, base.minute);
}

/// 单次提醒的**最近一次**时刻：今天的那个点还没到就用今天，过了就明天。
///
/// 凯森 2026-09-21 的要求：选时间时只选时:分、不选日期，
/// 所以「哪天」由这里定 —— 不让用户为了选一个已经过去的时刻而报错。
///
/// 算法和 [nextDailyOccurrence] 一样，特意留两个名字：
/// 一个的语义是「每天的下一次」，一个是「就这一次」，读代码时不容易搞混。
DateTime nextOnceOccurrence(DateTime base, DateTime now) =>
    nextDailyOccurrence(base, now);

/// 「N 天后」的时刻：今天 + [days] 天，时:分取 [base] 的。
/// days = 0 就是今天（和单次同一套算法）。
DateTime afterDaysOccurrence(DateTime base, int days, DateTime now) {
  if (days <= 0) return nextOnceOccurrence(base, now);
  return DateTime(
      now.year, now.month, now.day + days, base.hour, base.minute);
}

String _two(int n) => n < 10 ? '0$n' : '$n';
