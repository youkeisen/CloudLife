/// 设置页：基本 / 天气 / 作息与节次 / 数据（备份导出、还原、清空）。
///
/// 区块与文案对齐电脑版设置页（`app/static/index.html` 的 settings 区 +
/// `app.js` 的备份/还原/清空三个按钮）：
/// - 每一处改动立即落盘（数据文件就几 KB，同步写没有压力）；
/// - 还原前先自动给当前数据留一份备份；清空必须输入「清空」两个字；
/// - 外观改动通过 [SettingsPage.onChanged] 一路通知到 MaterialApp 重建。
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker, FixedExtentScrollController;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../backup.dart';
import '../changelog.dart' show kChangelog;
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
    this.pickTime,
    this.locate,
  });

  final Store store;

  /// 任何设置变化后回调（ MyApp 用它重建，让外观/教学周等立即生效）。
  final VoidCallback? onChanged;

  /// 节次时间选择器（测试注入用）；不给就走系统时间选择对话框。
  final Future<TimeOfDay?> Function(TimeOfDay initial)? pickTime;

  /// 定位加地点（测试注入用）：返回坐标 + 反查出的城市名；不给就走真定位。
  /// 返回 null 表示用户没给权限/定位不可用。
  final Future<LocateSpot?> Function()? locate;


  /// 选一个备份 zip 的字节；返回 null 表示没选。测试注入假选择器。
  final Future<List<int>?> Function()? pickZip;

  /// 测试时注入假天气接口；不传就用真的 Open-Meteo。
  final WeatherApi? api;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _s = widget.store.settings();
  late final WeatherApi _api = widget.api ?? WeatherApi();

  bool _addingPlace = false;
  final TextEditingController _placeCtrl = TextEditingController();
  bool _searching = false;
  List<CitySuggestion> _results = <CitySuggestion>[];
  String? _searchError;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // 「关于」里展示的版本号来自安装包本身（pubspec 的 version）
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _appVersion = info.version;
          _appBuild = info.buildNumber;
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
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

  /// 定位加地点：拿到坐标和城市名后，走和搜索添加同一套落库逻辑。
  Future<void> _locateAdd() async {
    setState(() => _locating = true);
    try {
      final spot = await (widget.locate?.call() ?? _locateReal());
      if (spot == null) {
        _toast('没有拿到定位权限，或定位不可用');
        return;
      }
      final write = addPlace(
        _s.weatherCities,
        <String, dynamic>{
          'name': spot.name,
          'admin': spot.admin,
          'latitude': spot.latitude,
          'longitude': spot.longitude,
        },
        newId: () => widget.store.newId('p'),
      );
      _save((s) {
        s.weatherCities = write.places;
        s.weatherCity = write.current;
      });
      _toast('已定位添加 ${spot.name}');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('定位失败：$e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 真定位：geolocator 拿坐标 + Nominatim 反查城市名。
  /// 先查定位服务开关，再用最近位置（秒回），最后才等 GPS 实测。
  Future<LocateSpot?> _locateReal() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      throw const FormatException('手机的定位服务（GPS）没开，下拉控制中心打开后再试');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }
    // 最近位置可能没有缓存（null），那就现场等 GPS，超时放宽到 30 秒。
    // 安卓上强制走系统定位服务：部分国产机的融合定位会卡住不返回。
    Position? pos = await Geolocator.getLastKnownPosition();
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.medium,
                  timeLimit: const Duration(seconds: 30),
                  forceLocationManager: true,
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.medium,
                  timeLimit: Duration(seconds: 30),
                ),
        );
      } on TimeoutException {
        throw const FormatException('定位超时：室内可能收不到 GPS，到窗边或连上 Wi-Fi 再试一次');
      }
    }
    final city =
        await _api.reverseGeocode(pos.latitude, pos.longitude);
    return LocateSpot(
      latitude: city.latitude ?? pos.latitude,
      longitude: city.longitude ?? pos.longitude,
      name: city.name,
      admin: city.admin,
    );
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
      // 底部留 110：悬浮底栏是盖在内容上的，不留会被挡住（凯森 v1.3.5 反馈）
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
      children: <Widget>[
        _cardCollapsible(context, '基本',
            key: const ValueKey('s-basic-card'),
            toggleKey: 's-basic-toggle',
            open: _basicOpen,
            onToggle: () { _basicOpen = !_basicOpen; _toggleCollapse('basic'); },
            children: <Widget>[
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
        _cardCollapsible(context, '天气',
            key: const ValueKey('s-weather-card'),
            toggleKey: 's-weather-toggle',
            open: _weatherOpen,
            onToggle: () { _weatherOpen = !_weatherOpen; _toggleCollapse('weather'); },
            summary: _s.weatherCities.isEmpty ? '还没设' : '${_s.weatherCities.length} 个地点',
            children: <Widget>[
          _rowTitle('我的地点', '选中即切换，右侧 × 移除'),
          if (_s.weatherCities.isEmpty)
            Text('还没有保存的地点',
                key: const ValueKey('s-places-empty'),
                style: TextStyle(fontSize: 12, color: cs.outline))
          else
            for (final p in _s.weatherCities)
              _placeRow(context, p),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            OutlinedButton.icon(
              key: const ValueKey('s-add-place'),
              onPressed: () => setState(() => _addingPlace = !_addingPlace),
              icon: Icon(_addingPlace ? Icons.close : Icons.add),
              label: Text(_addingPlace ? '收起' : '＋ 添加地点'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey('s-locate-place'),
              onPressed: _locating ? null : _locateAdd,
              icon: _locating
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 18),
              label: const Text('定位添加'),
            ),
          ]),
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
        _cardCollapsible(context, '作息与节次（全部自定义）',
            key: const ValueKey('s-periods-card'),
            toggleKey: 's-periods-toggle',
            open: _periodsOpen,
          onToggle: () { _periodsOpen = !_periodsOpen; _toggleCollapse('periods'); },
          summary: _s.periods.isEmpty ? '还没设' : '${_s.periods.length} 个节次',
          children: <Widget>[
          if (_s.periods.isEmpty)
            Text('还没有节次，先添加几条吧',
                key: const ValueKey('s-periods-empty'),
                style: TextStyle(fontSize: 12, color: cs.outline))
          else
            for (final p in _s.periods)
              _PeriodRow(
                key: ValueKey('s-period-${p.id}'),
                period: p,
                pickTime: widget.pickTime,
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
        _cardCollapsible(context, '数据',
            key: const ValueKey('s-data-card'),
            toggleKey: 's-data-toggle',
            open: _dataOpen,
            onToggle: () { _dataOpen = !_dataOpen; _toggleCollapse('data'); },
            children: <Widget>[
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
        _cardCollapsible(context, '关于',
            key: const ValueKey('s-about-card'),
            toggleKey: 's-about-toggle',
            open: _aboutOpen,
            onToggle: () { _aboutOpen = !_aboutOpen; _toggleCollapse('about'); },
            summary: _appVersion.isEmpty ? '' : 'v$_appVersion',
            children: <Widget>[
              Row(children: <Widget>[
                const Text('云生活',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  _appVersion.isEmpty
                      ? '版本号读取中…'
                      : 'v$_appVersion（构建 $_appBuild）',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('更新日志',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final entry in kChangelog) ...<Widget>[
                Text('v${entry.$1}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
                for (final line in entry.$2)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 2),
                    child: Text('· $line',
                        style: TextStyle(
                            fontSize: 12, color: cs.outline, height: 1.35)),
                  ),
                const SizedBox(height: 8),
              ],
        ]),
      ],
    );
  }

  /// 卡片收放状态记在设置文件的 extra.ui 里，重进不丢（凯森 v1.3.7 反馈）。
  /// 作息与节次默认收起（列表长），其余默认展开。
  bool _aboutOpen = false;
  String _appVersion = '';
  String _appBuild = '';
  late bool _periodsOpen = _collapseFlag('periods', false);
  late bool _basicOpen = _collapseFlag('basic', true);
  late bool _weatherOpen = _collapseFlag('weather', true);
  late bool _dataOpen = _collapseFlag('data', true);

  bool _collapseFlag(String key, bool dflt) {
    final ui = asMap(widget.store.settings().extra['ui']);
    final v = ui[key];
    return v is bool ? v : dflt;
  }

  void _toggleCollapse(String key) {
    setState(() {});
    _save((s) {
      final ui = Map<String, dynamic>.from(asMap(s.extra['ui']));
      ui[key] = openOf(key);
      s.extra['ui'] = ui;
    });
  }

  bool openOf(String key) {
    switch (key) {
      case 'basic':
        return _basicOpen;
      case 'weather':
        return _weatherOpen;
      case 'data':
        return _dataOpen;
      case 'periods':
        return _periodsOpen;
    }
    return true;
  }

  Widget _cardCollapsible(
    BuildContext context,
    String title, {
    Key? key,
    required String toggleKey,
    required bool open,
    required VoidCallback onToggle,
    String? summary,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key,
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
          InkWell(
            key: ValueKey(toggleKey),
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                if (!open && summary != null)
                  Text(summary,
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                const SizedBox(width: 6),
                // 收起时朝下、展开时朝上（和首页速览的小三角一个意思）
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more,
                      size: 20, color: cs.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (open) ...children,
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
    this.pickTime,
  });

  final Period period;
  final ValueChanged<Period> onChanged;
  final VoidCallback onRemove;

  /// 节次时间选择器（测试注入用）；不给就走系统时间选择对话框。
  final Future<TimeOfDay?> Function(TimeOfDay initial)? pickTime;

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
    // 旧数据里可能有手输时代的乱值（不是「时:分」格式），直接清掉显示占位提示，
    // 免得看起来像设好了时间其实没存对。先赋值再挂监听，避免清值触发落盘。
    _label.text = widget.period.label;
    _start.text = _cleanTime(widget.period.start);
    _end.text = _cleanTime(widget.period.end);
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

  /// 只认「时:分」格式，其它（手输时代的乱值）一律清空。
  static String _cleanTime(String v) =>
      RegExp(r'^\d{1,2}:\d{2}$').hasMatch(v.trim()) ? v.trim() : '';

  @override
  void dispose() {
    _label.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  /// Windows 风格的时间选择：两列滚轮（时 / 分）+ 确定 / 取消。
  Future<TimeOfDay?> _showWheelTimePicker(TimeOfDay initial) {
    var hour = initial.hour.clamp(0, 23);
    var minute = initial.minute.clamp(0, 59);
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: false, // 防止误点外面关掉导致白选
      builder: (ctx) => AlertDialog(
        title: const Text('选择时间'),
        content: SizedBox(
          height: 180,
          child: Row(
            children: <Widget>[
              Expanded(
                child: CupertinoPicker(
                  key: const ValueKey('wheel-hour'),
                  scrollController:
                      FixedExtentScrollController(initialItem: hour),
                  itemExtent: 40,
                  onSelectedItemChanged: (i) => hour = i,
                  children: <Widget>[
                    for (var h = 0; h < 24; h++)
                      Center(
                        child: Text(h.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 20)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  key: const ValueKey('wheel-minute'),
                  scrollController:
                      FixedExtentScrollController(initialItem: minute),
                  itemExtent: 40,
                  onSelectedItemChanged: (i) => minute = i,
                  children: <Widget>[
                    for (var m = 0; m < 60; m++)
                      Center(
                        child: Text(m.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 20)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('wheel-ok'),
            onPressed: () =>
                Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 点开始/结束时间框弹出时间选择器（不再手输，杜绝乱填中文）。
  Future<void> _pickTime(bool isStart) async {
    final current = (isStart ? _start.text : _end.text).trim();
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = widget.pickTime != null
        ? await widget.pickTime!(initial)
        : await _showWheelTimePicker(initial);
    if (picked == null) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isStart) {
        _start.text = text;
      } else {
        _end.text = text;
      }
    });
  }

  Widget _timeField(bool isStart) {
    final controller = isStart ? _start : _end;
    return TextField(
      key: ValueKey(
          's-period-${isStart ? 'start' : 'end'}-${widget.period.id}'),
      controller: controller,
      readOnly: true,
      showCursor: false,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14),
      onTap: () => _pickTime(isStart),
      decoration: InputDecoration(
        hintText: isStart ? '开始' : '结束',
        isDense: true,
        // 不放后缀图标、收紧内边距：时间是「08:10」五位字符，宽度必须留够，
        // 不然挤得什么都显示不出来（凯森 v1.3.2 反馈）
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('s-period-label-${widget.period.id}'),
              controller: _label,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: '节次名',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _timeField(true)),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _timeField(false)),
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
