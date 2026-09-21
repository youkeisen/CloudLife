/// 本地数据层：四份 JSON 的读写、原子写、坏文件自愈。
///
/// 数据结构与电脑版 `D:\App\MyDay\app\store.py` 一一对应，**文件名和字段名都不改**，
/// 这样电脑版导出的备份 zip 可以直接导进来（见 PRD 第 6 节）。
///
/// 用同步文件读写：数据都是几 KB 的小文件，同步写法更简单、也更好测；
/// 真机上这几毫秒的开销可以接受。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'ledger_icons.dart' show defaultLedgerCategories;
import 'models.dart';
import 'week.dart' show pad2;

/// 读文件时发现的问题（界面上要提示用户，别悄悄吞掉）。
class StoreWarning {
  StoreWarning({required this.file, required this.brokenCopy, required this.message});

  final String file;
  final String brokenCopy;
  final String message;
}

class Store {
  Store(this.dir);

  final Directory dir;
  final List<StoreWarning> _warnings = <StoreWarning>[];
  final Random _random = Random();

  /// 四份数据文件（顺序也照电脑版）。
  ///
  /// **记账（ledger）不在这里**：它是手机版独有的模块，电脑版没有。
  /// 备份时额外打进去（见 backup.dart），但电脑版还原时只看这四份、
  /// 会忽略多出来的 ledger.json，所以两边都不会炸。
  static const List<String> fileNames = <String>[
    'settings',
    'courses',
    'notes',
    'weather_cache',
  ];

  /// 记账数据文件名。单独列出来是因为它不进 `fileNames`（不参与
  /// 「四份必须齐」的校验），但备份/清空/读写都要照顾到它。
  static const String ledgerFile = 'ledger';

  List<StoreWarning> get warnings => List<StoreWarning>.unmodifiable(_warnings);
  void clearWarnings() => _warnings.clear();

  // ---------- 变更通知（v1.8.1） ----------
  //
  // 起因（凯森 2026-09-21）：在首页点开一条备忘录、删掉、返回，
  // 首页那张「备忘录速览」里**它还在**，得切走再切回来才消失。
  //
  // 根因：页面都是 build 时**实时读** store 的，数据永远是最新的；
  // 缺的是「数据变了 → 界面重新 build」这一环。首页的 State 一直在（没被销毁），
  // 所以只要没有人叫它 setState，它就一直显示旧内容。
  // 切 Tab 之所以看着「好了」，是因为 HomeShell 用 KeyedSubtree 带 label 做 key，
  // 切走再切回会把 State 整个重建一遍 —— 那是巧合，不是修好了。
  //
  // 监听挂在 [write] 上：它是所有落盘的**唯一总入口**，
  // 挂在那一处就覆盖了备忘录、课表、设置、记账、天气缓存所有保存路径，
  // 不用在每个 saveXxx 里各写一遍（那种写法早晚会漏一个）。
  final List<void Function()> _listeners = <void Function()>[];

  /// 数据变化时回调（界面用来 setState）。记得在 dispose 里 [removeListener]。
  void addListener(void Function() f) => _listeners.add(f);

  void removeListener(void Function() f) => _listeners.remove(f);

  bool _notifying = false;

  /// 通知所有监听者。**带防重入**：万一某个回调里又写了数据，
  /// 不加这个守卫就是无限递归。
  void _notifyChanged() {
    if (_notifying || _listeners.isEmpty) return;
    _notifying = true;
    try {
      // 复制一份再遍历：回调里可能增删监听
      for (final f in List<void Function()>.of(_listeners)) {
        f();
      }
    } finally {
      _notifying = false;
    }
  }

  /// 各文件的默认内容。**必须和电脑版 `DEFAULT_*` 一致**，
  /// 而且不能有任何真实个人信息（零预置原则）。
  static Map<String, dynamic> defaultsFor(String name) {
    switch (name) {
      case 'settings':
        return <String, dynamic>{
          'version': schemaVersion,
          'displayName': '',
          'semesterName': '',
          'week1Monday': '',
          'weekStartsOn': 1,
          'campus': '',
          'periods': <dynamic>[],
          'weatherCity': <String, dynamic>{
            'name': '',
            'latitude': null,
            'longitude': null,
            'timezone': defaultTimezone,
          },
          'weatherCities': <dynamic>[],
          // v1.6.0（需求文档第 7 条）：自动刷新选项从设置里去掉，固定 10 分钟
          'refreshMinutes': 10,
          // v1.6.0（需求文档第 1 条）：上课前多少分钟提醒；-1 = 不提醒
          'lessonRemindMinutes': 15,
          // v1.6.0（需求文档第 9 条）：自定义备份位置；空 = 默认 backups/
          'backupDir': '',
          'theme': 'system',
        };
      case 'courses':
        return <String, dynamic>{'version': schemaVersion, 'weeks': <String, dynamic>{}};
      case 'notes':
        return <String, dynamic>{'version': schemaVersion, 'notes': <dynamic>[]};
      case 'weather_cache':
        return <String, dynamic>{
          'version': schemaVersion,
          'fetchedAt': '',
          'city': <String, dynamic>{'name': '', 'latitude': null, 'longitude': null},
          'payload': null,
        };
      case 'ledger':
        // v1.7.0（需求文档第 3 条）：记账。分类留给首次打开时按默认表建，
        // 这里保持空——零预置原则，不塞任何跟凯森个人有关的东西。
        return <String, dynamic>{
          'version': schemaVersion,
          'categories': <dynamic>[],
          'records': <dynamic>[],
        };
      default:
        throw ArgumentError('未知的数据文件：$name');
    }
  }

  File fileFor(String name) => File(p.join(dir.path, '$name.json'));

  /// 建目录 + 缺哪份补哪份（首次启动就走这里）。
  void init() {
    dir.createSync(recursive: true);
    for (final name in fileNames) {
      if (!fileFor(name).existsSync()) {
        write(name, defaultsFor(name));
      }
    }
    dropLegacyNoteTags();
  }

  /// 把存量数据里的旧 `tags` 字段抹掉（v1.9.0 去掉标签功能）。
  ///
  /// 为什么非要在 init 里单独清一遍：模型已经不再解析 tags 了，
  /// 但**光靠「不解析」清不掉文件里的旧数据** ——
  /// 用户的笔记只要不被编辑过就不会重写，那些 tags 会一直躺在 notes.json 里。
  /// 凯森 2026-09-21 要求「数据一起清掉」，所以启动时扫一遍、有残留就重写。
  ///
  /// 「没有残留就不写」很重要：不然每次启动都写一次文件，
  /// 白白触发界面刷新，还磨损存储。
  void dropLegacyNoteTags() {
    final obj = read('notes');
    final list = obj['notes'];
    if (list is! List) return;
    var changed = false;
    for (final raw in list) {
      if (raw is Map && raw.containsKey('tags')) {
        raw.remove('tags');
        changed = true;
      }
    }
    if (changed) write('notes', obj);
  }

  /// 原子写：先写 `xxx.json.tmp`，成功后再改名覆盖。
  /// 中途断电/被杀，也只会留下一个 .tmp，不会把原文件写坏。
  void write(String name, Map<String, dynamic> data) {
    dir.createSync(recursive: true);
    final target = fileFor(name);
    final tmp = File('${target.path}.tmp');
    try {
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      tmp.renameSync(target.path);
      // 落盘成功才通知界面（写失败了别让界面误以为改好了）
      _notifyChanged();
    } catch (_) {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {/* 删不掉就算了 */}
      }
      rethrow;
    }
  }

  /// 读一份数据。文件不在就写一份默认的；内容坏了就改名留存 + 回落默认值。
  Map<String, dynamic> read(String name) {
    final f = fileFor(name);
    if (!f.existsSync()) {
      final fresh = defaultsFor(name);
      write(name, fresh);
      return fresh;
    }
    final text = f.readAsStringSync();
    Object? failure;
    try {
      final obj = jsonDecode(text);
      if (obj is Map) {
        return obj.map((k, v) => MapEntry(k.toString(), v));
      }
      failure = '顶层不是对象';
    } catch (e) {
      failure = e;
    }
    // 到这里说明文件坏了
    final now = DateTime.now();
    final stamp = '${now.year}${pad2(now.month)}${pad2(now.day)}-'
        '${pad2(now.hour)}${pad2(now.minute)}${pad2(now.second)}';
    final broken = File('${f.path}.corrupt-$stamp');
    try {
      f.renameSync(broken.path);
    } catch (_) {/* 改不了名也要继续 */}
    _warnings.add(StoreWarning(
      file: '$name.json',
      brokenCopy: p.basename(broken.path),
      message: '数据文件损坏，已恢复默认内容：$name.json（$failure）',
    ));
    final fresh = defaultsFor(name);
    write(name, fresh);
    return fresh;
  }

  // ---------- 设置 ----------
  Settings settings() => Settings.fromJson(read('settings'));

  void saveSettings(Settings s) => write('settings', s.toJson());

  // ---------- 课程 ----------
  Courses courses() => Courses.fromJson(read('courses'));

  void saveCourses(Courses c) => write('courses', c.toJson());

  List<Lesson> listWeek(int week) => courses().week(week);

  void saveWeek(int week, List<Lesson> lessons) {
    final c = courses();
    c.setWeek(week, lessons);
    saveCourses(c);
  }

  // ---------- 备忘录 ----------
  Notes notes() => Notes.fromJson(read('notes'));

  void saveNotes(Notes n) => write('notes', n.toJson());

  /// 置顶在前、改过的在前（和电脑版列表顺序一致）。
  List<Note> sortedNotes({bool includeArchived = false}) {
    final list = notes()
        .notes
        .where((n) => includeArchived || !n.archived)
        .toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  // ---------- 记账（v1.7.0，需求文档第 3 条） ----------

  Ledger ledger() => Ledger.fromJson(read(ledgerFile));

  void saveLedger(Ledger l) => write(ledgerFile, l.toJson());

  /// 首次打开记账时按默认表把分类建好（只建一次——建过就不再动，
  /// 用户删掉的分类不会被「补回来」）。
  ///
  /// 判断依据是文件里有没有 categories 这个键被显式写过，而不是「列表空」：
  /// 用户完全可能把分类删光，那时不该又冒出默认分类。
  Ledger ensureLedgerSeed() {
    final obj = read(ledgerFile);
    final hasSeed =
        (obj['catsSeeded'] as dynamic) == true || (obj['catsSeeded'] as dynamic) == 1;
    final l = Ledger.fromJson(obj);
    if (hasSeed) return l;
    l.categories = defaultLedgerCategories();
    // 标记已种过。用 extra 背着这个标记，Ledger.fromJson/toJson 会原样带着它。
    l.extra['catsSeeded'] = true;
    saveLedger(l);
    return l;
  }

  // ---------- 天气缓存 ----------
  WeatherCache weatherCache() => WeatherCache.fromJson(read('weather_cache'));

  WeatherCache setWeatherCache(City city, Map<String, dynamic>? payload) {
    final obj = <String, dynamic>{
      'version': schemaVersion,
      'fetchedAt': nowIso(),
      'city': <String, dynamic>{
        'name': city.name,
        'latitude': city.latitude,
        'longitude': city.longitude,
      },
      'payload': payload,
    };
    write('weather_cache', obj);
    return WeatherCache.fromJson(obj);
  }

  // ---------- 小工具 ----------
  static int _counter = 0;

  /// id 形如 `c20260919030501_1_ab12cd34`（和电脑版同款，够用就行）。
  String newId(String prefix) {
    final n = DateTime.now();
    final stamp = '${n.year}${pad2(n.month)}${pad2(n.day)}'
        '${pad2(n.hour)}${pad2(n.minute)}${pad2(n.second)}';
    _counter++;
    final rnd = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$prefix${stamp}_${_counter}_$rnd';
  }

  /// 带时区偏移的本地时间，形如 `2026-09-19T03:05:01+08:00`（和电脑版一致）。
  static String nowIso() => isoOf(DateTime.now());

  /// 同 [nowIso]，但可以指定时刻（备份 manifest 等地方用）。
  static String isoOf(DateTime n) {
    final off = n.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final hh = pad2(off.inHours.abs());
    final mm = pad2(off.inMinutes.abs() % 60);
    return '${n.year}-${pad2(n.month)}-${pad2(n.day)}T'
        '${pad2(n.hour)}:${pad2(n.minute)}:${pad2(n.second)}$sign$hh:$mm';
  }
}
