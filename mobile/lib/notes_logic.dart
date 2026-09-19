/// 备忘录模块的纯逻辑：分组、过滤、搜索、标签解析、列表副标题。
///
/// 行为基准是电脑版 `D:\App\MyDay\app\static\app.js` 里的
/// `noteGroupsHtml` / `filteredNotes` / `noteSubLine`，文案保持一致。
/// 不碰界面、不碰 Store，方便单测。
library;

import 'models.dart';

/// 侧栏的一个分组：key 用于过滤（all / pinned / archived / tag:xxx）。
class NoteGroup {
  const NoteGroup(this.key, this.label, this.count);

  final String key;
  final String label;
  final int count;
}

/// 分组统计（和电脑版 noteGroupsHtml 一致）：
/// 全部 = 未归档；置顶 = 未归档且置顶；各标签 = 未归档笔记里数条数；
/// 归档 = 已归档。标签按首次出现的顺序排（电脑版用 Object.keys，也是插入序）。
List<NoteGroup> noteGroups(List<Note> notes) {
  final visible = notes.where((n) => !n.archived).toList();
  final groups = <NoteGroup>[
    NoteGroup('all', '全部', visible.length),
    NoteGroup('pinned', '置顶', visible.where((n) => n.pinned).length),
  ];
  final tags = <String, int>{};
  for (final n in visible) {
    for (final raw in n.tags) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      tags[t] = (tags[t] ?? 0) + 1;
    }
  }
  tags.forEach((t, c) => groups.add(NoteGroup('tag:$t', t, c)));
  groups.add(NoteGroup('archived', '归档', notes.where((n) => n.archived).length));
  return groups;
}

/// 拼搜索用的全文（和电脑版一致：标题 + 正文 + 每条清单项，空格相连）。
String noteHaystack(Note n) =>
    <String>[n.title, n.body, ...n.items.map((i) => i.text)].join(' ').toLowerCase();

/// 按分组 + 搜索词过滤（和电脑版 filteredNotes 一致）。
/// 搜索在分组过滤之后做；认不出来的分组键返回全部（电脑版兜底 return true）。
List<Note> filteredNotes(List<Note> notes, String groupKey, String query) {
  Iterable<Note> list = notes;
  if (groupKey == 'all') {
    list = list.where((n) => !n.archived);
  } else if (groupKey == 'pinned') {
    list = list.where((n) => !n.archived && n.pinned);
  } else if (groupKey == 'archived') {
    list = list.where((n) => n.archived);
  } else if (groupKey.startsWith('tag:')) {
    final tag = groupKey.substring(4);
    list = list.where((n) => n.tags.any((t) => t.trim() == tag) && !n.archived);
  }
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List<Note>.from(list);
  return list.where((n) => noteHaystack(n).contains(q)).toList();
}

/// 标签输入框的解析：逗号 / 中文逗号 / 顿号分隔，去首尾空白、丢空段。
/// 电脑版不合并重复项，这里也不合并。
List<String> parseTags(String input) => input
    .split(RegExp(r'[,，、]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// 列表第二行：类型 · 标签 · 摘要（与电脑版 noteSubLine 一致）。
/// 没标签就不写「未分类」——免得看着像这条笔记没归到任何类别。
String noteSubLine(Note n) {
  final bits = <String>[NoteType.label(n.type)];
  final tags = n.tags.where((t) => t.isNotEmpty).toList();
  if (tags.isNotEmpty) bits.add(tags.join('、'));
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
