// 备份模块的测试：zip 结构、manifest、校验文案、还原原子性。
// 全部用临时目录 + 虚构数据，不碰真网、不碰真实个人信息。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/backup.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-backup-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 给数据目录塞一点虚构内容，方便验证打包/还原。
  void seedData() {
    final s = store.settings()
      ..displayName = '测试用户'
      ..semesterName = '测试学期'
      ..week1Monday = '2026-08-31';
    store.saveSettings(s);

    final lesson = Lesson(
      id: 'c1',
      day: 1,
      slot: '1',
      spanEnd: '2',
      name: '测试课程',
      location: '测试楼 101',
    );
    store.saveCourses(Courses(weeks: {1: [lesson], 3: []}));

    store.saveNotes(Notes(notes: [
      Note(id: 'n1', title: '测试备忘录', body: '正文第一行'),
    ]));

    store.setWeatherCache(City(name: '示例市', latitude: 31.1, longitude: 118.1),
        <String, dynamic>{'city': <String, dynamic>{}, 'tips': <String>[]});
  }

  group('文件名与 manifest', () {
    test('zip 名是 MyDay-backup-YYYYMMDD-HHMM.zip', () {
      final n = DateTime(2026, 9, 19, 8, 5);
      expect(backupZipName(n), 'MyDay-backup-20260919-0805.zip');
    });

    test('manifest 字段齐全且 files 顺序照电脑版', () {
      final m = buildManifest(DateTime(2026, 9, 19, 11, 16, 2));
      expect(m['app'], 'MyDay');
      expect(m['version'], 1);
      expect(m['exportedAt'], isA<String>());
      expect(m['files'], backupDataFiles);
      expect(backupDataFiles,
          <String>['settings.json', 'courses.json', 'notes.json', 'weather_cache.json']);
    });

    test('exportedAt 带本地时区偏移', () {
      final m = buildManifest(DateTime(2026, 9, 19, 11, 16, 2));
      expect(m['exportedAt'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$')));
    });
  });

  group('打包', () {
    test('zip 里有 manifest + 四份数据，内容能解出来', () {
      seedData();
      final raw = buildBackupZip(store);
      final archive = ZipDecoder().decodeBytes(raw);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, <String>{'manifest.json', ...backupDataFiles});

      final manifest =
          jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content as List<int>))
              as Map<String, dynamic>;
      expect(manifest['app'], 'MyDay');

      final settings =
          jsonDecode(utf8.decode(archive.findFile('settings.json')!.content as List<int>))
              as Map<String, dynamic>;
      expect(settings['displayName'], '测试用户');

      final courses =
          jsonDecode(utf8.decode(archive.findFile('courses.json')!.content as List<int>))
              as Map<String, dynamic>;
      expect((courses['weeks'] as Map)['1'], isA<List<dynamic>>());
    });

    test('数据文件缺失时按电脑版写 {} 占位', () {
      File(store.fileFor('notes').path).deleteSync();
      final archive = ZipDecoder().decodeBytes(buildBackupZip(store));
      final notes = utf8.decode(archive.findFile('notes.json')!.content as List<int>);
      expect(notes, '{}');
    });

    test('saveBackupFile 落到 backups/ 目录，文件名能对上', () {
      final path = saveBackupFile(store, buildBackupZip(store),
          now: DateTime(2026, 9, 19, 12, 34));
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), greaterThan(0));
      expect(path.contains('backups'), isTrue);
      expect(path.endsWith('MyDay-backup-20260919-1234.zip'), isTrue);
    });
  });

  group('校验（文案与电脑版一致）', () {
    test('合法备份能过校验并拿到 manifest', () {
      final manifest = inspectBackup(buildBackupZip(store));
      expect(manifest['app'], 'MyDay');
    });

    test('不是 zip → 不是有效的备份文件', () {
      expect(() => inspectBackup(<int>[1, 2, 3, 4]),
          throwsA(isA<BackupException>().having((e) => e.message, 'msg', contains('不是有效的备份文件'))));
    });

    test('缺 manifest → 备份文件缺少 manifest.json', () {
      final archive = Archive();
      final bytes = utf8.encode('{}');
      archive.addFile(ArchiveFile('settings.json', bytes.length, bytes));
      final raw = ZipEncoder().encode(archive)!;
      expect(() => inspectBackup(raw),
          throwsA(isA<BackupException>().having((e) => e.message, 'msg', '备份文件缺少 manifest.json')));
    });

    test('manifest 坏了 → manifest 读不出来', () {
      final archive = Archive();
      final bad = utf8.encode('not json');
      archive.addFile(ArchiveFile('manifest.json', bad.length, bad));
      final raw = ZipEncoder().encode(archive)!;
      expect(() => inspectBackup(raw),
          throwsA(isA<BackupException>().having((e) => e.message, 'msg', contains('manifest 读不出来'))));
    });

    test('缺数据文件 → 备份缺少数据文件（顿号连接）', () {
      final archive = Archive();
      final bytes = utf8.encode('{}');
      archive.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
      archive.addFile(ArchiveFile('settings.json', bytes.length, bytes));
      final raw = ZipEncoder().encode(archive)!;
      expect(
          () => inspectBackup(raw),
          throwsA(isA<BackupException>().having((e) => e.message, 'msg',
              '备份缺少数据文件：courses.json、notes.json、weather_cache.json')));
    });
  });

  group('还原与清空', () {
    test('还原覆盖四份数据，返回值键名与电脑版一致', () {
      seedData();
      final raw = buildBackupZip(store);

      // 换一个目录里的新数据，再还原旧备份
      final tmp2 = Directory.systemTemp.createTempSync('myday-backup-restore-');
      addTearDown(() {
        if (tmp2.existsSync()) tmp2.deleteSync(recursive: true);
      });
      final store2 = Store(tmp2)..init();

      final info = restoreBackup(store2, raw);
      expect(info['restored'], backupDataFiles);
      expect(info['exportedAt'], isA<String>());

      final s = store2.settings();
      expect(s.displayName, '测试用户');
      expect(s.week1Monday, '2026-08-31');
      final c = store2.courses();
      expect(c.week(1).first.name, '测试课程');
      expect(c.week(3), isEmpty); // 空周也回来了
      final n = store2.notes();
      expect(n.notes.first.title, '测试备忘录');
      expect(store2.weatherCache().city.name, '示例市');
    });

    test('数据文件不是 JSON 对象时拒绝还原，且不做半套修改', () {
      seedData();
      // 造一份 notes.json 内容是数组的坏备份
      final archive = Archive();
      void add(String name, Object obj) {
        final bytes = utf8.encode(jsonEncode(obj));
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add('manifest.json', buildManifest(DateTime(2026, 9, 19)));
      add('settings.json', <String, dynamic>{});
      add('courses.json', <String, dynamic>{});
      add('notes.json', <dynamic>[1, 2, 3]);
      add('weather_cache.json', <String, dynamic>{});
      final raw = ZipEncoder().encode(archive)!;

      expect(
          () => restoreBackup(store, raw),
          throwsA(isA<BackupException>()
              .having((e) => e.message, 'msg', 'notes.json 内容不是 JSON 对象')));
      // 半套修改不可能发生：settings 里的内容原封不动
      expect(store.settings().displayName, '测试用户');
    });

    test('safetyBackup 返回文件名且真的落了盘', () {
      seedData();
      final name = safetyBackup(store, now: DateTime(2026, 9, 19, 23, 59));
      expect(name, 'MyDay-backup-20260919-2359.zip');
      expect(File('${tmp.path}/backups/$name').existsSync(), isTrue);
    });

    test('还原的 zip 里存的正是 safetyBackup 打的包（往返一致）', () {
      seedData();
      final name = safetyBackup(store, now: DateTime(2026, 9, 19, 12, 0));
      final raw = File('${tmp.path}/backups/$name').readAsBytesSync();
      final s = store.settings()..displayName = '';
      store.saveSettings(s);
      restoreBackup(store, raw);
      expect(store.settings().displayName, '测试用户');
    });

    test('resetAllData 四份文件回到默认', () {
      seedData();
      resetAllData(store);
      expect(store.settings().displayName, '');
      expect(store.settings().periods, isEmpty);
      expect(store.courses().weeks, isEmpty);
      expect(store.notes().notes, isEmpty);
      expect(store.weatherCache().payload, isNull);
      expect(store.weatherCache().fetchedAt, '');
    });
  });

  group('与电脑版备份互通', () {
    test('按电脑版 backup.py 的布局手工拼的 zip 能直接还原', () {
      // 模拟电脑版：同样的五个条目名、manifest 结构、UTF-8 JSON
      final archive = Archive();
      void add(String name, Object obj) {
        final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(obj));
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add('manifest.json', <String, dynamic>{
        'app': 'MyDay',
        'version': 1,
        'exportedAt': '2026-09-18T22:00:00+08:00',
        'files': backupDataFiles,
      });
      add('settings.json', <String, dynamic>{
        'version': 1,
        'displayName': '电脑端称呼',
        'week1Monday': '2026-08-31',
        'weekStartsOn': 1,
      });
      add('courses.json', <String, dynamic>{
        'version': 1,
        'weeks': <String, dynamic>{
          '2': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'c9', 'day': 2, 'slot': '3', 'spanEnd': '4', 'name': '电脑端课程'},
          ],
        },
      });
      add('notes.json', <String, dynamic>{
        'version': 1,
        'notes': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'n9', 'title': '电脑端备忘录', 'type': 'text'},
        ],
      });
      add('weather_cache.json', <String, dynamic>{
        'version': 1,
        'fetchedAt': '2026-09-18T22:00:00+08:00',
        'city': <String, dynamic>{'name': '甲城', 'latitude': 30.5, 'longitude': 117.0},
        'payload': null,
      });
      final raw = ZipEncoder().encode(archive)!;

      final info = restoreBackup(store, raw);
      expect(info['exportedAt'], '2026-09-18T22:00:00+08:00');
      expect(store.settings().displayName, '电脑端称呼');
      expect(store.courses().week(2).first.name, '电脑端课程');
      expect(store.notes().notes.first.title, '电脑端备忘录');
      expect(store.weatherCache().city.name, '甲城');
      // 电脑版 settings 里没写的字段回落默认值，不炸。
      // v1.6.0：刷新间隔默认改成 10 分钟（需求文档第 7 条）
      expect(store.settings().refreshMinutes, 10);
    });
  });

  group('记账（v1.7.0，需求文档第 3 条）', () {
    /// 造一份「有账本」的本机数据。
    void seedLedger() {
      store.saveLedger(Ledger(
        categories: <LedgerCategory>[
          LedgerCategory(id: 'c1', name: '餐饮', icon: 'food', sort: 0),
        ],
        records: <LedgerRecord>[
          LedgerRecord(
            id: 'r1', amount: 32, categoryId: 'c1', date: '2026-09-20',
            note: '奶茶', createdAt: '2026-09-20T12:00:00',
          ),
        ],
      ));
    }

    test('备份 zip 里有 ledger.json', () {
      seedLedger();
      final raw = buildBackupZip(store);
      final archive = ZipDecoder().decodeBytes(raw);
      expect(archive.files.any((f) => f.name == 'ledger.json'), isTrue);
    });

    test('没有账本时备份里就不带 ledger.json（不写 {} 占位）', () {
      // 关键：写了 {} 占位的话，还原那台机器上的账本会被清空。
      // 先把可能被 read 自动建出来的文件删掉
      final f = store.fileFor('ledger');
      if (f.existsSync()) f.deleteSync();
      final raw = buildBackupZip(store);
      final archive = ZipDecoder().decodeBytes(raw);
      expect(archive.files.any((f) => f.name == 'ledger.json'), isFalse,
          reason: '不能写占位，否则会清空别人的账本');
    });

    test('备份里带账本 → 还原后账本还在', () {
      seedLedger();
      final raw = buildBackupZip(store);
      // 清掉账本再还原
      store.write('ledger', Store.defaultsFor('ledger'));
      expect(store.ledger().records, isEmpty);

      restoreBackup(store, raw);
      expect(store.ledger().records.single.note, '奶茶');
      expect(store.ledger().categories.single.name, '餐饮');
    });

    test('导电脑版备份（没有 ledger.json）→ 本机账本保持不动', () {
      seedLedger();
      // 造一份电脑版风格的备份：只有四份，没有 ledger
      final archive = Archive();
      void add(String name, Map<String, dynamic> obj) {
        final b = utf8.encode(jsonEncode(obj));
        archive.addFile(ArchiveFile(name, b.length, b));
      }

      add(backupManifestName, <String, dynamic>{
        'app': 'MyDay', 'version': 1,
        'exportedAt': '2026-09-18T22:00:00+08:00',
        'files': List<String>.from(backupDataFiles),
      });
      add('settings.json', Store.defaultsFor('settings'));
      add('courses.json', Store.defaultsFor('courses'));
      add('notes.json', Store.defaultsFor('notes'));
      add('weather_cache.json', Store.defaultsFor('weather_cache'));

      restoreBackup(store, ZipEncoder().encode(archive)!);
      expect(store.ledger().records.single.note, '奶茶',
          reason: '电脑版备份里没有账本，不该把本机账本清掉');
    });

    test('清空数据会把账本一起清掉', () {
      seedLedger();
      expect(store.ledger().records, isNotEmpty);
      store.clearWarnings();
      resetAllData(store);
      expect(store.ledger().records, isEmpty);
      expect(store.ledger().categories, isEmpty);
    });
  });

  // v1.7.3：凯森 2026-09-20 反馈「位置设定不了」，
  // 报错路径 `/storage/emulated/0/下载/Download` 里中英文名叠了层。
  group('备份目录规整（v1.7.3）', () {
    test('中英文叠层：/下载/Download 收成 /下载', () {
      expect(normalizeBackupDir('/storage/emulated/0/下载/Download'),
          '/storage/emulated/0/下载');
      expect(normalizeBackupDir('/storage/emulated/0/文档/Documents'),
          '/storage/emulated/0/文档');
      expect(normalizeBackupDir('/storage/emulated/0/图片/Pictures'),
          '/storage/emulated/0/图片');
    });

    test('没叠层的路径原样返回（不去瞎猜）', () {
      expect(normalizeBackupDir('/storage/emulated/0/Download'),
          '/storage/emulated/0/Download');
      expect(normalizeBackupDir('/storage/emulated/0/下载'),
          '/storage/emulated/0/下载');
      expect(normalizeBackupDir('/sdcard/MyFolder'), '/sdcard/MyFolder');
    });

    test('中文名在中间但结尾不是英文名，不动它', () {
      expect(normalizeBackupDir('/storage/emulated/0/下载/我的备份'),
          '/storage/emulated/0/下载/我的备份');
    });

    test('去掉结尾多余斜杠', () {
      expect(normalizeBackupDir('/storage/emulated/0/下载///'),
          '/storage/emulated/0/下载');
      expect(normalizeBackupDir('/storage/emulated/0/下载/Download/'),
          '/storage/emulated/0/下载');
    });

    test('Windows 盘符路径原样不动（不去统一斜杠体裁）', () {
      expect(normalizeBackupDir(r'C:\Users\me\Documents'),
          r'C:\Users\me\Documents');
      expect(normalizeBackupDir(r'C:\Users\me\下载'),
          r'C:\Users\me\下载');
    });

    test('反斜杠的叠层也收（Windows 风格）', () {
      expect(normalizeBackupDir(r'D:\下载\Download'), r'D:\下载');
    });
  });
}
