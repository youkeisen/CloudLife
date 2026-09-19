/// 备忘录页：分组（全部/置顶/标签/归档）+ 搜索 + 新建；点开进编辑页。
/// 编辑页支持笔记 / 清单两种形态，自动保存（500ms 防抖）+ 保存键 +
/// 「已保存 / 有改动…」状态，切走前补存。
///
/// 行为对齐电脑版（`app/static/app.js` 的备忘录区），文案保持一致。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../notification_service.dart';
import '../notes_logic.dart';
import '../store.dart';
import 'wheel_time_picker.dart';
import 'glass.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key, required this.store});

  final Store store;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  String _group = 'all';
  String _query = '';

  void _openEditor(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteEditPage(store: widget.store, noteId: id),
    ));
    // 回来后重读数据（编辑页里可能改了/删了/归档了）。
    if (mounted) setState(() {});
  }

  void _createNote() {
    final notes = widget.store.notes();
    final now = Store.nowIso();
    final n = Note(
      id: widget.store.newId('n'),
      title: '',
      type: NoteType.text,
      tags: <String>[],
      createdAt: now,
      updatedAt: now,
    );
    notes.notes.add(n);
    widget.store.saveNotes(notes);
    _openEditor(n.id);
  }

  @override
  Widget build(BuildContext context) {
    // 置顶在前、改过的在前（Store 的同款排序），分组过滤在其上做。
    final all = widget.store.sortedNotes(includeArchived: true);
    final groups = noteGroups(all);
    if (groups.every((g) => g.key != _group)) {
      _group = 'all'; // 分组可能因为删标签等失效，回落到「全部」
    }
    final list = filteredNotes(all, _group, _query);
    final cs = Theme.of(context).colorScheme;

    return Column(
      key: const ValueKey('page-notes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey('notes-search'),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: '搜标题、内容、清单项',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('btn-new-note'),
              onPressed: _createNote,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建备忘录'),
            ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: <Widget>[
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('note-group-${g.key}'),
                    label: Text('${g.label} ${g.count}'),
                    selected: _group == g.key,
                    onSelected: (_) => setState(() => _group = g.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: all.isEmpty
              ? _emptyHint(cs,
                  key: 'notes-empty',
                  icon: Icons.edit_note_outlined,
                  title: '这里还没有东西',
                  hint: '点「新建备忘录」开始写，支持笔记和可勾选的清单')
              : list.isEmpty
                  ? _emptyHint(cs,
                      key: 'notes-no-match',
                      icon: Icons.search_off,
                      title: '没有符合条件的内容',
                      hint: '换个分组或搜索词试试')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final n = list[i];
                        return Card(
                          key: ValueKey('note-card-${n.id}'),
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(
                              (n.pinned ? '★ ' : '') + (n.title.isEmpty ? '无标题' : n.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              noteSubLine(n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.outline),
                            ),
                            onTap: () => _openEditor(n.id),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _emptyHint(ColorScheme cs,
      {required String key,
      required IconData icon,
      required String title,
      required String hint}) {
    return Center(
      key: ValueKey<String>(key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 46, color: cs.outline),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(hint, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
        ),
      ),
    );
  }
}

/// 备忘录编辑页：标题 / 标签 / 类型 / 正文或清单。
class NoteEditPage extends StatefulWidget {
  const NoteEditPage({super.key, required this.store, required this.noteId});

  final Store store;
  final String noteId;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late final Notes _notes;
  Note? _note;
  late final TextEditingController _titleCtl;
  late final TextEditingController _tagsCtl;
  late final TextEditingController _bodyCtl;
  final List<TextEditingController> _itemCtls = <TextEditingController>[];
  Timer? _timer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _notes = widget.store.notes();
    _note = _notes.byId(widget.noteId);
    final n = _note;
    _titleCtl = TextEditingController(text: n?.title ?? '');
    _tagsCtl = TextEditingController(text: (n?.tags ?? const <String>[]).join('、'));
    _bodyCtl = TextEditingController(text: n?.body ?? '');
    for (final item in n?.items ?? const <NoteItem>[]) {
      _itemCtls.add(TextEditingController(text: item.text));
    }
  }

  @override
  void dispose() {
    // 切走前补存（电脑版点别的笔记前也会先补存，别让刚敲的字丢了）。
    _timer?.cancel();
    if (_dirty) _save();
    _titleCtl.dispose();
    _tagsCtl.dispose();
    _bodyCtl.dispose();
    for (final c in _itemCtls) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    setState(() => _dirty = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), _save);
  }

  void _save() {
    final n = _note;
    if (n == null) return;
    n.updatedAt = Store.nowIso();
    widget.store.saveNotes(_notes);
    if (mounted) setState(() => _dirty = false);
  }

  void _saveNow() {
    _timer?.cancel();
    _save();
  }

  void _setType(String type) {
    final n = _note;
    if (n == null) return;
    n.type = type;
    // 和电脑版一致：切成清单时一条都没有就先给一行空的。
    if (type == NoteType.todo && n.items.isEmpty) {
      _addItem();
    }
    _saveNow();
  }

  void _addItem() {
    final n = _note;
    if (n == null) return;
    n.items.add(NoteItem(text: '', done: false));
    _itemCtls.add(TextEditingController(text: ''));
    _saveNow();
  }

  void _removeItem(int i) {
    final n = _note;
    if (n == null || i < 0 || i >= n.items.length) return;
    n.items.removeAt(i);
    _itemCtls[i].dispose();
    _itemCtls.removeAt(i);
    _saveNow();
  }

  // ---------- 定时提醒 ----------

  String _remindText() {
    final raw = _note?.remindAt ?? '';
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    return '${dt.month}月${dt.day}日 '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 选提醒时间：先挑日期，再用 Windows 同款滚轮挑时分。
  Future<void> _pickRemindAt() async {
    final n = _note;
    if (n == null) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: '选提醒日期',
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showWheelTimePicker(
        context, TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null) return;
    final when =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text('要选未来的时间'), duration: Duration(seconds: 2)));
      }
      return;
    }
    n.remindAt = when.toIso8601String();
    await NotificationService.scheduleFor(n.id, n.title, when);
    _saveNow();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(
                '已设提醒：${when.month}月${when.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
            duration: const Duration(seconds: 2)));
    }
  }

  /// 清掉提醒。
  Future<void> _clearRemindAt() async {
    final n = _note;
    if (n == null) return;
    n.remindAt = '';
    await NotificationService.cancel(n.id);
    _saveNow();
  }

  void _deleteNote() {
    final n = _note;
    if (n == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条备忘录'),
        content: const Text('删除后不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('btn-confirm-delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _timer?.cancel();
              _dirty = false;
              _notes.notes.removeWhere((x) => x.id == n.id);
              widget.store.saveNotes(_notes);
              // 删了备忘录就把它的提醒也撤了
              NotificationService.cancel(n.id);
              // 先抓住 messenger：这页自己也要 pop，之后 context 就不能用了。
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(ctx).pop(); // 关弹窗
              Navigator.of(context).pop(); // 回列表
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text('已删除'),
                  duration: Duration(milliseconds: 1200),
                ));
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _note;
    final cs = Theme.of(context).colorScheme;
    if (n == null) {
      // 数据被别处删了之类的极端情况：给个提示直接回去。
      return GlassBackdrop(
        child: Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('备忘录不存在')),
        ),
      );
    }
    final isTodo = n.isTodo;

    return PopScope<Object?>(
      // 返回键按下时就把没落盘的改动补存掉：dispose 要等转场结束才跑，
      // 那时列表页早就重读过了，会显示旧数据。
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _timer?.cancel();
          if (_dirty) _save();
        }
      },
      // 编辑页是独立路由：底下没有壳子的渐变背景，得自己垫一层，
      // 否则透明的 Scaffold 会露出路由遮罩的黑底（v1.1.0 的 bug）。
      child: GlassBackdrop(
        child: Scaffold(
        key: const ValueKey('page-note-edit'),
        appBar: AppBar(
          title: Text(isTodo ? '编辑清单' : '编辑笔记'),
          actions: <Widget>[
            TextButton(
              key: const ValueKey('btn-save-note'),
              onPressed: _saveNow,
              child: const Text('保存'),
            ),
          ],
        ),
        body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          TextField(
            key: const ValueKey('field-title'),
            controller: _titleCtl,
            decoration: const InputDecoration(labelText: '标题'),
            onChanged: (v) {
              n.title = v;
              _markDirty();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('field-tags'),
            controller: _tagsCtl,
            decoration: const InputDecoration(
              labelText: '标签（用逗号或顿号分开）',
              hintText: '例如：生活、学习',
            ),
            onChanged: (v) {
              n.tags = parseTags(v);
              _markDirty();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('field-type'),
            initialValue: n.type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '类型'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: NoteType.text, child: Text('笔记')),
              DropdownMenuItem<String>(value: NoteType.todo, child: Text('清单')),
            ],
            onChanged: (v) {
              if (v != null && v != n.type) _setType(v);
            },
          ),
          const SizedBox(height: 12),
          // 定时提醒（凯森 v1.5.0 要求）：点一下选日期 + 时间，设了以后系统会推通知
          InkWell(
            key: const ValueKey('field-remind'),
            onTap: _pickRemindAt,
            child: InputDecorator(
              isEmpty: n.remindAt.isEmpty,
              decoration: InputDecoration(
                labelText: '定时提醒',
                hintText: '不提醒',
                suffixIcon: n.remindAt.isEmpty
                    ? const Icon(Icons.alarm_add, size: 20)
                    : IconButton(
                        key: const ValueKey('btn-clear-remind'),
                        tooltip: '取消提醒',
                        icon: const Icon(Icons.alarm_off, size: 20),
                        onPressed: _clearRemindAt,
                      ),
              ),
              child: Text(_remindText()),
            ),
          ),
          const SizedBox(height: 16),
          if (!isTodo)
            TextField(
              key: const ValueKey('field-body'),
              controller: _bodyCtl,
              decoration: const InputDecoration(
                labelText: '内容',
                alignLabelWithHint: true,
                hintText: '想到什么写什么',
              ),
              minLines: 8,
              maxLines: 16,
              onChanged: (v) {
                n.body = v;
                _markDirty();
              },
            )
          else ...<Widget>[
            Text('清单', style: TextStyle(fontSize: 12, color: cs.outline)),
            for (var i = 0; i < n.items.length; i++)
              Row(
                key: ValueKey('todo-row-$i'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Checkbox(
                    key: ValueKey('todo-check-$i'),
                    value: n.items[i].done,
                    onChanged: (v) {
                      n.items[i].done = v ?? false;
                      _saveNow();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('todo-text-$i'),
                      controller: _itemCtls[i],
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '一件事一行，写在这里',
                        border: InputBorder.none,
                      ),
                      onChanged: (v) {
                        n.items[i].text = v;
                        _markDirty();
                      },
                    ),
                  ),
                  IconButton(
                    key: ValueKey('todo-del-$i'),
                    tooltip: '删这一行',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() => _removeItem(i));
                    },
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: <Widget>[
                OutlinedButton.icon(
                  key: const ValueKey('btn-add-todo'),
                  onPressed: () {
                    setState(_addItem);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('加一行'),
                ),
                const SizedBox(width: 10),
                Text('勾上就是做完，进度会同步到列表和首页',
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          Row(children: <Widget>[
            Text(
              _dirty ? '有改动…' : '已保存',
              key: const ValueKey('note-status'),
              style: TextStyle(
                fontSize: 12,
                color: _dirty ? cs.primary : cs.outline,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              key: const ValueKey('btn-pin'),
              onPressed: () {
                n.pinned = !n.pinned;
                _saveNow();
              },
              icon: Icon(n.pinned ? Icons.star : Icons.star_border, size: 18),
              label: Text(n.pinned ? '取消置顶' : '置顶'),
            ),
            TextButton.icon(
              key: const ValueKey('btn-archive'),
              onPressed: () {
                n.archived = !n.archived;
                _saveNow();
              },
              icon: Icon(
                n.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                size: 18,
              ),
              label: Text(n.archived ? '还原' : '归档'),
            ),
            TextButton.icon(
              key: const ValueKey('btn-delete-note'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _deleteNote,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ]),
        ],
        ),
        ),
      ),
    );
  }
}
