// 上课提醒的纯逻辑测试（v1.6.0，需求文档第 1 条）：
// 「给课程开始前添加提醒功能，提前多久提醒自定义」。
//
// 数据全部虚构；时间用固定的基准时刻，不依赖跑测试时的真实日期。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/lesson_reminder.dart';
import 'package:my_day_phone/models.dart';

void main() {
  /// 造一份「第 1 周周一 = 2026-09-07」的设置，三节课：
  /// 周一 第1节 08:10 高数（1#102）；周一 第3节 10:10 英语；周三 第1节 08:10 体育。
  Settings makeSettings({int lead = 15}) {
    final s = Settings.initial()
      ..week1Monday = '2026-09-07'
      ..lessonRemindMinutes = lead
      ..periods = <Period>[
        Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:55'),
        Period(id: 'p2', label: '第 2 节', start: '09:05', end: '09:50'),
        Period(id: 'p3', label: '第 3 节', start: '10:10', end: '10:55'),
      ];
    return s;
  }

  Courses makeCourses() => Courses(weeks: <int, List<Lesson>>{
        1: <Lesson>[
          Lesson(
              id: 'l1',
              day: 1,
              slot: 'p1',
              name: '高等数学',
              location: '1#102'),
          Lesson(id: 'l2', day: 1, slot: 'p3', name: '英语'),
          Lesson(id: 'l3', day: 3, slot: 'p1', name: '体育'),
        ],
      });

  // 2026-09-07 是周一，08:00（比第一节课早 10 分钟）
  final DateTime base = DateTime(2026, 9, 7, 8, 0);

  test('提前量标签文案', () {
    expect(remindLeadLabel(-1), '不提醒');
    expect(remindLeadLabel(0), '上课时提醒');
    expect(remindLeadLabel(15), '提前 15 分钟');
    expect(remindLeadLabel(60), '提前 1 小时');
  });

  test('默认提前 15 分钟：算出当天后面两节课的提醒时间', () {
    final list = lessonReminders(
      settings: makeSettings(),
      courses: makeCourses(),
      from: base,
      days: 7,
    );
    // 8:00 这个时刻：08:10 的那节课（提前 15 分钟 → 07:55）已经过了，
    // 10:10 的英语（→09:55）还在，周三的体育（09-09 07:55）也在。
    final titles = list.map((r) => r.title).toList();
    expect(titles.any((t) => t.contains('英语')), isTrue);
    expect(titles.any((t) => t.contains('体育')), isTrue);
    expect(titles.any((t) => t.contains('高等数学')), isFalse,
        reason: '07:55 已经过去，不该再排');

    final english = list.firstWhere((r) => r.title.contains('英语'));
    expect(english.when, DateTime(2026, 9, 7, 9, 55));
    final sport = list.firstWhere((r) => r.title.contains('体育'));
    expect(sport.when, DateTime(2026, 9, 9, 7, 55));
  });

  test('提醒按时间升序', () {
    final list = lessonReminders(
      settings: makeSettings(),
      courses: makeCourses(),
      from: base,
      days: 7,
    );
    for (var i = 1; i < list.length; i++) {
      expect(list[i].when.isBefore(list[i - 1].when), isFalse,
          reason: '第 $i 条应该不早于前一条');
    }
  });

  test('提前量自定义：提前 60 分钟时第一节课也排得进去', () {
    final list = lessonReminders(
      settings: makeSettings(lead: 60),
      courses: makeCourses(),
      from: DateTime(2026, 9, 7, 7, 0),
      days: 7,
    );
    final math = list.firstWhere((r) => r.title.contains('高等数学'));
    expect(math.when, DateTime(2026, 9, 7, 7, 10));
  });

  test('提前量为 0 表示上课时提醒', () {
    final list = lessonReminders(
      settings: makeSettings(lead: 0),
      courses: makeCourses(),
      from: DateTime(2026, 9, 7, 8, 0),
      days: 7,
    );
    final math = list.firstWhere((r) => r.title.contains('高等数学'));
    expect(math.when, DateTime(2026, 9, 7, 8, 10));
    expect(math.title, contains('该上课了'));
  });

  test('关掉提醒（-1）→ 一条都不排', () {
    final list = lessonReminders(
      settings: makeSettings(lead: -1),
      courses: makeCourses(),
      from: base,
      days: 7,
    );
    expect(list, isEmpty);
  });

  test('没设第 1 周周一 → 一条都不排（算不出教学周）', () {
    final s = makeSettings()..week1Monday = '';
    expect(
        lessonReminders(settings: s, courses: makeCourses(), from: base), isEmpty);
  });

  test('节次没填开始时间的课跳过，不炸', () {
    final s = makeSettings();
    s.periods = <Period>[Period(id: 'p9', label: '第 9 节')]; // 无 start
    final c = Courses(weeks: <int, List<Lesson>>{
      1: <Lesson>[Lesson(id: 'x', day: 1, slot: 'p9', name: '没时间的课')],
    });
    expect(lessonReminders(settings: s, courses: c, from: base), isEmpty);
  });

  test('跨周：第 1 周排完接着排第 2 周', () {
    // 第 1 周是 09-07 起；从 09-10（周四）看未来 7 天，会覆盖到 09-14（第 2 周周一）
    final c = Courses(weeks: <int, List<Lesson>>{
      1: <Lesson>[Lesson(id: 'a', day: 4, slot: 'p1', name: '第一周周四的课')],
      2: <Lesson>[Lesson(id: 'b', day: 1, slot: 'p1', name: '第二周周一的课')],
    });
    final list = lessonReminders(
      settings: makeSettings(),
      courses: c,
      from: DateTime(2026, 9, 10, 0, 0),
      days: 7,
    );
    final names = list.map((r) => r.title).join('|');
    expect(names, contains('第二周周一的课'));
  });

  test('同一节课的通知 id 稳定（重排是覆盖而不是堆一串）', () {
    final a = lessonReminders(
      settings: makeSettings(),
      courses: makeCourses(),
      from: base,
      days: 7,
    );
    final b = lessonReminders(
      settings: makeSettings(),
      courses: makeCourses(),
      from: DateTime(2026, 9, 7, 9, 0),
      days: 7,
    );
    final mapA = <String, int>{for (final r in a) r.lessonId: r.noteId};
    final mapB = <String, int>{for (final r in b) r.lessonId: r.noteId};
    for (final k in mapA.keys) {
      if (mapB.containsKey(k)) {
        expect(mapA[k], mapB[k], reason: '$k 的通知 id 不该变');
      }
    }
  });

  test('通知正文带节次和地点', () {
    // 从周一 07:00 看，距离 08:10 的高数还有 1 小时多，提醒排得进去
    final list = lessonReminders(
      settings: makeSettings(),
      courses: makeCourses(),
      from: DateTime(2026, 9, 7, 7, 0),
      days: 7,
    );
    final math = list.firstWhere((r) => r.title.contains('高等数学'));
    expect(math.body, contains('第 1 节'));
    expect(math.body, contains('1#102'));
  });

  test('HH:MM 解析：合法通过、越界和乱值返回 null', () {
    expect(minutesOfHhmm('08:10'), 490);
    expect(minutesOfHhmm('00:00'), 0);
    expect(minutesOfHhmm('8:5'), 485);
    expect(minutesOfHhmm('24:00'), isNull);
    expect(minutesOfHhmm('08:70'), isNull);
    expect(minutesOfHhmm('中午'), isNull);
    expect(minutesOfHhmm(''), isNull);
  });
}
