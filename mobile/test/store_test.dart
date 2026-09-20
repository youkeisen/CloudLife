// 数据层（Store）的测试：四份 JSON 的读写、坏文件自愈、原子写。
// 测试用临时目录，不碰真机上的数据。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-phone-test-');
    store = Store(tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('初始化', () {
    test('init 会补齐四份文件', () {
      store.init();
      for (final name in Store.fileNames) {
        expect(store.fileFor(name).existsSync(), isTrue, reason: '$name.json 应该被建出来');
      }
    });

    test('重复 init 不覆盖已有数据', () {
      store.init();
      final s = store.settings()..displayName = '别覆盖我';
      store.saveSettings(s);
      store.init();
      expect(store.settings().displayName, '别覆盖我');
    });

    test('全新数据是空的（零预置）', () {
      store.init();
      final s = store.settings();
      expect(s.periods, isEmpty);
      expect(s.weatherCities, isEmpty);
      expect(s.weatherCity.isSet, isFalse);
      expect(store.courses().weeks, isEmpty);
      expect(store.notes().notes, isEmpty);
      expect(store.weatherCache().payload, isNull);
    });

    test('文件不存在时读会自动补一份默认的', () {
      final s = store.settings();
      expect(s.displayName, '');
      expect(store.fileFor('settings').existsSync(), isTrue);
    });
  });

  group('设置', () {
    test('存了能读回来', () {
      final s = store.settings()
        ..displayName = '小明'
        ..week1Monday = '2026-08-31'
        ..periods = <Period>[Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:55')];
      store.saveSettings(s);

      final back = store.settings();
      expect(back.displayName, '小明');
      expect(back.week1Monday, '2026-08-31');
      expect(back.periods.single.label, '第 1 节');
    });

    test('写出去的是人看得懂的 JSON（缩进 + 中文不转义）', () {
      final s = store.settings()..campus = '示例校区';
      store.saveSettings(s);
      final text = store.fileFor('settings').readAsStringSync();
      expect(text.contains('示例校区'), isTrue, reason: '中文不该被转义成 \\u');
      expect(text.contains('\n  '), isTrue, reason: '应该有缩进，方便人直接看');
    });
  });

  group('坏文件自愈', () {
    test('内容坏了就留副本、给警告、回落默认值', () {
      store.saveSettings(store.settings()..displayName = '原来的');
      store.fileFor('settings').writeAsStringSync('{"坏的');

      final back = store.settings();
      expect(back.displayName, '', reason: '坏了就回默认值');
      expect(store.warnings.length, 1);
      expect(store.warnings.single.file, 'settings.json');
      expect(store.warnings.single.brokenCopy.contains('.corrupt-'), isTrue);
      expect(store.warnings.single.message.contains('已恢复默认内容'), isTrue);

      final copies = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt-'))
          .toList();
      expect(copies.length, 1, reason: '坏文件要留一份，别直接删掉');
      expect(copies.single.readAsStringSync(), '{"坏的');
    });

    test('顶层不是对象也算坏', () {
      store.fileFor('notes').writeAsStringSync('[1,2,3]');
      expect(store.notes().notes, isEmpty);
      expect(store.warnings.single.file, 'notes.json');
    });

    test('空文件也算坏', () {
      store.fileFor('courses').writeAsStringSync('');
      expect(store.courses().weeks, isEmpty);
      expect(store.warnings, isNotEmpty);
    });

    test('警告可以清掉', () {
      store.fileFor('settings').writeAsStringSync('坏了');
      store.settings();
      expect(store.warnings, isNotEmpty);
      store.clearWarnings();
      expect(store.warnings, isEmpty);
    });

    test('一个文件坏了不影响其它文件', () {
      store.saveNotes(Notes(notes: <Note>[Note(id: 'n1', title: '还在')]));
      store.fileFor('settings').writeAsStringSync('坏了');
      store.settings();
      expect(store.notes().notes.single.title, '还在');
    });
  });

  group('原子写', () {
    test('写完不留 .tmp 残渣', () {
      store.saveSettings(store.settings()..displayName = 'x');
      final leftovers = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('连续写多次，最后一个是最后写的那份', () {
      for (var i = 1; i <= 5; i++) {
        store.saveSettings(store.settings()..displayName = '第 $i 次');
      }
      expect(store.settings().displayName, '第 5 次');
    });
  });

  group('课程', () {
    test('按周存取', () {
      store.saveWeek(3, <Lesson>[
        Lesson(id: 'c1', day: 1, slot: 'p1', name: '示例课程', location: 'A-101'),
      ]);
      expect(store.listWeek(3).single.name, '示例课程');
      expect(store.listWeek(4), isEmpty);
      expect(store.courses().usedWeeks, <int>[3]);
    });

    test('清空某一周（和电脑版一样留一个空数组）', () {
      store.saveWeek(2, <Lesson>[Lesson(id: 'c1', day: 1, slot: 'p1', name: 'x')]);
      store.saveWeek(2, <Lesson>[]);
      expect(store.listWeek(2), isEmpty);
      final weeks = store.courses().toJson()['weeks'] as Map;
      expect(weeks.containsKey('2'), isTrue);
    });

    test('两周互不干扰', () {
      store.saveWeek(1, <Lesson>[Lesson(id: 'a', day: 1, slot: 'p1', name: '第一周的课')]);
      store.saveWeek(2, <Lesson>[Lesson(id: 'b', day: 2, slot: 'p2', name: '第二周的课')]);
      expect(store.listWeek(1).single.name, '第一周的课');
      expect(store.listWeek(2).single.name, '第二周的课');
    });
  });

  group('备忘录', () {
    test('排序：置顶在前，然后按改动时间倒序', () {
      store.saveNotes(Notes(notes: <Note>[
        Note(id: 'a', title: '旧', updatedAt: '2026-09-01T10:00:00+08:00'),
        Note(id: 'b', title: '新', updatedAt: '2026-09-03T10:00:00+08:00'),
        Note(
          id: 'c',
          title: '置顶的旧',
          pinned: true,
          updatedAt: '2026-08-01T10:00:00+08:00',
        ),
      ]));
      expect(store.sortedNotes().map((n) => n.title).toList(), <String>['置顶的旧', '新', '旧']);
    });

    test('归档的不出现在默认列表里', () {
      store.saveNotes(Notes(notes: <Note>[
        Note(id: 'a', title: '正常的'),
        Note(id: 'b', title: '归档的', archived: true),
      ]));
      expect(store.sortedNotes().map((n) => n.title), <String>['正常的']);
      expect(store.sortedNotes(includeArchived: true).length, 2);
    });
  });

  group('天气缓存', () {
    test('写入时自动带时间戳，城市不含 timezone', () {
      final cache = store.setWeatherCache(
        City(name: '示例市', latitude: 30.0, longitude: 120.0),
        <String, dynamic>{'current': <String, dynamic>{'temp': 26.4}},
      );
      expect(cache.fetchedAt, isNotEmpty);
      expect(cache.payload!['current']['temp'], 26.4);

      final raw = jsonDecode(store.fileFor('weather_cache').readAsStringSync()) as Map;
      expect((raw['city'] as Map).keys.toSet(), <String>{'name', 'latitude', 'longitude'});
      expect(raw['city']['name'], '示例市');
    });
  });

  group('小工具', () {
    test('id 不重复', () {
      final ids = List<String>.generate(200, (_) => store.newId('c'));
      expect(ids.toSet().length, 200);
      expect(ids.first.startsWith('c'), isTrue);
    });

    test('时间戳格式带时区偏移', () {
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$')
            .hasMatch(Store.nowIso()),
        isTrue,
        reason: '和电脑版一样要带偏移，形如 2026-09-19T03:05:01+08:00',
      );
    });

    test('四份文件的默认值键名写全了', () {
      expect(Store.defaultsFor('settings').containsKey('weatherCities'), isTrue);
      expect(Store.defaultsFor('courses')['weeks'], isEmpty);
      expect(Store.defaultsFor('notes')['notes'], isEmpty);
      expect(Store.defaultsFor('weather_cache')['payload'], isNull);
      expect(() => Store.defaultsFor('不存在'), throwsArgumentError);
    });
  });

  group('记账数据（v1.7.0，需求文档第 3 条）', () {
    test('ledger 不在四份里，但默认值能取到', () {
      expect(Store.fileNames.contains('ledger'), isFalse,
          reason: '记账是手机版独有的，不能混进和电脑版对齐的四份里');
      expect(Store.ledgerFile, 'ledger');
      final d = Store.defaultsFor('ledger');
      expect(d['categories'], isEmpty);
      expect(d['records'], isEmpty);
    });

    test('没有 ledger.json 时读出来是空账本，不崩', () {
      store.init();
      expect(store.fileFor('ledger').existsSync(), isFalse);
      final l = store.ledger();
      expect(l.categories, isEmpty);
      expect(l.records, isEmpty);
      // 读一次会自动建出来（read 的行为），之后文件就在了
      expect(store.fileFor('ledger').existsSync(), isTrue);
    });

    test('存了再读，字段不丢', () {
      store.init();
      store.saveLedger(Ledger(
        categories: <LedgerCategory>[
          LedgerCategory(id: 'c1', name: '餐饮', icon: 'food', sort: 10),
        ],
        records: <LedgerRecord>[
          LedgerRecord(
            id: 'r1', amount: 32, categoryId: 'c1', date: '2026-09-20',
            note: '点点·二分奶茶', createdAt: '2026-09-20T12:00:00',
          ),
        ],
      ));
      final l = store.ledger();
      expect(l.categories.single.name, '餐饮');
      expect(l.categories.single.icon, 'food');
      expect(l.records.single.amount, 32);
      expect(l.records.single.note, '点点·二分奶茶');
      expect(l.records.single.date, '2026-09-20');
    });

    test('首次种默认分类；种过之后不再补（用户删光也不重生）', () {
      store.init();
      final first = store.ensureLedgerSeed();
      expect(first.categories, isNotEmpty);

      // 用户把分类全删了
      first.categories = <LedgerCategory>[];
      store.saveLedger(first);
      final second = store.ensureLedgerSeed();
      expect(second.categories, isEmpty,
          reason: '删光分类是用户的选择，不能又给他长回来');
    });

    test('种过标记写进了数据文件（重启也认）', () {
      store.init();
      store.ensureLedgerSeed();
      final raw = store.read('ledger');
      expect(raw['catsSeeded'], isTrue);
    });

    test('认不出的字段原样留着（跨版本不丢数据）', () {
      store.init();
      store.write('ledger', <String, dynamic>{
        'version': 1,
        'categories': <dynamic>[],
        'records': <dynamic>[],
        '将来才有的字段': '别丢',
      });
      final l = store.ledger();
      expect(l.extra['将来才有的字段'], '别丢');
      expect(l.toJson()['将来才有的字段'], '别丢');
    });

    test('坏记录被过滤掉，好记录还能读', () {
      store.init();
      store.write('ledger', <String, dynamic>{
        'version': 1,
        'categories': <dynamic>[
          <String, dynamic>{'id': 'c1', 'name': '餐饮', 'icon': 'food', 'sort': 0},
          <String, dynamic>{'name': '没有 id 的坏分类'},
        ],
        'records': <dynamic>[
          <String, dynamic>{
            'id': 'r1', 'amount': 10, 'categoryId': 'c1',
            'date': '2026-09-20', 'kind': 'expense',
          },
          <String, dynamic>{'amount': 20}, // 没 id，丢掉
        ],
      });
      final l = store.ledger();
      expect(l.categories, hasLength(1));
      expect(l.records, hasLength(1));
      expect(l.records.single.id, 'r1');
    });

    test('认不出的 kind 当支出处理（宁可少算收入也别多算）', () {
      store.init();
      store.write('ledger', <String, dynamic>{
        'version': 1,
        'categories': <dynamic>[],
        'records': <dynamic>[
          <String, dynamic>{
            'id': 'r1', 'amount': 10, 'categoryId': 'c1',
            'date': '2026-09-20', 'kind': '这是什么鬼',
          },
        ],
      });
      expect(store.ledger().records.single.isIncome, isFalse);
    });
  });
}
