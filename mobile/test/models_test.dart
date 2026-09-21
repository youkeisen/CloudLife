// 数据模型的测试：默认值必须为空、序列化必须往返无损、
// 而且认不出的字段不能吃掉（这是和电脑版备份互通的关键）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';

void main() {
  group('默认值（零预置原则）', () {
    test('全新的设置里一个字真东西都没有', () {
      final s = Settings.initial();
      expect(s.displayName, '');
      expect(s.semesterName, '');
      expect(s.week1Monday, '');
      expect(s.campus, '');
      expect(s.periods, isEmpty, reason: '节次必须空着，由用户自己建');
      expect(s.weatherCities, isEmpty, reason: '不许预置城市');
      expect(s.weatherCity.isSet, isFalse);
      expect(s.weekStartsOn, 1);
      // v1.6.0（需求文档第 7 条）：自动刷新选项去掉，固定 10 分钟
      expect(s.refreshMinutes, 10);
      // v1.6.0（需求文档第 1 条）：默认课前 15 分钟提醒
      expect(s.lessonRemindMinutes, 15);
      // v1.6.0（需求文档第 9 条）：默认用应用目录下的 backups/
      expect(s.backupDir, '');
      expect(s.theme, 'system');
    });

    test('设置 JSON 的键和电脑版一字不差', () {
      // 抄自电脑版 app/store.py 的 DEFAULT_SETTINGS。
      // v1.6.0 多了两个**手机版专属**字段：lessonRemindMinutes（上课前提醒）
      // 和 backupDir（自定义备份位置）。这两个不会进电脑版，电脑版读我们导出的
      // 备份时会把它们留在 extra 里原样保留，所以互通不受影响。
      final json = Settings.initial().toJson();
      expect(json.keys.toSet(), <String>{
        'version',
        'displayName',
        'semesterName',
        'week1Monday',
        'weekStartsOn',
        'campus',
        'periods',
        'weatherCity',
        'weatherCities',
        'refreshMinutes',
        'lessonRemindMinutes',
        'backupDir',
        'theme',
      });
      final city = json['weatherCity'] as Map;
      expect(city.keys.toSet(), <String>{'name', 'latitude', 'longitude', 'timezone'});
      expect(city['timezone'], 'Asia/Shanghai');
      expect(city['latitude'], isNull);
      expect(city['name'], '');
    });

    test('课程 / 备忘录 / 天气缓存的默认键', () {
      expect(Courses().toJson().keys.toSet(), <String>{'version', 'weeks'});
      expect(Notes().toJson().keys.toSet(), <String>{'version', 'notes'});
      final cache = WeatherCache().toJson();
      expect(cache.keys.toSet(), <String>{'version', 'fetchedAt', 'city', 'payload'});
      expect((cache['city'] as Map).keys.toSet(), <String>{'name', 'latitude', 'longitude'},
          reason: '缓存里的城市和电脑版一样不带 timezone');
      expect(cache['payload'], isNull);
    });
  });

  group('序列化往返', () {
    test('设置里的节次和地点能存能读', () {
      final s = Settings(
        displayName: '小明',
        week1Monday: '2026-08-31',
        weekStartsOn: 7,
        periods: <Period>[
          Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:55'),
          Period(id: 'p2', label: '中午1', start: '12:20', end: '13:05'),
        ],
        weatherCity: City(name: '示例市', latitude: 30.0, longitude: 120.0),
        weatherCities: <Place>[
          Place(id: 'pl1', name: '示例市', admin: '示例省', latitude: 30.0, longitude: 120.0),
        ],
      );
      final back = Settings.fromJson(s.toJson());
      expect(back.displayName, '小明');
      expect(back.week1Monday, '2026-08-31');
      expect(back.weekStartsOn, 7);
      expect(back.periods.length, 2);
      expect(back.periods[1].label, '中午1');
      expect(back.periods[0].start, '08:10');
      expect(back.weatherCity.name, '示例市');
      expect(back.weatherCity.latitude, 30.0);
      expect(back.weatherCities.single.admin, '示例省');
      expect(back.weatherCities.single.label, '示例市 · 示例省');
    });

    test('课程按周存取，周次键在 JSON 里是字符串', () {
      final c = Courses();
      c.setWeek(3, <Lesson>[
        Lesson(
          id: 'c1',
          day: 1,
          slot: 'p1',
          spanEnd: 'p2',
          name: '示例课程',
          location: 'A-101',
          teacher: '李老师',
        ),
      ]);
      final json = c.toJson();
      expect((json['weeks'] as Map).keys.toSet(), <String>{'3'});
      final back = Courses.fromJson(json);
      expect(back.week(3).single.name, '示例课程');
      expect(back.week(3).single.spanEnd, 'p2');
      expect(back.week(4), isEmpty);
      expect(back.usedWeeks, <int>[3]);
    });

    test('备忘录的清单项和标签', () {
      final n = Note(
        id: 'n1',
        title: '作业',
        type: NoteType.todo,
        items: <NoteItem>[
          NoteItem(text: '写作业', done: true),
          NoteItem(text: '交作业'),
        ],
        pinned: true,
      );
      final back = Note.fromJson(n.toJson());
      expect(back.isTodo, isTrue);
      expect(back.itemsTotal, 2);
      expect(back.itemsDone, 1);
      expect(back.pinned, isTrue);
      expect(back.archived, isFalse);
    });

    test('v1.9.0：读进带 tags 的旧数据，写出去就没有 tags 了', () {
      // 这条守的其实是个反直觉的点：known 里**必须留着 'tags' 这个名字**。
      // 因为 extraKeys 会把「不在 known 里」的键收进 extra 再原样写回去 ——
      // 把 'tags' 从 known 删掉，旧数据反而会被永久保留在文件里，清不掉。
      final n = Note.fromJson(<String, dynamic>{
        'id': 'n1',
        'title': '旧的',
        'tags': <String>['学习', '生活'],
        'createdAt': '2026-09-19T07:00:00+08:00',
      });
      expect(n.title, '旧的');
      expect(n.extra.containsKey('tags'), isFalse,
          reason: 'tags 不能被当成「认不出的字段」留下来');
      expect(n.toJson().containsKey('tags'), isFalse);
    });

    test('认不出的字段会被留下来——不会把另一边的字段吃掉', () {
      final json = <String, dynamic>{
        'version': 1,
        'displayName': '',
        'semesterName': '',
        'week1Monday': '',
        'weekStartsOn': 1,
        'campus': '',
        'periods': <dynamic>[],
        'weatherCity': <String, dynamic>{'name': '', 'latitude': null, 'longitude': null},
        'weatherCities': <dynamic>[],
        'refreshMinutes': 30,
        'theme': 'system',
        // 假设电脑版以后加了这些字段
        'futureField': '别弄丢我',
        'anotherOne': 42,
      };
      final back = Settings.fromJson(json).toJson();
      expect(back['futureField'], '别弄丢我');
      expect(back['anotherOne'], 42);
    });

    test('笔记里的清单项编号、lesson 的额外字段同样保留', () {
      final lesson = Lesson.fromJson(<String, dynamic>{
        'id': 'c1',
        'day': 1,
        'slot': 'p1',
        'futureColor': 'red',
      });
      expect(lesson.toJson()['futureColor'], 'red');
      expect(lesson.spanEnd, '');
      expect(lesson.name, '');

      final item = NoteItem.fromJson(<String, dynamic>{'text': 'a', 'done': true, 'x': 1});
      expect(item.toJson()['x'], 1);
    });

    test('字段类型不对时不崩，能给个合理默认', () {
      final s = Settings.fromJson(<String, dynamic>{
        'periods': 'not a list',
        'weekStartsOn': 'abc',
        'weatherCities': null,
        'refreshMinutes': '60',
      });
      expect(s.periods, isEmpty);
      expect(s.weekStartsOn, 1);
      expect(s.weatherCities, isEmpty);
      expect(s.refreshMinutes, 60, reason: '字符串数字也要认');
    });
  });

  group('备忘录摘要（列表第二行用）', () {
    test('清单型显示完成进度', () {
      final n = Note(
        id: 'n',
        type: NoteType.todo,
        items: <NoteItem>[
          NoteItem(text: 'a', done: true),
          NoteItem(text: 'b'),
        ],
      );
      expect(n.summary, '1/2 项完成');
    });

    test('空清单不硬凑文案', () {
      expect(Note(id: 'n', type: NoteType.todo).summary, '');
    });

    test('笔记型取正文第一行', () {
      expect(Note(id: 'n', body: '第一行\n第二行').summary, '第一行');
    });

    test('类型名字', () {
      expect(NoteType.label(NoteType.text), '笔记');
      expect(NoteType.label(NoteType.todo), '清单');
    });
  });

  // ---------- 提醒的重复方式（v1.8.2） ----------

  group('提醒重复方式（v1.8.2）', () {
    test('默认是单次', () {
      final n = Note(id: 'n');
      expect(n.remindRepeat, '');
      expect(n.remindDaily, isFalse);
    });

    test('每天能存能读', () {
      final n = Note(id: 'n', remindRepeat: Note.remindRepeatDaily);
      expect(n.remindDaily, isTrue);
      final back = Note.fromJson(jsonDecode(jsonEncode(n.toJson())));
      expect(back.remindRepeat, Note.remindRepeatDaily);
      expect(back.remindDaily, isTrue);
    });

    test('老数据没有这个键 → 当单次（不能改变原有行为）', () {
      final back = Note.fromJson(<String, dynamic>{'id': 'n', 'title': '旧的'});
      expect(back.remindRepeat, '');
      expect(back.remindDaily, isFalse);
    });

    test('认不出来的值一律当单次，不引入没实现的行为', () {
      final back = Note.fromJson(<String, dynamic>{
        'id': 'n',
        'remindRepeat': 'weekly', // 以后可能加，但现在没实现
      });
      expect(back.remindRepeat, '');
      expect(back.remindDaily, isFalse);
    });

    // ---------- v1.9.1：第三种方式「N 天后」 ----------

    test('「N 天后」能存能读，天数是数字', () {
      final n = Note(
          id: 'n', remindRepeat: Note.remindRepeatDays, remindDays: 3);
      expect(n.remindAfterDays, isTrue);
      expect(n.remindDaily, isFalse);
      final back = Note.fromJson(jsonDecode(jsonEncode(n.toJson())));
      expect(back.remindRepeat, Note.remindRepeatDays);
      expect(back.remindDays, 3);
      expect(back.remindAfterDays, isTrue);
    });

    test('天数默认 0；老数据没有这个键也不炸', () {
      expect(Note(id: 'n').remindDays, 0);
      final back = Note.fromJson(<String, dynamic>{'id': 'n'});
      expect(back.remindDays, 0);
    });

    test('copyWith 不能把提醒弄丢（v1.9.1 顺手修的雷）', () {
      // 原来 copyWith 没带 remindAt / remindRepeat，
      // 谁要是拿它「改个标题」，提醒会被静默清空。
      final n = Note(
        id: 'n',
        title: '旧标题',
        remindAt: '2026-09-21T08:00:00',
        remindRepeat: Note.remindRepeatDays,
        remindDays: 5,
      );
      final copy = n.copyWith(title: '新标题');
      expect(copy.title, '新标题');
      expect(copy.remindAt, '2026-09-21T08:00:00', reason: '提醒时间不能被 copyWith 吃掉');
      expect(copy.remindRepeat, Note.remindRepeatDays);
      expect(copy.remindDays, 5);
    });
  });

  group('地点与当前城市', () {
    test('地点转当前城市时不带 id/省份', () {
      final place = Place(
        id: 'pl1',
        name: '合肥',
        admin: '示例省',
        latitude: 31.86,
        longitude: 117.28,
      );
      final city = place.toCity().toJson();
      expect(city.keys.toSet(), <String>{'name', 'latitude', 'longitude', 'timezone'});
      expect(city['name'], '合肥');
    });

    test('坐标缺失时城市算「没设置」', () {
      expect(City(name: '示例市').isSet, isFalse);
      expect(City().isEmpty, isTrue);
      expect(City(name: '示例市', latitude: 31.1, longitude: 118.1).isSet, isTrue);
    });
  });
}
