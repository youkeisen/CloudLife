/// 课程页：周次切换、课表表格（节次 × 星期）、点课块编辑、增删改、
/// 整周复制（三种策略）、清空本周、没节次时的引导。
///
/// 行为对齐电脑版课程页（`app/static/app.js`），文案保持一致。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../courses_logic.dart';
import '../import_logic.dart';
import '../models.dart';
import '../pdf_timetable.dart';
import '../pdf_timetable_v2.dart';
import '../store.dart';
import '../timetable.dart';
import '../week.dart';

// 课表格子的固定尺寸：每格等高，跨节次的课块高度按格数算出来，
// 这样不用 rowspan 也能对齐各列（横向滚动，7 列在窄屏上也放得下）。
const double _cellH = 64;
const double _cellGap = 4;
const double _headH = 30;
const double _labelW = 62;
const double _dayW = 104;

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key, required this.store, this.pickTimetable});

  final Store store;

  /// 测试注入用：不给就走系统文件选择器。
  final Future<List<int>?> Function()? pickTimetable;

  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  int _week = 1;

  @override
  void initState() {
    super.initState();
    // 默认落在今天所在的教学周；没设置第 1 周周一就先看第 1 周。
    final w = weekOf(DateTime.now(), widget.store.settings().week1Monday);
    _week = w ?? 1;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1200),
      ));
  }

  void _goToday() {
    final w = weekOf(DateTime.now(), widget.store.settings().week1Monday);
    if (w == null) {
      _toast('还没设置第 1 周周一，去设置页填一下');
      return;
    }
    setState(() => _week = w);
  }

  // ---------- 导入课表 ----------

  Future<List<int>?> _pickTimetable() async {
    if (widget.pickTimetable != null) return widget.pickTimetable!();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['xlsx', 'pdf'],
      withData: true,
    );
    return result?.files.single.bytes;
  }

  /// PDF 有两种教务系统格式，逐个试：哪个能解析出课程就用哪个。
  ParsedTimetable _parsePdfAuto(List<int> bytes) {
    final lines = extractPdfLines(bytes);
    final errors = <String>[];
    final parsers = <ParsedTimetable Function(List<RectLine>)>[
      parsePdfTimetableFromLines,
      parsePdfTimetableV2,
    ];
    for (final parser in parsers) {
      try {
        final p = parser(lines);
        if (p.courses.isNotEmpty) return p;
      } on TimetableError catch (e) {
        errors.add(e.message);
      }
    }
    throw TimetableError(errors.join('；'));
  }

  Future<void> _importTimetable() async {
    List<int>? bytes;
    try {
      bytes = await _pickTimetable();
    } catch (e) {
      _toast('选文件出了问题：$e');
      return;
    }
    if (bytes == null || bytes.isEmpty) return;

    final ParsedTimetable parsed;
    try {
      parsed =
          looksLikePdf(bytes) ? _parsePdfAuto(bytes) : parseTimetable(bytes);
    } on TimetableError catch (e) {
      _toast(e.message);
      return;
    }
    if (!mounted) return;
    final plan = planFromParsed(parsed, widget.store.settings());
    if (!mounted) return;
    final mode = await _askImportMode(plan);
    if (mode == null || !mounted) return;

    try {
      final result = applyImport(widget.store, plan, parsed, mode);
      if (!mounted) return;
      setState(() {}); // 课表立刻刷新
      _toast('导入完成：${result.added} 节课，涉及 ${result.weeks.length} 周');
    } on TimetableError catch (e) {
      _toast(e.message);
    }
  }

  Future<String?> _askImportMode(ImportPlan plan) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入课表'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${plan.courseCount} 门课，共 ${plan.totalLessons} 节'),
            Text('涉及周次：${plan.weeks.first} - ${plan.weeks.last}',
                style: const TextStyle(fontSize: 12)),
            if (plan.newPeriods.isNotEmpty)
              Text('将新建节次：${plan.newPeriods.join('、')}',
                  style: const TextStyle(fontSize: 12)),
            if (plan.reusePeriods.isNotEmpty)
              Text('复用已有节次：${plan.reusePeriods.join('、')}',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            if (plan.warnings.isNotEmpty)
              Text('${plan.warnings.length} 条课程没写周次，会跳过',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 8),
            const Text('导入前会自动备份当前数据。',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('import-cancel'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('import-merge'),
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('追加'),
          ),
          TextButton(
            key: const ValueKey('import-overwrite'),
            onPressed: () => Navigator.pop(ctx, 'overwrite'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
  }

  // ---------- 增删改 ----------

  void _openEditor({Lesson? lesson, int? day, String? slot}) {
    final settings = widget.store.settings();
    final periods = settings.periods;
    if (periods.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('还不能添加课程'),
          content: const Text('节次列表是空的，先到「设置 → 作息与节次」里添加至少一条节次。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final days = dayOrder(settings.weekStartsOn);
    final todayWeek = weekOf(DateTime.now(), settings.week1Monday);
    final now = DateTime.now();
    // 和电脑版一致：编辑用课本身的星期；新增默认今天是星期几（不在本周就给周一）。
    final defaultDay = lesson?.day ?? ((todayWeek == _week) ? dayOfWeek(now) : 1);

    var selDay = defaultDay;
    var selSlot = (lesson?.slot.isNotEmpty ?? false) &&
            periods.any((p) => p.id == lesson!.slot)
        ? lesson!.slot
        : (periods.any((p) => p.id == slot) ? slot! : periods.first.id);
    var selEnd = lesson != null &&
            lesson.spanEnd.isNotEmpty &&
            periods.any((p) => p.id == lesson.spanEnd)
        ? lesson.spanEnd
        : '';
    final nameCtl = TextEditingController(text: lesson?.name ?? '');
    final locCtl = TextEditingController(text: lesson?.location ?? '');
    final teaCtl = TextEditingController(text: lesson?.teacher ?? '');
    final noteCtl = TextEditingController(text: lesson?.note ?? '');
    // 错误提示要放在 builder 外面：StatefulBuilder 重跑 builder 时不会被重置。
    String? nameError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void save() {
            final err = validateCourseName(nameCtl.text);
            if (err != null) {
              setSheet(() => nameError = err);
              return;
            }
            final list = widget.store.listWeek(_week);
            if (lesson == null) {
              list.add(Lesson(
                id: widget.store.newId('c'),
                day: selDay,
                slot: selSlot,
                spanEnd: selEnd,
                name: nameCtl.text.trim(),
                location: locCtl.text.trim(),
                teacher: teaCtl.text.trim(),
                note: noteCtl.text.trim(),
              ));
            } else {
              final idx = list.indexWhere((l) => l.id == lesson.id);
              final updated = lesson.copyWith(
                day: selDay,
                slot: selSlot,
                spanEnd: selEnd,
                name: nameCtl.text.trim(),
                location: locCtl.text.trim(),
                teacher: teaCtl.text.trim(),
                note: noteCtl.text.trim(),
              );
              if (idx >= 0) {
                list[idx] = updated;
              } else {
                list.add(updated); // 找不到就当新增，别把改动弄丢
              }
            }
            widget.store.saveWeek(_week, list);
            Navigator.of(ctx).pop();
            setState(() {});
            _toast('已保存');
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(lesson == null ? '添加课程' : '编辑课程',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtl,
                    autofocus: lesson == null,
                    decoration: InputDecoration(
                      labelText: '课程名',
                      hintText: '自己填',
                      errorText: nameError,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('f-day'),
                        initialValue: selDay,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '星期'),
                        items: <DropdownMenuItem<int>>[
                          for (final d in days)
                            DropdownMenuItem<int>(value: d.num, child: Text(d.name)),
                        ],
                        onChanged: (v) => setSheet(() => selDay = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('f-slot'),
                        initialValue: selSlot,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '开始节次'),
                        items: <DropdownMenuItem<String>>[
                          for (final p in periods)
                            DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(
                                '${p.label.isEmpty ? '未命名' : p.label} ${timeRange(p)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setSheet(() => selSlot = v ?? periods.first.id),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('f-end'),
                    initialValue: selEnd,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '跨到哪一节（可选）'),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(value: '', child: Text('不跨节次')),
                      for (final p in periods)
                        DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(p.label.isEmpty ? '未命名' : p.label),
                        ),
                    ],
                    onChanged: (v) => setSheet(() => selEnd = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  Row(children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: locCtl,
                        decoration: const InputDecoration(labelText: '地点'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: teaCtl,
                        decoration: const InputDecoration(labelText: '老师'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtl,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  const SizedBox(height: 16),
                  Row(children: <Widget>[
                    if (lesson != null)
                      TextButton(
                        key: const ValueKey('btn-del-course'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: () {
                          final list = widget.store
                              .listWeek(_week)
                              .where((l) => l.id != lesson.id)
                              .toList();
                          widget.store.saveWeek(_week, list);
                          Navigator.of(ctx).pop();
                          setState(() {});
                          _toast('已删除');
                        },
                        child: const Text('删除'),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('btn-save-course'),
                      onPressed: save,
                      child: const Text('保存'),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- 整周复制 ----------

  void _openCopyDialog(int count) {
    // 默认选中下一周（和电脑版一样：min(当前+1, 20)）。
    final selected = <int>{_week < 20 ? _week + 1 : 20};
    var mode = CopyMode.overwrite;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('复制第 $_week 周的课表',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('本周共 $count 节课，选择目标周（可多选），整周铺过去。',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
              const SizedBox(height: 12),
              Wrap(
                key: const ValueKey('copy-chips'),
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (var w = 1; w <= 20; w++)
                    FilterChip(
                      key: ValueKey('chip-w$w'),
                      label: Text('第 $w 周'),
                      selected: selected.contains(w),
                      onSelected: (v) =>
                          setSheet(() => v ? selected.add(w) : selected.remove(w)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('copy-mode'),
                initialValue: mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '遇到目标周已有课程时'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: CopyMode.overwrite, child: Text('覆盖目标周')),
                  DropdownMenuItem<String>(
                      value: CopyMode.merge, child: Text('保留两边（合并）')),
                  DropdownMenuItem<String>(
                      value: CopyMode.emptyOnly, child: Text('只填空的周')),
                ],
                onChanged: (v) => setSheet(() => mode = v ?? CopyMode.overwrite),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('btn-do-copy'),
                  onPressed: () {
                    if (selected.isEmpty) {
                      _toast('还没选目标周');
                      return;
                    }
                    final courses = widget.store.courses();
                    copyWeek(
                        courses, _week, selected.toList(), mode, widget.store.newId);
                    widget.store.saveCourses(courses);
                    Navigator.of(ctx).pop();
                    setState(() {});
                    _toast('已复制到 ${selected.length} 周');
                  },
                  child: const Text('开始复制'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 清空本周 ----------

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空第 $_week 周'),
        content: const Text('会删掉这一周的全部课程，不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('btn-confirm-clear'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              widget.store.saveWeek(_week, <Lesson>[]);
              Navigator.of(ctx).pop();
              setState(() {});
              _toast('已清空');
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final settings = widget.store.settings();
    final periods = settings.periods;
    final courses = widget.store.courses();
    final lessons = courses.week(_week);
    final cs = Theme.of(context).colorScheme;

    return Column(
      key: const ValueKey('page-courses'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(children: <Widget>[
            DropdownButton<int>(
              key: const ValueKey('week-sel'),
              value: _week < 1 ? 1 : (_week > 20 ? 20 : _week),
              items: <DropdownMenuItem<int>>[
                for (var i = 1; i <= 20; i++)
                  DropdownMenuItem<int>(value: i, child: Text('第 $i 周')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _week = v);
              },
            ),
            TextButton.icon(
              key: const ValueKey('btn-today'),
              onPressed: _goToday,
              icon: const Icon(Icons.today, size: 18),
              label: const Text('回到今天'),
            ),
            TextButton.icon(
              key: const ValueKey('btn-import'),
              onPressed: _importTimetable,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('导入'),
            ),
            const Spacer(),
            Text('本周 ${lessons.length} 节课',
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            weekRangeText(_week, settings.week1Monday),
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: <Widget>[
              _toolbarBtn(
                key: const ValueKey('btn-add-course'),
                onPressed: () => _openEditor(),
                icon: Icons.add,
                label: '添加课程',
              ),
              _toolbarBtn(
                key: const ValueKey('btn-copy-week'),
                onPressed: () => _openCopyDialog(lessons.length),
                icon: Icons.copy_all_outlined,
                label: '复制整周',
              ),
              _toolbarBtn(
                key: const ValueKey('btn-clear-week'),
                onPressed: _confirmClear,
                icon: Icons.delete_outline,
                label: '清空本周',
              ),
              _toolbarBtn(
                key: const ValueKey('btn-merge'),
                onPressed: _toggleMergeMode,
                icon: Icons.join_full_outlined,
                label: _mergeMode ? '取消合并' : '合并',
                highlighted: _mergeMode,
              ),
            ],
          ),
        ),
        if (_mergeMode)
          Container(
            key: const ValueKey('merge-banner'),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: <Widget>[
              Expanded(
                child: Text(
                  _mergeSel.length < 2
                      ? '合并模式：点选同一节课的 2~3 个相邻格子'
                      : '已选 ${_mergeSel.length} 格，点「合并」变成一节连堂',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                key: const ValueKey('btn-merge-cancel'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _exitMergeMode,
                child: const Text('取消'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                key: const ValueKey('btn-merge-confirm'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _mergeSel.length < 2 ? null : _doMerge,
                child: const Text('合并'),
              ),
            ]),
          ),
        Expanded(
          child: periods.isEmpty
              ? _emptyPeriods(cs)
              : _buildTable(periods, lessons, settings),
        ),
      ],
    );
  }

  /// 节次一个都没有时的引导（和电脑版空态文案一致）。
  Widget _emptyPeriods(ColorScheme cs) {
    return Center(
      key: const ValueKey('courses-no-periods'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.view_agenda_outlined, size: 46, color: cs.outline),
            const SizedBox(height: 12),
            const Text('还没有任何节次',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(
              '节次名称和时间完全由你定义，去「设置 → 作息与节次」添加后，'
              '这里会出现对应的课表网格。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }

  /// 工具栏按钮：四个平分一行。
  Widget _toolbarBtn(
      {required Key key,
      required VoidCallback onPressed,
      required IconData icon,
      required String label,
      bool highlighted = false}) {
    return Expanded(
      child: OutlinedButton.icon(
        key: key,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor:
              highlighted ? Theme.of(context).colorScheme.primary : null,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  /// 长按复制的课（应用内剪贴板，切周不清除）
  Lesson? _copied;

  /// 长按有课的格子 = 复制这节课；长按空格子 = 把复制的课贴过来（单节）。
  void _onCellLongPress(Lesson? lesson, int day, String slot) {
    if (lesson != null) {
      if (lesson.name.isEmpty) {
        _toast('这节课没名字，不用复制');
        return;
      }
      setState(() => _copied = lesson);
      _toast('已复制「${lesson.name}」，长按空格子粘贴');
      return;
    }
    final src = _copied;
    if (src == null) {
      _toast('还没有复制的课，先长按一节有课的格子');
      return;
    }
    // 只贴成单节：跨节次的课贴过去容易被别的课占位，宁可简单可靠
    final courses = widget.store.courses();
    final weekList = courses.weeks[_week] ?? <Lesson>[];
    weekList.add(src.copyWith(
      id: widget.store.newId('c'),
      day: day,
      slot: slot,
      spanEnd: '',
    ));
    courses.weeks[_week] = weekList;
    widget.store.saveCourses(courses);
    setState(() {});
    _toast('已粘贴「${src.name}」（第 $day 天 $slot）');
  }

  // ---------- 合并模式 ----------

  bool _mergeMode = false;
  final Set<String> _mergeSel = <String>{}; // 'day@slot'

  void _toggleMergeMode() {
    setState(() {
      _mergeMode = !_mergeMode;
      _mergeSel.clear();
    });
  }

  void _exitMergeMode() {
    setState(() {
      _mergeMode = false;
      _mergeSel.clear();
    });
  }

  /// 合并模式里点格子：只允许同一天、节次相邻，最多选到节次表末尾。
  void _toggleMergeCell(int day, String slot, List<Period> periods) {
    final key = '$day@$slot';
    setState(() {
      if (_mergeSel.remove(key)) return;
      if (_mergeSel.isEmpty) {
        _mergeSel.add(key);
        return;
      }
      // 校验：同一天 + 与已选的节次相邻
      String dayOf(String k) => k.split('@')[0];
      String slotOf(String k) => k.split('@')[1];
      final sameDay = _mergeSel.every((k) => dayOf(k) == '$day');
      if (!sameDay) {
        _toast('要合并的格子必须在同一天');
        return;
      }
      int idxOf(String s) => periods.indexWhere((p) => p.id == s);
      final idxs = _mergeSel.map((k) => idxOf(slotOf(k))).toList()..sort();
      final myIdx = idxOf(slot);
      if (myIdx < 0) return;
      final minIdx = idxs.first, maxIdx = idxs.last;
      if (myIdx != minIdx - 1 && myIdx != maxIdx + 1) {
        _toast('只能选相邻的节次');
        return;
      }
      _mergeSel.add(key);
    });
  }

  /// 执行合并：选中范围内的旧课全部去掉，换成一条 spanEnd 到最后节次的课。
  void _doMerge() {
    final periods = widget.store.settings().periods;
    if (_mergeSel.length < 2) return;
    final day = int.parse(_mergeSel.first.split('@')[0]);
    final idxs = _mergeSel
        .map((k) => periods.indexWhere((p) => p.id == k.split('@')[1]))
        .toList()
      ..sort();
    for (var i = 1; i < idxs.length; i++) {
      if (idxs[i] != idxs[i - 1] + 1) {
        _toast('只能合并相邻的节次');
        return;
      }
    }
    final first = periods[idxs.first];
    final last = periods[idxs.last];
    final slotSet = _mergeSel.map((k) => k.split('@')[1]).toSet();

    final courses = widget.store.courses();
    final weekList = courses.weeks[_week] ?? <Lesson>[];
    // 范围内的旧课：拿第一门有名字的当内容，其余全部移除
    Lesson? merged;
    weekList.removeWhere((l) {
      if (l.day != day || !slotSet.contains(l.slot)) return false;
      merged ??= l;
      return true;
    });
    final src = merged;
    weekList.add(Lesson(
      id: widget.store.newId('c'),
      day: day,
      slot: first.id,
      spanEnd: last.id,
      name: src?.name ?? '',
      location: src?.location ?? '',
      teacher: src?.teacher ?? '',
      note: src?.note ?? '',
      color: src?.color ?? '',
    ));
    courses.weeks[_week] = weekList;
    widget.store.saveCourses(courses);
    _exitMergeMode();
    _toast('已合并成 ${idxs.length} 节连堂');
  }

  Widget _buildTable(List<Period> periods, List<Lesson> lessons, Settings settings) {
    final days = dayOrder(settings.weekStartsOn);
    final now = DateTime.now();
    final todayWeek = weekOf(now, settings.week1Monday);
    final todayDow = dayOfWeek(now);
    final cs = Theme.of(context).colorScheme;
    final pitch = _cellH + _cellGap;

    Widget header(String text, {bool highlight = false}) => SizedBox(
          height: _headH,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: highlight ? cs.primary : null,
              ),
            ),
          ),
        );

    // 最左边一列：节次名 + 时间。
    final labelColumn = SizedBox(
      width: _labelW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header('节次'),
          for (final p in periods)
            SizedBox(
              height: pitch,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, _cellGap),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      p.label.isEmpty ? '未命名' : p.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      timeRange(p),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: TextStyle(fontSize: 9, color: cs.outline, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    // 一天一列。跨节次的课块占多行高度，后面的格子跳过。
    Widget dayColumn(CourseDay d) {
      final isToday = todayWeek == _week && todayDow == d.num;
      final cells = <Widget>[header(d.name, highlight: isToday)];
      final skip = <int>{};
      for (var pi = 0; pi < periods.length; pi++) {
        if (skip.contains(pi)) continue;
        final p = periods[pi];
        Lesson? lesson;
        for (final l in lessons) {
          if (l.day == d.num && l.slot == p.id) {
            lesson = l;
            break;
          }
        }
        var span = 1;
        if (lesson != null && lesson.spanEnd.isNotEmpty) {
          final endIdx = periods.indexWhere((x) => x.id == lesson!.spanEnd);
          if (endIdx > pi) {
            span = endIdx - pi + 1;
            for (var k = pi + 1; k <= endIdx; k++) {
              skip.add(k);
            }
          }
        }
        final h = span * pitch - _cellGap;
        final isCopied = lesson != null && lesson.id == _copied?.id;
        final isSel = _mergeMode && _mergeSel.contains('${d.num}@${p.id}');
        cells.add(
          GestureDetector(
            key: lesson != null
                ? ValueKey('lesson-${lesson.id}')
                : ValueKey('cell-${d.num}-${p.id}'),
            onTap: _mergeMode
                ? () => _toggleMergeCell(d.num, p.id, periods)
                : () => _openEditor(lesson: lesson, day: d.num, slot: p.id),
            // 长按有课的格子 = 复制；长按空格子 = 粘贴（凯森 v1.4.1 反馈）
            onLongPress:
                _mergeMode ? null : () => _onCellLongPress(lesson, d.num, p.id),
            child: Container(
              height: h,
              margin: const EdgeInsets.only(right: _cellGap, bottom: _cellGap),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSel
                    ? cs.primary.withValues(alpha: 0.35)
                    : lesson == null
                        ? cs.surfaceContainerHighest
                        : cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: (isCopied || isSel)
                    ? Border.all(
                        color: cs.primary, width: isSel ? 2 : 1.5)
                    : null,
              ),
              alignment: Alignment.topLeft,
              child: lesson == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          lesson.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          periodLabel(lesson.slot, periods) +
                              (lesson.spanEnd.isNotEmpty
                                  ? ' - ${periodLabel(lesson.spanEnd, periods)}'
                                  : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, color: cs.outline),
                        ),
                        if (lesson.location.isNotEmpty)
                          Text(
                            lesson.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                      ],
                    ),
            ),
          ),
        );
      }
      return SizedBox(
        key: ValueKey('day-col-${d.num}'),
        width: _dayW,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      );
    }

    // 缩放：双指捏合缩小到「刚好完整看到整张表」，放大看细节（凯森 v1.3.8 反馈）。
    // 缩小时列宽跟着缩，横向不再需要滚动条。
    final tableW = _labelW + _dayW * days.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LayoutBuilder(builder: (context, cons) {
        final fit = cons.maxWidth.isFinite && tableW > 0
            ? cons.maxWidth / tableW
            : 1.0;
        return InteractiveViewer(
          constrained: false,
          minScale: fit.clamp(0.4, 1.0),
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(24),
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: tableW,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[labelColumn, ...days.map(dayColumn)],
            ),
          ),
        );
      }),
    );
  }
}
