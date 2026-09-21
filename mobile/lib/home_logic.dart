/// 首页聚合的纯逻辑：问候语、今天日期信息、今日课程状态、备忘录速览。
///
/// 行为基准是电脑版 `D:\App\MyDay\app\server.py` 的 `api_home` /
/// `compute_lesson_states` / `greeting_of` / `_minutes`，以及
/// `app/static/app.js` 的 `homeLessonsHtml` / `homeNotesHtml`，文案保持一致。
/// 这里不碰文件、不碰网络、不碰界面，纯函数好测。
library;

import 'models.dart';

// ---------- 问候语（和电脑版 greeting_of 一致） ----------
String greetingOf(DateTime now) {
  final h = now.hour;
  if (h < 6) return '还没睡';
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

const Map<int, String> weekdayNames = <int, String>{
  1: '周一',
  2: '周二',
  3: '周三',
  4: '周四',
  5: '周五',
  6: '周六',
  7: '周日',
};

String weekdayCn(int dow) => weekdayNames[dow] ?? '';

// ---------- 时间小工具（和电脑版 _minutes 一致） ----------
/// `HH:MM` 转当天 0 点起的分钟数；解析不了返回 null。
int? minutesFromHhmm(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Python `str.strip(' -')` 的等价物：去掉两端有空格和短横线。
String stripDashSpace(String s) {
  var a = 0;
  var b = s.length;
  while (a < b && (s[a] == ' ' || s[a] == '-')) {
    a++;
  }
  while (b > a && (s[b - 1] == ' ' || s[b - 1] == '-')) {
    b--;
  }
  return s.substring(a, b);
}

// ---------- 今日课程状态（和电脑版 compute_lesson_states 一致） ----------
class LessonState {
  LessonState({
    required this.lesson,
    required this.periodLabel,
    required this.periodRange,
    required this.status,
    required this.order,
    required this.seq,
    this.begin,
    this.next = false,
  });

  final Lesson lesson;

  /// 起始节次的名字（电脑版直接用 label 原文，空就是空）。
  final String periodLabel;

  /// 起止时间文案；没设时间时是「时间未设置」。
  final String periodRange;

  /// upcoming / now / done / unknown（与电脑版同名）。
  final String status;

  /// 起始节次在节次表里的位置（找不到是 999）。
  final int order;

  /// 原始列表里的位置，排序的最后一层平手判据（模拟 Python 稳定排序）。
  final int seq;

  /// 开始的分钟数；节次没设时间时为 null。
  final int? begin;

  /// 今天接下来要上的那节课（第一个 upcoming）。
  bool next;
}

List<LessonState> computeLessonStates(
  List<Lesson> lessons,
  List<Period> periods,
  int nowMin,
) {
  final out = <LessonState>[];
  var seq = 0;
  for (final lesson in lessons) {
    Period? startP;
    Period? endP;
    for (var i = 0; i < periods.length; i++) {
      final p = periods[i];
      if (startP == null && p.id == lesson.slot) {
        startP = p;
      }
      if (lesson.spanEnd.isNotEmpty && endP == null && p.id == lesson.spanEnd) {
        endP = p;
      }
    }
    var order = 999;
    for (var i = 0; i < periods.length; i++) {
      if (periods[i].id == lesson.slot) {
        order = i;
        break;
      }
    }
    final begin = startP == null ? null : minutesFromHhmm(startP.start);
    final finishP = endP ?? startP;
    final finish = finishP == null ? null : minutesFromHhmm(finishP.end);

    var status = 'unknown';
    if (begin != null && finish != null) {
      var fin = finish;
      if (fin < begin) fin += 24 * 60; // 跨零点，按次日凌晨处理
      if (nowMin < begin) {
        status = 'upcoming';
      } else if (begin <= nowMin && nowMin <= fin) {
        status = 'now';
      } else {
        status = 'done';
      }
    }

    final rangeRaw = '${startP?.start ?? ''} - ${(finishP ?? startP)?.end ?? ''}';
    final range = stripDashSpace(rangeRaw);

    out.add(LessonState(
      lesson: lesson,
      periodLabel: startP?.label ?? '',
      periodRange: range.isEmpty ? '时间未设置' : range,
      status: status,
      begin: begin,
      order: order,
      seq: seq++,
    ));
  }
  // 和电脑版一样：begin 为 null 的排最后，再按开始时间、节次顺序排。
  out.sort((a, b) {
    final aNull = a.begin == null;
    final bNull = b.begin == null;
    if (aNull != bNull) return aNull ? 1 : -1;
    final ab = a.begin ?? 0;
    final bb = b.begin ?? 0;
    if (ab != bb) return ab - bb;
    if (a.order != b.order) return a.order - b.order;
    return a.seq - b.seq;
  });
  var nextMarked = false;
  for (final item in out) {
    item.next = false;
    if (item.status == 'upcoming' && !nextMarked) {
      item.next = true;
      nextMarked = true;
    }
  }
  return out;
}

// ---------- 备忘录速览（和电脑版 api_home 的 notesPreview 一致） ----------
const int previewNotesMax = 3;
const int previewItemsMax = 6;
const int previewBodyMax = 200;

class HomeNotePreview {
  HomeNotePreview({
    required this.id,
    required this.title,
    required this.type,
    required this.summary,
    required this.pinned,
    required this.items,
    required this.moreItems,
    required this.itemsDone,
    required this.itemsTotal,
    required this.body,
    required this.bodyCut,
  });

  final String id;
  final String title;
  final String type;

  /// v1.9.1：标签功能去掉了，速览不再带 tags（凯森要求删标签）。
  final String summary;
  final bool pinned;

  /// 首页摊出来的前几项清单（整段回写会冲掉没显示的项，勾选只翻转单条）。
  final List<NoteItem> items;
  final int moreItems;
  final int itemsDone;
  final int itemsTotal;
  final String body;
  final bool bodyCut;
}

/// 挑首页速览：未归档、置顶在前、改过的在前，最多 [maxNotes] 条。
List<HomeNotePreview> previewNotes(
  List<Note> notes, {
  int maxNotes = previewNotesMax,
  int maxItems = previewItemsMax,
  int maxBody = previewBodyMax,
}) {
  // 模拟电脑版两次稳定排序：先 updatedAt 倒序，再置顶的在前。
  // 记下原始下标当最后一层平手判据（Dart 的 sort 不保证稳定）。
  final ranked = <int>[];
  for (var i = 0; i < notes.length; i++) {
    if (!notes[i].archived) ranked.add(i);
  }
  ranked.sort((ai, bi) {
    final a = notes[ai];
    final b = notes[bi];
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final c = b.updatedAt.compareTo(a.updatedAt);
    if (c != 0) return c;
    return ai - bi;
  });

  final out = <HomeNotePreview>[];
  for (final i in ranked.take(maxNotes)) {
    final n = notes[i];
    final total = n.items.length;
    final done = n.items.where((i) => i.done).length;
    final shown = n.items.take(maxItems).toList();
    final bodyTrimmed = n.body.trim();
    out.add(HomeNotePreview(
      id: n.id,
      title: n.title.isEmpty ? '无标题' : n.title,
      type: n.type,
      // 清单永远给「x/y 项完成」（0 项也给，和电脑版 api_home 一致）；
      // 笔记给正文第一行，截 24 个字符（不 trim，照抄）。
      summary: n.isTodo
          ? '$done/$total 项完成'
          : _firstLine(n.body, 24),
      pinned: n.pinned,
      items: shown.map((i) => NoteItem(text: i.text, done: i.done)).toList(),
      moreItems: total - shown.length < 0 ? 0 : total - shown.length,
      itemsDone: done,
      itemsTotal: total,
      body: bodyTrimmed.length > maxBody
          ? bodyTrimmed.substring(0, maxBody)
          : bodyTrimmed,
      bodyCut: bodyTrimmed.length > maxBody,
    ));
  }
  return out;
}

String _firstLine(String body, int max) {
  final line = body.split('\n').first;
  if (line.length > max) return line.substring(0, max);
  return line;
}

/// 只翻转某一条清单项（和电脑版 `store.toggle_note_item` 一致）：
/// 首页速览只带了前几项，**绝不能整段回写 items**，会把没显示出来的项冲掉。
/// 翻转成功顺手更新 updatedAt。找不到笔记 / 序号越界返回 null。
Note? toggleNoteItem(
  Notes notes,
  String id,
  int index, {
  required String Function() nowIso,
}) {
  for (final n in notes.notes) {
    if (n.id != id) continue;
    if (index < 0 || index >= n.items.length) return null;
    final item = n.items[index];
    n.items[index] = item.copyWith(done: !item.done);
    n.updatedAt = nowIso();
    return n;
  }
  return null;
}
