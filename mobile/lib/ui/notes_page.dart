/// 备忘录页：分组（全部/置顶/标签/归档）+ 搜索 + 新建；点开进编辑页。
/// 编辑页支持笔记 / 清单两种形态，自动保存（500ms 防抖）+ 保存键 +
/// 「已保存 / 有改动…」状态，切走前补存。
///
/// 行为对齐电脑版（`app/static/app.js` 的备忘录区），文案保持一致。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, TextInputFormatter;

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

/// 备忘录编辑页：标题 / 类型 / 定时提醒 / 正文或清单。
/// （v1.9.1 起没有标签输入框了。）
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
  late final TextEditingController _bodyCtl;
  final List<TextEditingController> _itemCtls = <TextEditingController>[];

  /// 「N 天后」那个天数输入框（v1.9.1）。
  late final TextEditingController _daysCtl;
  Timer? _timer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _notes = widget.store.notes();
    _note = _notes.byId(widget.noteId);
    final n = _note;
    _titleCtl = TextEditingController(text: n?.title ?? '');
    _bodyCtl = TextEditingController(text: n?.body ?? '');
    // 天数给个默认「1」——空着的话用户会以为坏了；真的要今天就填 0
    _daysCtl = TextEditingController(
        text: '${(n?.remindDays ?? 0) > 0 ? n!.remindDays : 1}');
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
    _bodyCtl.dispose();
    _daysCtl.dispose();
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

  String _remindText() => _note == null ? '' : remindLabel(_note!);

  /// 排提醒 / 撤提醒，失败了也不往外抛。
  ///
  /// 为什么吞掉：设提醒这件事里，「把时间存下来」是主，**「排进系统」是次**——
  /// 排不上（插件不可用、权限被拒）也不该让用户白设一次。
  /// 数据存下来之后，下次 App 启动 [ReminderScheduler] 会全量重排一遍兜底。
  Future<void> _scheduleQuietly(
    Note n,
    DateTime when, {
    bool daily = false,
  }) async {
    try {
      await NotificationService.scheduleFor(n.id, n.title, when,
          repeatDaily: daily);
    } catch (_) {/* 交给下次重排 */}
  }

  Future<void> _cancelQuietly(Note n) async {
    try {
      await NotificationService.cancel(n.id);
    } catch (_) {/* 同上 */}
  }

  /// 把当前这条按它的方式排进系统（三种方式共用）。
  /// 存下来的 [Note.remindAt] 只是「基准时:分」，真正排的是现算出来的时刻。
  Future<void> _scheduleByMode(Note n, DateTime base, DateTime now) async {
    if (n.remindDaily) {
      await _scheduleQuietly(n, nextDailyOccurrence(base, now), daily: true);
      return;
    }
    if (n.remindAfterDays) {
      await _scheduleQuietly(
          n, afterDaysOccurrence(base, n.remindDays, now));
      return;
    }
    await _scheduleQuietly(n, nextOnceOccurrence(base, now));
  }

  /// 点「定时提醒」：**直接弹时间滚轮**（v1.9.1 改）。
  ///
  /// 凯森 2026-09-21 的要求：只选小时和分钟、不选日期，默认停在**当前时间**
  /// （以前是 +1 小时，他要改成当前）。「哪天响」由方式决定（见 [_setRemindMode]）。
  Future<void> _pickRemindTime() async {
    final n = _note;
    if (n == null) return;
    final now = DateTime.now();
    final time = await showWheelTimePicker(context, TimeOfDay.fromDateTime(now));
    if (time == null) return;
    final base = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    n.remindAt = base.toIso8601String();
    _saveNow();
    await _scheduleByMode(n, base, now);
    if (!mounted) return;
    final hm = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('已设提醒：$hm'), duration: const Duration(seconds: 2)));
  }

  /// 设/改提醒方式：单次 / 每天 / N 天后。
  ///
  /// 凯森 2026-09-21 的要求：方式的选择放在**编辑页上**（不在弹窗里），
  /// 选好时间之后就能点。
  Future<void> _setRemindMode(String mode) async {
    final n = _note;
    if (n == null || n.remindAt.isEmpty) return;
    final now = DateTime.now();
    final base = DateTime.tryParse(n.remindAt);
    if (base == null) return;

    n.remindRepeat = mode;
    if (mode != Note.remindRepeatDays) {
      // 不是「N 天后」就把天数归零，免得留着上次的数字下次又冒出来
      n.remindDays = 0;
    } else if (n.remindDays <= 0) {
      // 第一次切到「N 天后」：用输入框里的值（默认 1），别弄出个 0 天
      n.remindDays = int.tryParse(_daysCtl.text) ?? 1;
      if (n.remindDays <= 0) n.remindDays = 1;
      _daysCtl.text = '${n.remindDays}';
    }
    _saveNow();
    await _scheduleByMode(n, base, now);
  }

  /// 改「N 天后」的那个 N。
  Future<void> _setRemindDays(int days) async {
    final n = _note;
    if (n == null || n.remindAt.isEmpty) return;
    final base = DateTime.tryParse(n.remindAt);
    if (base == null) return;
    n.remindDays = days < 0 ? 0 : days;
    _saveNow();
    await _scheduleByMode(n, base, DateTime.now());
  }

  /// 提醒方式三选一（单次 / 每天 / N 天后）+ 「N 天后」的天数（v1.9.1）。
  ///
  /// 凯森 2026-09-21 的要求：方式的选择放在编辑页上，选好时间之后就能点。
  Widget _remindModeRow(Note n) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String label, String mode, String key) => ChoiceChip(
          key: ValueKey<String>(key),
          label: Text(label),
          selected: n.remindRepeat == mode,
          onSelected: (_) => _setRemindMode(mode),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('提醒方式', style: TextStyle(fontSize: 12, color: cs.outline)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          chip('单次', '', 'remind-mode-once'),
          chip('每天', Note.remindRepeatDaily, 'remind-mode-daily'),
          chip('N 天后', Note.remindRepeatDays, 'remind-mode-days'),
        ]),
        if (n.remindAfterDays) ...<Widget>[
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Text('几天后：', style: TextStyle(fontSize: 12, color: cs.outline)),
            SizedBox(
              width: 76,
              child: TextField(
                key: const ValueKey('field-remind-days'),
                controller: _daysCtl,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(isDense: true, suffixText: '天'),
                onChanged: (v) => _setRemindDays(int.tryParse(v) ?? 0),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  /// 清掉提醒。
  Future<void> _clearRemindAt() async {
    final n = _note;
    if (n == null) return;
    n.remindAt = '';
    n.remindRepeat = '';
    n.remindDays = 0;
    _saveNow();
    await _cancelQuietly(n);
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
          // v1.9.0：标签输入框去掉了（凯森 2026-09-21「把笔记里的标签删除」）。
          // 数据里的 tags 字段也一起删了，存量数据由 Store.init() 清（他说「数据一起清掉」）。
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
          // 定时提醒（凯森 v1.5.0 要求）：点一下**直接选时分**（v1.9.1 改，
          // 以前还要先挑日期）。设好之后下面出现「单次 / 每天 / N 天后」的选择。
          InkWell(
            key: const ValueKey('field-remind'),
            onTap: _pickRemindTime,
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
          if (n.remindAt.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            _remindModeRow(n),
          ],
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
