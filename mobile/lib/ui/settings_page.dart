/// 设置页：基本 / 天气 / 作息与节次 / 数据（备份导出、还原、清空）。
///
/// 区块与文案对齐电脑版设置页（`app/static/index.html` 的 settings 区 +
/// `app.js` 的备份/还原/清空三个按钮）：
/// - 每一处改动立即落盘（数据文件就几 KB，同步写没有压力）；
/// - 还原前先自动给当前数据留一份备份；清空必须输入「清空」两个字；
/// - 外观改动通过 [SettingsPage.onChanged] 一路通知到 MaterialApp 重建。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backup.dart';
import '../models.dart';
import '../store.dart';
import '../weather_api.dart';
import '../weather_logic.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    this.onChanged,
    this.pickZip,
    this.api,
  });

  final Store store;

  /// 任何设置变化后回调（ MyApp 用它重建，让外观/教学周等立即生效）。
  final VoidCallback? onChanged;

  /// 选一个备份 zip 的字节；返回 null 表示没选。测试注入假选择器。
  final Future<List<int>?> Function()? pickZip;

  /// 测试时注入假天气接口；不传就用真的 Open-Meteo。
  final WeatherApi? api;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _s = widget.store.settings();
  late final TextEditingController _nameCtrl = TextEditingController(text: _s.displayName);
  late final TextEditingController _semCtrl = TextEditingController(text: _s.semesterName);
  late final TextEditingController _campusCtrl = TextEditingController(text: _s.campus);
  late final WeatherApi _api = widget.api ?? WeatherApi();

  bool _addingPlace = false;
  final TextEditingController _placeCtrl = TextEditingController();
  bool _searching = false;
  List<CitySuggestion> _results = <CitySuggestion>[];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => _save((s) => s.displayName = _nameCtrl.text));
    _semCtrl.addListener(() => _save((s) => s.semesterName = _semCtrl.text));
    _campusCtrl.addListener(() => _save((s) => s.campus = _campusCtrl.text));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _semCtrl.dispose();
    _campusCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  /// 改一处就落一处（像电脑版一样随手存）。
  void _save(void Function(Settings) mutate) {
    mutate(_s);
    widget.store.saveSettings(_s);
    if (mounted) setState(() {}); // 让空态/开关状态跟着重画
    widget.onChanged?.call();
  }

  /// 还原/清空之后把整页状态重读一遍。
  void _reload() {
    setState(() => _s = widget.store.settings());
    widget.onChanged?.call();
  }

  // ---------- 备份 / 还原 / 清空 ----------

  Future<void> _doBackup() async {
    try {
      final path = saveBackupFile(widget.store, buildBackupZip(widget.store));
      _toast('已备份：${path.split('/').last.split('\\').last}');
    } catch (e) {
      _toast('备份失败：$e');
    }
  }

  Future<List<int>?> _pickZip() async {
    if (widget.pickZip != null) return widget.pickZip!();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
      withData: true,
    );
    return result?.files.single.bytes;
  }

  Future<void> _doRestore() async {
    List<int>? raw;
    String fileName = '';
    try {
      raw = await _pickZip();
      if (raw == null) {
        _toast('先选择一个备份 zip');
        return;
      }
      // 先校验，能解析才弹确认框
      final manifest = inspectBackup(raw);
      fileName = asString(manifest['exportedAt']);
    } on BackupException catch (e) {
      _toast(e.message);
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('还原备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('用这份备份覆盖当前全部数据？还原前会自动给现在的数据留一份备份。',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text('导出于 $fileName',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            key: const ValueKey('btn-confirm-restore'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认还原'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      safetyBackup(widget.store); // 手滑也能找回来
      restoreBackup(widget.store, raw);
      _reload();
      _toast('还原成功');
    } on BackupException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('还原失败：$e');
    }
  }

  Future<void> _doReset() async {
    final wordCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空全部数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('课程、备忘录、天气缓存和设置都会被清掉。清空前会自动备份一次。',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('reset-word'),
              controller: wordCtrl,
              decoration: const InputDecoration(
                labelText: '确认方式：输入「清空」两个字',
                hintText: '清空',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            key: const ValueKey('btn-confirm-reset'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              if (wordCtrl.text.trim() != '清空') {
                _toast('请先输入「清空」两个字');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final name = safetyBackup(widget.store);
      resetAllData(widget.store);
      _reload();
      _toast('已清空，备份文件：$name');
    } catch (e) {
      _toast('清空失败：$e');
    }
  }

  // ---------- 我的地点 ----------

  Future<void> _searchPlaces() async {
    final q = _placeCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _searchError = '输入城市名');
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await _api.searchCities(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
        if (r.isEmpty) _searchError = '没有找到「$q」，换个名字试试';
      });
    } on WeatherApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = '搜索失败：$e';
      });
    }
  }

  void _addPlace(CitySuggestion c) {
    try {
      final write = addPlace(_s.weatherCities, c.toPlaceData(),
          newId: () => widget.store.newId('p'));
      _save((s) {
        s.weatherCities = write.places;
        s.weatherCity = write.current;
      });
      setState(() => _results = const <CitySuggestion>[]);
      _toast('已添加 ${c.name}');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  void _selectPlace(Place p) {
    final write = selectPlace(_s.weatherCities, p.id);
    if (write == null) return;
    _save((s) {
      s.weatherCities = write.places;
      s.weatherCity = write.current;
    });
  }

  void _removePlace(Place p) {
    final write = removePlace(_s.weatherCities, _s.weatherCity, p.id);
    _save((s) {
      s.weatherCities = write.places;
      s.weatherCity = write.current;
    });
  }

  // ---------- 节次 ----------

  void _addPeriod() {
    _save((s) => s.periods.add(Period(id: widget.store.newId('p'))));
  }

  void _removePeriod(String id) {
    _save((s) => s.periods.removeWhere((p) => p.id == id));
  }

  Future<void> _pickWeek1Monday() async {
    final initial = DateTime.tryParse(_s.week1Monday) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择第 1 周周一日期',
    );
    if (picked == null) return;
    final mm = picked.month < 10 ? '0${picked.month}' : '${picked.month}';
    final dd = picked.day < 10 ? '0${picked.day}' : '${picked.day}';
    _save((s) => s.week1Monday = '${picked.year}-$mm-$dd');
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('page-settings'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        _card(context, '基本', <Widget>[
          _field('称呼', '首页问候用，随便填',
              TextField(
                key: const ValueKey('s-name'),
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: '未填写'),
              )),
          _field('学期名', '只用于显示',
              TextField(
                key: const ValueKey('s-semester'),
                controller: _semCtrl,
                decoration: const InputDecoration(hintText: '例如：本学期'),
              )),
          _field('第 1 周周一日期', '必填，用来算今天是第几教学周',
              InkWell(
                key: const ValueKey('s-week1'),
                onTap: _pickWeek1Monday,
                child: InputDecorator(
                  isEmpty: _s.week1Monday.isEmpty,
                  decoration: const InputDecoration(
                      hintText: '未选择', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                  child: Text(_s.week1Monday.isEmpty ? '' : _s.week1Monday),
                ),
              )),
          _field('每周起始日', null,
              DropdownButtonFormField<int>(
                key: const ValueKey('s-weekstart'),
                initialValue: _s.weekStartsOn,
                isExpanded: true,
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem<int>(value: 1, child: Text('周一')),
                  DropdownMenuItem<int>(value: 7, child: Text('周日')),
                ],
                onChanged: (int? v) => v == null ? null : _save((s) => s.weekStartsOn = v),
              )),
          _field('校区 / 地点备注', '可留空',
              TextField(
                key: const ValueKey('s-campus'),
                controller: _campusCtrl,
                decoration: const InputDecoration(hintText: '未填写'),
              )),
          _field('外观', null,
              DropdownButtonFormField<String>(
                key: const ValueKey('s-theme'),
                initialValue: _s.theme,
                isExpanded: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem<String>(value: 'light', child: Text('浅色')),
                  DropdownMenuItem<String>(value: 'dark', child: Text('深色')),
                ],
                onChanged: (String? v) => v == null ? null : _save((s) => s.theme = v),
              )),
        ]),
        _card(context, '天气', <Widget>[
          _rowTitle('我的地点', '选中即切换，右侧 × 移除'),
          if (_s.weatherCities.isEmpty)
            Text('还没有保存的地点',
                key: const ValueKey('s-places-empty'),
                style: TextStyle(fontSize: 12, color: cs.outline))
          else
            for (final p in _s.weatherCities)
              _placeRow(context, p),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('s-add-place'),
            onPressed: () => setState(() => _addingPlace = !_addingPlace),
            icon: Icon(_addingPlace ? Icons.close : Icons.add),
            label: Text(_addingPlace ? '收起' : '＋ 添加地点'),
          ),
          if (_addingPlace) ...<Widget>[
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Expanded(
                child: TextField(
                  key: const ValueKey('s-place-q'),
                  controller: _placeCtrl,
                  decoration: const InputDecoration(hintText: '输入城市名'),
                  onSubmitted: (_) => _searchPlaces(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('s-place-search'),
                onPressed: _searching ? null : _searchPlaces,
                icon: const Icon(Icons.search),
              ),
            ]),
            if (_searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_searchError!,
                    style: TextStyle(fontSize: 12, color: cs.error)),
              ),
            for (final c in _results)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: InkWell(
                  key: ValueKey('s-place-result-${c.name}'),
                  onTap: () => _addPlace(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(c.name, style: const TextStyle(fontSize: 13)),
                        ),
                        if (c.admin.isNotEmpty)
                          Text(c.admin,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          _field('自动刷新', null,
              DropdownButtonFormField<int>(
                key: const ValueKey('s-refresh'),
                initialValue: _s.refreshMinutes,
                isExpanded: true,
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem<int>(value: 10, child: Text('10 分钟')),
                  DropdownMenuItem<int>(value: 30, child: Text('30 分钟')),
                  DropdownMenuItem<int>(value: 60, child: Text('1 小时')),
                  DropdownMenuItem<int>(value: 0, child: Text('仅手动')),
                ],
                onChanged: (int? v) => v == null ? null : _save((s) => s.refreshMinutes = v),
              )),
        ]),
        _card(context, '作息与节次（全部自定义）', <Widget>[
          if (_s.periods.isEmpty)
            Text('还没有节次，先添加几条吧',
                key: const ValueKey('s-periods-empty'),
                style: TextStyle(fontSize: 12, color: cs.outline))
          else
            for (final p in _s.periods)
              _PeriodRow(
                key: ValueKey('s-period-${p.id}'),
                period: p,
                onChanged: (Period next) {
                  _save((s) {
                    final i = s.periods.indexWhere((x) => x.id == next.id);
                    if (i >= 0) s.periods[i] = next;
                  });
                },
                onRemove: () => _removePeriod(p.id),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('s-add-period'),
            onPressed: _addPeriod,
            icon: const Icon(Icons.add),
            label: const Text('+ 添加节次'),
          ),
          const SizedBox(height: 4),
          Text('点一下加一条，名称和起止时间随便填，支持中午时段、晚课、实训',
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ]),
        _card(context, '数据', <Widget>[
          _dataLine(
            '手动备份',
            '导出 zip，同时在本机留一份',
            FilledButton(
              key: const ValueKey('btn-backup'),
              onPressed: _doBackup,
              child: const Text('立即备份'),
            ),
          ),
          _dataLine(
            '从备份还原',
            '选择之前导出的 zip',
            OutlinedButton(
              key: const ValueKey('btn-restore'),
              onPressed: _doRestore,
              child: const Text('还原'),
            ),
          ),
          _dataLine(
            '清空全部数据',
            '不可撤销，会先自动备份',
            OutlinedButton(
              key: const ValueKey('btn-reset'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _doReset,
              child: const Text('清空'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _field(String label, String? desc, Widget input) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 13)),
                if (desc != null)
                  Text(desc,
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 4, child: input),
        ],
      ),
    );
  }

  Widget _rowTitle(String label, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(desc,
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _placeRow(BuildContext context, Place p) {
    final cs = Theme.of(context).colorScheme;
    final current = isCurrentPlace(_s.weatherCity, p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(
            current ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: current ? cs.primary : cs.outline,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(p.label, style: const TextStyle(fontSize: 13))),
          TextButton(
            key: ValueKey('s-place-use-${p.id}'),
            onPressed: current ? null : () => _selectPlace(p),
            child: const Text('切换'),
          ),
          IconButton(
            key: ValueKey('s-place-del-${p.id}'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _removePlace(p),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _dataLine(String label, String desc, Widget button) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 13)),
                Text(desc,
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          button,
        ],
      ),
    );
  }
}

/// 一行节次：名称 + 起止时间 + 删除。控制器跟着行走，改动通过回调落盘。
class _PeriodRow extends StatefulWidget {
  const _PeriodRow({
    super.key,
    required this.period,
    required this.onChanged,
    required this.onRemove,
  });

  final Period period;
  final ValueChanged<Period> onChanged;
  final VoidCallback onRemove;

  @override
  State<_PeriodRow> createState() => _PeriodRowState();
}

class _PeriodRowState extends State<_PeriodRow> {
  late final TextEditingController _label = TextEditingController(text: widget.period.label);
  late final TextEditingController _start = TextEditingController(text: widget.period.start);
  late final TextEditingController _end = TextEditingController(text: widget.period.end);

  @override
  void initState() {
    super.initState();
    void bind(TextEditingController c) {
      c.addListener(() {
        widget.onChanged(Period(
          id: widget.period.id,
          label: _label.text,
          start: _start.text,
          end: _end.text,
          extra: Map<String, dynamic>.from(widget.period.extra),
        ));
      });
    }

    bind(_label);
    bind(_start);
    bind(_end);
  }

  @override
  void dispose() {
    _label.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: TextField(
              key: ValueKey('s-period-label-${widget.period.id}'),
              controller: _label,
              decoration: const InputDecoration(hintText: '节次名', isDense: true),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('s-period-start-${widget.period.id}'),
              controller: _start,
              decoration: const InputDecoration(hintText: '开始 如 08:10', isDense: true),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('s-period-end-${widget.period.id}'),
              controller: _end,
              decoration: const InputDecoration(hintText: '结束 如 08:50', isDense: true),
            ),
          ),
          IconButton(
            key: ValueKey('s-period-del-${widget.period.id}'),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
