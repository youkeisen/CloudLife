/// 设置页：基本 / 天气 / 作息与节次 / 数据（备份导出、还原、清空）。
///
/// 区块与文案对齐电脑版设置页（`app/static/index.html` 的 settings 区 +
/// `app.js` 的备份/还原/清空三个按钮）：
/// - 每一处改动立即落盘（数据文件就几 KB，同步写没有压力）；
/// - 还原前先自动给当前数据留一份备份；清空必须输入「清空」两个字；
/// - 外观改动通过 [SettingsPage.onChanged] 一路通知到 MaterialApp 重建。
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../backup.dart';
import '../changelog.dart' show kChangelog;
import '../lesson_reminder.dart';
import '../models.dart';
import '../notification_service.dart';
import '../reminder_scheduler.dart';
import '../store.dart';
import '../system_tweaks.dart';
import '../update_checker.dart';
import 'wheel_time_picker.dart';
import '../weather_api.dart';
import '../weather_logic.dart';
import '../week.dart';
import 'design.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    this.onChanged,
    this.pickZip,
    this.pickDir,
    this.api,
    this.pickTime,
    this.locate,
    this.checkUpdate,
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

  /// 选一个备份目录（v1.6.0）；返回 null 表示没选。测试注入假选择器。
  final Future<String?> Function()? pickDir;

  /// 测试时注入假天气接口；不传就用真的 Open-Meteo。
  final WeatherApi? api;

  /// 检查更新（测试注入用）：传入当前版本号，返回检查结论。
  /// 不给就走真的 GitHub Releases。
  final Future<UpdateCheckResult> Function(String currentVersion)? checkUpdate;

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
    // 电池优化状态查一次（v1.6.0，需求文档第 8 条）
    _checkBatteryOpt();
    // 通知权限也查一次（v1.7.4）——「到点不提醒」最常见的原因
    _checkNotifPerm();
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
  /// v1.6.0：改完顺手重排一次提醒——上课提醒的提前量存在设置里，
  /// 改了下拉就得让新值立刻排进系统闹钟，不然要等下次开 App 才生效。
  void _save(void Function(Settings) mutate) {
    mutate(_s);
    widget.store.saveSettings(_s);
    if (mounted) setState(() {}); // 让空态/开关状态跟着重画
    widget.onChanged?.call();
    rescheduleAllReminders(widget.store).catchError((_) {});
  }

  /// 还原/清空之后把整页状态重读一遍。
  void _reload() {
    setState(() => _s = widget.store.settings());
    widget.onChanged?.call();
  }

  // ---------- 备份 / 还原 / 清空 ----------

  Future<void> _doBackup() async {
    // v1.7.3：设过自定义位置、但权限后来被系统撤了（卸载重装/手动关掉）时，
    // 备份会直接失败。这里先查一次，没有就引导去开，别让用户吃一个天书报错。
    if (_s.backupDir.isNotEmpty &&
        (Platform.isAndroid || SystemTweaks.debugFakeAndroid)) {
      final ok = await _ensureStoragePermission();
      if (!ok) return;
    }
    try {
      final path = saveBackupFile(widget.store, buildBackupZip(widget.store),
          dirPath: _s.backupDir);
      _toast('已备份：${path.split('/').last.split('\\').last}');
    } on BackupException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('备份失败：$e');
    }
  }

  /// 选备份位置（v1.6.0，需求文档第 9 条；v1.7.3 加权限前置检查）。
  /// 安卓上 file_picker 的 getDirectoryPath 会弹系统目录选择框；
  /// 有些 ROM 不给选根目录，选不了就提示别处再试。
  ///
  /// **v1.7.3 的关键改动**：凯森 2026-09-20 反馈「位置设定不了」，
  /// 报 `PathAccessException: ... Operation not permitted`。根因是安卓 10+
  /// 分区存储，普通 File IO 写不进共享目录，**必须先拿到「所有文件访问」权限**。
  /// 所以现在流程是「**先查权限 → 没有就引导去开 → 开完再选目录**」，
  /// 而不是等用户选完了才告诉他写不进去。
  Future<void> _pickBackupDir() async {
    // 先查权限：测试注入 pickDir 时跳过（测试环境没有真实权限概念）
    final androidLike = Platform.isAndroid || SystemTweaks.debugFakeAndroid;
    if (widget.pickDir == null && androidLike) {
      final ok = await _ensureStoragePermission();
      if (!ok) return;
    }

    String? dir;
    try {
      dir = widget.pickDir != null
          ? await widget.pickDir!()
          : await FilePicker.platform.getDirectoryPath(
              dialogTitle: '选择备份位置');
    } catch (e) {
      _toast('选目录失败：$e');
      return;
    }
    if (dir == null || dir.trim().isEmpty) return;
    // v1.7.3：有些 ROM 的目录选择器会把中英文名叠起来返回
    // （比如 `/storage/emulated/0/下载/Download`），规整一下再存。
    dir = normalizeBackupDir(dir);
    // 再试写一下兜底：万一是别的应用私有目录之类，能选中但确实写不进去
    try {
      final probe = File(p.join(dir, '.cloudlife-write-test'));
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
    } catch (e) {
      _toast('这个位置写不进去，换一个（比如「下载」目录）：$e');
      return;
    }
    _save((s) => s.backupDir = dir!);
    _toast('备份位置已设为 $dir');
  }


  /// 确保拿到了「所有文件访问」权限。没有就弹框引导用户去系统设置开。
  /// 返回 true 表示最终有权限（可以继续选目录）。
  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid && !SystemTweaks.debugFakeAndroid) return true;
    if (await SystemTweaks.hasManageExternalStorage()) return true;
    if (!mounted) return false;

    // 解释清楚为什么需要这个权限——这是敏感权限，不说明白用户会不敢开
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('dlg-storage-permission'),
        title: const Text('需要「所有文件访问」权限'),
        content: const Text(
          '安卓 10 以后不允许应用直接往「下载」「文档」这类公共目录写文件，'
          '所以要先给它这个权限，才能把你选的位置当作备份目录。\n\n'
          '点「去开启」后会跳到系统设置页，找到 CloudLife，'
          '把「允许访问所有文件」打开，然后回到这里再点一次「选择」。',
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('dlg-storage-permission-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不用'),
          ),
          FilledButton(
            key: const ValueKey('dlg-storage-permission-go'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
    if (go != true) return false;

    try {
      await SystemTweaks.requestManageExternalStorage();
    } catch (_) {
      _toast('打不开系统设置，手动去：设置 → 应用 → CloudLife → 权限');
      return false;
    }
    // 用户可能刚开完回来，重查一次；没开好就再提示一遍
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final now = await SystemTweaks.hasManageExternalStorage();
    if (!now && mounted) {
      _toast('还没开启「所有文件访问」，开好后再点一次「选择」');
    }
    return now;
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
                style: Type.sm),
            const SizedBox(height: 8),
            Text('导出于 $fileName',
                style: Type.sm.copyWith(
                    color: Theme.of(ctx).colorScheme.outline)),
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
      safetyBackup(widget.store, dirPath: _s.backupDir); // 手滑也能找回来
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
                style: Type.sm),
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
      final name = safetyBackup(widget.store, dirPath: _s.backupDir);
      resetAllData(widget.store);
      _reload();
      _toast('已清空，备份文件：$name');
    } catch (e) {
      _toast('清空失败：$e');
    }
  }

  // ---------- 后台运行（v1.6.0，需求文档第 8 条） ----------

  /// 查通知权限 + 精确闹钟权限（v1.7.4）。
  ///
  /// 为什么必须把它显示出来：权限被拒之后，排进去的通知会被系统**静默丢掉**，
  /// App 侧完全无感。「到点没提醒」如果只看代码是查不出来的——
  /// 代码没错、通知也排了，就是系统不给弹。
  Future<void> _checkNotifPerm() async {
    if (!Platform.isAndroid && !SystemTweaks.debugFakeAndroid) return;
    try {
      final enabled = await NotificationService.notificationsEnabled();
      final exact = await NotificationService.exactAlarmsAllowed();
      if (mounted) {
        setState(() {
          _notifEnabled = enabled;
          _exactAlarmOk = exact;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _notifEnabled = null);
    }
  }

  /// 再申请一次通知权限；还是不行就带去系统设置。
  Future<void> _requestNotif() async {
    try {
      final ok = await NotificationService.requestPermissionAgain();
      if (ok) {
        await _checkNotifPerm();
        _toast('通知已开启');
        return;
      }
    } catch (_) {/* 落到下面的兜底 */}
    // 系统可能不再弹框（用户拒过两次），只能引导去设置页手动开
    try {
      await SystemTweaks.openAppSettings();
      _toast('去「通知」那一栏把「允许通知」打开');
    } catch (_) {
      _toast('打不开系统设置，手动去：设置 → 应用 → CloudLife → 通知');
    }
    await _checkNotifPerm();
  }

  /// 跳 ROM 的「自启动」管理页（v1.8.0）。
  ///
  /// 没有标准 Intent，各家 ROM 的页面都不一样，也没有 API 能查状态，
  /// 所以这里只负责把人送到页面上，不做「已开/未开」的判断——
  /// 判错了比不判更糟，用户会以为已经没问题了。
  Future<void> _openAutoStart() async {
    final opened = await SystemTweaks.openAutoStartSettings();
    if (!mounted) return;
    _toast(opened
        ? '找到 CloudLife，把「自启动」打开'
        : '这台手机没有专门的自启动页，已打开应用详情页');
  }

  /// 查系统里**实际排着的**通知条数（v1.7.5）。
  /// 用来验证「提醒到底排进去了没有」——排 0 条和排了但被压住，是两种病。
  Future<void> _checkPending() async {
    try {
      final list = await NotificationService.pendingRequests();
      // null = 非安卓/查不到，用 -1 表示，界面上说「查不到」而不是「一条都没有」
      if (mounted) setState(() => _pendingCount = list?.length ?? -1);
    } catch (_) {
      if (mounted) setState(() => _pendingCount = -1);
    }
  }

  /// 跳到系统的「闹钟与提醒」授权页，让用户允许精确闹钟。
  Future<void> _openExactAlarmSettings() async {
    try {
      await SystemTweaks.openExactAlarmSettings();
    } catch (_) {
      _toast('打不开系统设置，手动去：设置 → 应用 → CloudLife → 闹钟和提醒');
    }
    await _checkNotifPerm();
  }

  /// 查一下本应用是否已经在电池优化白名单里。
  Future<void> _checkBatteryOpt() async {
    if (!Platform.isAndroid) return;
    try {
      final ignored = await SystemTweaks.isBatteryOptimizationDisabled();
      if (mounted) setState(() => _batOptIgnored = ignored);
    } catch (_) {
      if (mounted) setState(() => _batOptIgnored = null);
    }
  }

  /// 跳到系统的「电池优化」页面让用户把本应用放行。
  /// 各家 ROM 这个页面不太一样，打不开就退而求其次开应用详情页。
  Future<void> _openBatterySettings() async {
    try {
      await SystemTweaks.requestIgnoreBatteryOptimizations();
    } catch (_) {
      try {
        await SystemTweaks.openAppSettings();
      } catch (e) {
        _toast('打不开系统设置，手动去：设置 → 应用 → CloudLife → 电池');
      }
    }
    // 用户可能刚放行，回来重查一次
    await _checkBatteryOpt();
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
    final week = weekOf(DateTime.now(), _s.week1Monday);
    return ListView(
      key: const ValueKey('page-settings'),
      // 底部留白：悬浮底栏是盖在内容上的，不留会被挡住（凯森 v1.3.5 反馈）
      padding: const EdgeInsets.only(bottom: Sp.bottomInset),
      children: <Widget>[
        PageHead(
          title: '设置',
          subtitle: _s.campus.isEmpty ? '数据只存在本机' : '${_s.campus} · 数据只存在本机',
          weekText: week == null ? '教学周未设置' : '第 $week 教学周',
          weekStrong: week != null,
          weekKey: week == null
              ? const ValueKey('week-pill-off')
              : const ValueKey('week-pill'),
        ),
        _profileCard(),
        const _GroupPad(child: GroupLabel(text: '通用')),
        _cardCollapsible(context, '基本',
            key: const ValueKey('s-basic-card'),
            toggleKey: 's-basic-toggle',
            open: _basicOpen,
            onToggle: () { _basicOpen = !_basicOpen; _toggleCollapse('basic'); },
            icon: Icons.tune,
            tint: Tone.of(context).primarySoft,
            tintColor: Tone.of(context).primary,
            children: <Widget>[
          _field('称呼', '填了之后首页的问候语会带上',
              TextFormField(
                key: const ValueKey('s-name'),
                initialValue: _s.displayName,
                decoration: const InputDecoration(hintText: '怎么称呼你'),
                onChanged: (v) => _save((s) => s.displayName = v),
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
          // v1.6.0（需求文档第 1 条）：上课前提醒，提前多久自己定。
          _field('上课提醒', '课前推一条通知到通知栏；改动后会自动重排',
              DropdownButtonFormField<int>(
                key: const ValueKey('s-lesson-remind'),
                initialValue: remindLeadChoices.contains(_s.lessonRemindMinutes)
                    ? _s.lessonRemindMinutes
                    : -1,
                isExpanded: true,
                items: <DropdownMenuItem<int>>[
                  for (final m in remindLeadChoices)
                    DropdownMenuItem<int>(value: m, child: Text(remindLeadLabel(m))),
                ],
                onChanged: (int? v) => v == null
                    ? null
                    : _save((s) => s.lessonRemindMinutes = v),
              )),
        ]),
        // v1.6.0（需求文档第 8 条）：让提醒在后台也能准时到。
        // 不加常驻通知（凯森选的），所以这里是「引导用户放行」而不是「强留进程」。
        _cardCollapsible(context, '后台运行与提醒',
            key: const ValueKey('s-bg-card'),
            toggleKey: 's-bg-toggle',
            open: _bgOpen,
            onToggle: () { _bgOpen = !_bgOpen; _toggleCollapse('bg'); },
            icon: Icons.notifications_none,
            tint: Tone.of(context).successSoft,
            tintColor: Tone.of(context).success,
            summary: _notifEnabled == false
                ? '通知被关了'
                : (_batOptIgnored == true ? '已放行' : null),
            children: <Widget>[
          // v1.7.4：通知权限排第一。这是「到时间不提醒」最常见的原因——
          // 权限被拒后系统直接丢掉通知，代码层面看不出任何异常。
          if (_notifEnabled == false)
            Container(
              key: const ValueKey('s-notif-warning'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: <Widget>[
                Icon(Icons.notifications_off_outlined,
                    size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '通知权限被关掉了，提醒到点也不会弹。'
                    '这是「设了提醒却没动静」最常见的原因。',
                    style: Type.sm.copyWith(color: cs.error),
                  ),
                ),
              ]),
            ),
          _dataLine(
            '通知权限',
            _notifEnabled == null
                ? '查询中…'
                : (_notifEnabled! ? '已开启，提醒能弹出来' : '被关掉了，提醒不会弹'),
            OutlinedButton(
              key: const ValueKey('btn-notif-perm'),
              onPressed: _notifEnabled == true ? null : _requestNotif,
              child: Text(_notifEnabled == true ? '已开启' : '去开启'),
            ),
          ),
          const Text(
              '提醒是交给系统的闹钟来响的，App 就算被清掉到点也会通知你。'
              '手机上做了下面这几件事，提醒会更准时：',
              style: Type.sm),
          const SizedBox(height: 10),
          _dataLine(
            '电池优化白名单',
            _batOptIgnored == null
                ? '查询中…'
                : (_batOptIgnored! ? '已放行，提醒不受省电限制' : '未放行，省电模式可能推迟通知'),
            OutlinedButton(
              key: const ValueKey('btn-battery-opt'),
              onPressed: _batOptIgnored == true ? null : _openBatterySettings,
              child: Text(_batOptIgnored == true ? '已放行' : '去设置'),
            ),
          ),
          // v1.7.4：精确闹钟。没开的话提醒会被系统攒着延后触发。
          _dataLine(
            '精确定时',
            _exactAlarmOk == null
                ? '查询中…'
                : (_exactAlarmOk!
                    ? '已允许，提醒准点响'
                    : '未允许，提醒可能晚几分钟（系统会攒着一起响）'),
            OutlinedButton(
              key: const ValueKey('btn-exact-alarm'),
              onPressed: _exactAlarmOk == true ? null : _openExactAlarmSettings,
              child: Text(_exactAlarmOk == true ? '已允许' : '去允许'),
            ),
          ),
          // v1.8.0：自启动。国产 ROM 独有的一层开关，关着的话
          // 手机重启后 App 起不来，开机补提醒就跑不了。
          _dataLine(
            '自启动',
            '关机重启后 App 能自己起来，把提醒重新排上。'
            '国产手机默认关着，不打开的话重启之后就不提醒了',
            OutlinedButton(
              key: const ValueKey('btn-auto-start'),
              onPressed: _openAutoStart,
              child: const Text('去设置'),
            ),
          ),
          // v1.7.5：自检——直接问系统「现在排着几条通知」。
          // 这是验证提醒有没有真的排进去最直接的办法：
          // 显示 0 条 = 排的环节有问题；有一堆 = 排成功了，是权限/拦截压住了。
          _dataLine(
            '已排提醒',
            _pendingCount == null
                ? '点右侧查一下'
                : (_pendingCount! < 0
                    ? '查不到（不影响使用）'
                    : (_pendingCount == 0
                        ? '系统里一条都没有 —— 提醒没排进去'
                        : '系统里有 $_pendingCount 条待提醒，到点会弹')),
            OutlinedButton(
              key: const ValueKey('btn-check-pending'),
              onPressed: _checkPending,
              child: const Text('检查'),
            ),
          ),
          // 查不到时把真实原因显示出来（v1.7.6）——
          // 只写「查不到」的话，出问题还得重新猜一遍
          if (_pendingCount != null &&
              _pendingCount! < 0 &&
              (NotificationService.lastPendingError ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                '原因：${NotificationService.lastPendingError}',
                key: const ValueKey('s-pending-error'),
                style: Type.xs.copyWith(color: cs.outline),
              ),
            ),
          if (Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                '上面的「自启动」不一定能跳对页面（各家手机藏的位置不一样）。'
                '没跳到的话手动去：设置 → 应用管理 → CloudLife → 自启动。',
                style: Type.xs.copyWith(color: cs.outline),
              ),
            ),
        ]),
        _cardCollapsible(context, '天气',            key: const ValueKey('s-weather-card'),
            toggleKey: 's-weather-toggle',
            open: _weatherOpen,
            onToggle: () { _weatherOpen = !_weatherOpen; _toggleCollapse('weather'); },
            icon: Icons.cloud_outlined,
            tint: Tone.of(context).accentSoft,
            tintColor: Tone.of(context).accent,
            summary: _s.weatherCities.isEmpty ? '还没设' : '${_s.weatherCities.length} 个地点',
            children: <Widget>[
          _rowTitle('我的地点', '选中即切换，右侧 × 移除'),
          if (_s.weatherCities.isEmpty)
            Text('还没有保存的地点',
                key: const ValueKey('s-places-empty'),
                style: Type.sm.copyWith(color: cs.outline))
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
                    style: Type.sm.copyWith(color: cs.error)),
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
                          child: Text(c.name, style: Type.body),
                        ),
                        if (c.admin.isNotEmpty)
                          Text(c.admin,
                              style: Type.xs.copyWith(color: cs.outline)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          // v1.6.0（需求文档第 7 条）：「自动刷新」下拉去掉了，固定 10 分钟刷新。
          // 数值仍然存在 settings.refreshMinutes 里（电脑版备份能对上），只是不给改。
          Row(
            key: const ValueKey('s-refresh-fixed'),
            children: <Widget>[
              Text('自动刷新', style: Type.sm.copyWith(color: cs.outline)),
              const Spacer(),
              Text('每 10 分钟',
                  style: Type.sm.copyWith(color: cs.outline)),
            ],
          ),
        ]),
        _cardCollapsible(context, '作息与节次（全部自定义）',
            key: const ValueKey('s-periods-card'),
            toggleKey: 's-periods-toggle',
            open: _periodsOpen,
          onToggle: () { _periodsOpen = !_periodsOpen; _toggleCollapse('periods'); },
          icon: Icons.schedule_outlined,
          tint: Tone.of(context).primarySoft,
          tintColor: Tone.of(context).primary,
          summary: _s.periods.isEmpty ? '还没设' : '${_s.periods.length} 个节次',
          children: <Widget>[
          if (_s.periods.isEmpty)
            Text('还没有节次，先添加几条吧',
                key: const ValueKey('s-periods-empty'),
                style: Type.sm.copyWith(color: cs.outline))
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
              style: Type.sm.copyWith(color: cs.outline)),
        ]),
        const _GroupPad(child: GroupLabel(text: '数据')),
        _cardCollapsible(context, '数据管理',
            key: const ValueKey('s-data-card'),
            toggleKey: 's-data-toggle',
            open: _dataOpen,
            onToggle: () { _dataOpen = !_dataOpen; _toggleCollapse('data'); },
            icon: Icons.storage_outlined,
            tint: Tone.of(context).ink100,
            tintColor: Tone.of(context).ink500,
            children: <Widget>[
          _dataLine(
            '备份位置',
            _s.backupDir.isEmpty ? '默认存在应用数据目录的 backups 里' : _s.backupDir,
            OutlinedButton(
              key: const ValueKey('btn-backup-dir'),
              onPressed: _pickBackupDir,
              child: Text(_s.backupDir.isEmpty ? '选择' : '更改'),
            ),
          ),
          if (_s.backupDir.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('btn-backup-dir-reset'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _save((s) => s.backupDir = ''),
                  child: const Text('恢复默认位置'),
                ),
              ),
            ),
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
        ]),
        _cardCollapsible(context, '关于',
            key: const ValueKey('s-about-card'),
            toggleKey: 's-about-toggle',
            open: _aboutOpen,
            onToggle: () { _aboutOpen = !_aboutOpen; _toggleCollapse('about'); },
            icon: Icons.info_outline,
            tint: Tone.of(context).ink100,
            tintColor: Tone.of(context).ink500,
            summary: _appVersion.isEmpty ? '' : 'v$_appVersion',
            children: <Widget>[
              Row(children: <Widget>[
                Text('CloudLife', style: Type.h3),
                const Spacer(),
                Text(
                  _appVersion.isEmpty
                      ? '版本号读取中…'
                      : 'v$_appVersion（构建 $_appBuild）',
                  style: Type.sm.copyWith(color: cs.outline),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                OutlinedButton.icon(
                  key: const ValueKey('btn-check-update'),
                  onPressed: _checkingUpdate ? null : _checkUpdate,
                  icon: const Icon(Icons.system_update_outlined, size: 18),
                  label: const Text('检查更新'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _updateStatus ?? '手动查一下是不是有了新版本',
                    key: const ValueKey('update-status'),
                    style: Type.sm.copyWith(color: cs.outline),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('更新日志', style: Type.h3),
              const SizedBox(height: 6),
              for (final entry in kChangelog) ...<Widget>[
                Text('v${entry.$1}',
                    style: Type.sm.copyWith(
                        fontWeight: FontWeight.w600, color: cs.primary)),
                for (final line in entry.$2)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 2),
                    child: Text('· $line',
                        style: Type.sm.copyWith(color: cs.outline)),
                  ),
                const SizedBox(height: 8),
              ],
        ]),
        // 危险操作与常规设置隔离，免得误触
        const _GroupPad(child: GroupLabel(text: '危险操作')),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, 0),
          child: GroupCard(
            children: <Widget>[
              SetRow(
                key: const ValueKey('btn-reset'),
                icon: Icons.delete_outline,
                tint: Tone.of(context).dangerSoft,
                tintColor: Tone.of(context).danger,
                title: '清除所有本地数据',
                subtitle: '不可撤销，会先自动备份',
                danger: true,
                onTap: _doReset,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Center(
            child: Text(
              'CloudLife${_appVersion.isEmpty ? '' : ' v$_appVersion'} · 数据存储于本机',
              style: Type.xs.copyWith(color: Tone.of(context).ink300),
            ),
          ),
        ),
      ],
    );
  }

  /// 卡片收放状态记在设置文件的 extra.ui 里，重进不丢（凯森 v1.3.7 反馈）。
  /// 作息与节次默认收起（列表长），其余默认展开。
  bool _aboutOpen = false;
  String _appVersion = '';
  String _appBuild = '';

  // ---------- 检查更新 ----------
  bool _checkingUpdate = false;
  String? _updateStatus;

  /// 设置 → 关于 → 检查更新：手动查一次 GitHub Release。
  /// 有新版本时弹更新窗（版本号 + 发布说明 + 下载入口）。
  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateStatus = '正在检查…';
    });
    final current = _appVersion.isEmpty ? '0.0.0' : _appVersion;
    final hook = widget.checkUpdate;
    final result = hook != null
        ? await hook(current)
        : await UpdateChecker().check(current);
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      switch (result.status) {
        case UpdateStatus.upToDate:
          _updateStatus = result.message ?? '已经是最新版本';
        case UpdateStatus.available:
          _updateStatus = '发现新版本 v${result.release!.version}';
        case UpdateStatus.error:
          _updateStatus = '检查失败：${result.message}';
      }
    });
    if (result.status == UpdateStatus.available && result.release != null) {
      _showUpdateDialog(result.release!);
    }
  }

  /// 有新版本就弹这个窗。
  void _showUpdateDialog(ReleaseInfo release) {
    final tone = Tone.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v${release.version}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('当前版本 v$_appVersion',
                    style: Type.sm.copyWith(color: tone.ink400)),
                const SizedBox(height: 8),
                Text(
                  release.notes.isEmpty ? '这次更新没有写说明。' : release.notes,
                  style: Type.body.copyWith(color: tone.ink700),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            key: const ValueKey('btn-download-update'),
            onPressed: () => _openUpdateUrl(ctx, release),
            child: Text(release.apkUrl.isEmpty ? '打开发布页' : '去下载'),
          ),
        ],
      ),
    );
  }

  /// 去下载：优先 apk 附件，没有就退到 release 页面。用系统浏览器开。
  Future<void> _openUpdateUrl(BuildContext dialogCtx, ReleaseInfo release) async {
    final url = release.apkUrl.isEmpty ? release.releaseUrl : release.apkUrl;
    Navigator.of(dialogCtx).pop();
    if (url.isEmpty) {
      _toast('没有拿到下载地址');
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      _toast('打不开浏览器：$e');
    }
  }

  /// 电池优化白名单状态（v1.6.0，需求文档第 8 条）：null = 还没查到。
  bool? _batOptIgnored;

  /// 通知权限状态（v1.7.4）：null = 还没查到。
  /// 「到时间不提醒」最常见的原因就是它——权限被拒后系统会静默丢掉通知。
  bool? _notifEnabled;

  /// 精确闹钟权限（v1.7.4）：非精确闹钟会被安卓延后触发。
  bool? _exactAlarmOk;

  /// 系统里实际排着的通知条数（v1.7.5）：null = 还没查，-1 = 查不到。
  int? _pendingCount;
  late bool _bgOpen = _collapseFlag('bg', false);
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
      case 'bg':
        return _bgOpen;
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
    IconData? icon,
    Color? tint,
    Color? tintColor,
    required List<Widget> children,
  }) {
    final tone = Tone.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, 0, Sp.gutter, Sp.s3),
      child: Card2(
        key: key,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 行头：图标 + 标题 +（收起时）右侧值 + 箭头
            InkWell(
              key: ValueKey(toggleKey),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      IconPlate(
                        icon: icon,
                        size: 32,
                        radius: 9,
                        iconSize: 17,
                        tint: tint,
                        tintColor: tintColor,
                      ),
                      const SizedBox(width: 11),
                    ],
                    Expanded(
                      child: Text(title, style: Type.h3.copyWith(color: tone.ink900)),
                    ),
                    if (!open && summary != null)
                      Text(summary, style: Type.sm.copyWith(color: tone.ink400)),
                    const SizedBox(width: 6),
                    // 收起时朝下、展开时朝上（和首页速览的小三角一个意思）
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.expand_more, size: 20, color: tone.ink300),
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...<Widget>[
              const SizedBox(height: 4),
              ...children,
            ],
          ],
        ),
      ),
    );
  }

  /// 账号卡：这一页的身份区（原设计完全没有）。称呼没填时给个占位。
  Widget _profileCard() {
    const c1 = Color(0xFF3D6BE5);
    const c2 = Color(0xFF1F3F9E);
    final name = _s.displayName.trim();
    final week = weekOf(DateTime.now(), _s.week1Monday);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s3 + 2, Sp.gutter, 0),
      child: Card2(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[c1, c2],
                ),
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Center(
                child: Text(
                  name.isEmpty ? '云' : name.substring(0, 1),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name.isEmpty ? '还没填称呼' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.h3.copyWith(color: context.tone.ink900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    <String>[
                      if (_s.campus.isNotEmpty) _s.campus,
                      week == null ? '教学周未设置' : '第 $week 教学周',
                      '数据存在本机',
                    ].join(' · '),
                    style: context.xs,
                  ),
                ],
              ),
            ),
          ],
        ),
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
                Text(label, style: Type.sm),
                if (desc != null)
                  Text(desc,
                      style: Type.xs.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
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
          Text(label, style: Type.sm),
          Text(desc,
              style: Type.xs.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
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
          Expanded(child: Text(p.label, style: Type.body)),
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
                Text(label, style: Type.sm),
                Text(desc,
                    style: Type.xs.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
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

/// 分组标题的统一外边距。
class _GroupPad extends StatelessWidget {
  const _GroupPad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s1, Sp.gutter, 0),
        child: child,
      );
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
        : await showWheelTimePicker(context, initial);
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
      style: Type.body,
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
              style: Type.body,
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
