// 首页聚合逻辑的测试：问候语、时间换算、今日课程状态、备忘录速览、
// 清单勾选只翻转单条（尾巴不能被冲掉）。数据全部虚构。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/home_logic.dart';
import 'package:my_day_phone/models.dart';

Period period(String id, String label, String start, String end) =>
    Period(id: id, label: label, start: start, end: end);

Lesson lesson(String id, int day, String slot, {String spanEnd = '', String name = '示例课'}) =>
    Lesson(id: id, day: day, slot: slot, spanEnd: spanEnd, name: name);

Note note(String id,
    {String title = '',
    String type = NoteType.text,
    String body = '',
    List<NoteItem>? items,
    List<String>? tags,
    bool pinned = false,
    bool archived = false,
    String updatedAt = '2026-09-19T08:00:00+08:00'}) {
  return Note(
    id: id,
    title: title,
    type: type,
    body: body,
    items: items,
    tags: tags,
    pinned: pinned,
    archived: archived,
    createdAt: '2026-09-19T07:00:00+08:00',
    updatedAt: updatedAt,
  );
}

void main() {
  // ---------- 问候语 ----------
  group('greetingOf', () {
    DateTime at(int h) => DateTime(2026, 9, 19, h);
    test('按小时分段，边界都对上电脑版', () {
      expect(greetingOf(at(5)), '还没睡');
      expect(greetingOf(at(6)), '早上好');
      expect(greetingOf(at(10)), '早上好');
      expect(greetingOf(at(11)), '中午好');
      expect(greetingOf(at(13)), '中午好');
      expect(greetingOf(at(14)), '下午好');
      expect(greetingOf(at(17)), '下午好');
      expect(greetingOf(at(18)), '晚上好');
      expect(greetingOf(at(23)), '晚上好');
    });
    test('weekdayCn', () {
      expect(weekdayCn(1), '周一');
      expect(weekdayCn(7), '周日');
      expect(weekdayCn(0), '');
    });
  });

  // ---------- 时间换算 ----------
  group('minutesFromHhmm / stripDashSpace', () {
    test('正常与带秒的写法', () {
      expect(minutesFromHhmm('08:10'), 8 * 60 + 10);
      expect(minutesFromHhmm('10:30:00'), 630, reason: '电脑版只取前两段，带秒也认');
      expect(minutesFromHhmm('00:00'), 0);
    });
    test('解析不了返回 null', () {
      expect(minutesFromHhmm(''), isNull);
      expect(minutesFromHhmm('1030'), isNull);
      expect(minutesFromHhmm('ab:cd'), isNull);
    });
    test('stripDashSpace 等价 Python strip(\' -\')', () {
      expect(stripDashSpace(' - '), '');
      expect(stripDashSpace('08:10 - '), '08:10');
      expect(stripDashSpace(' - 12:00'), '12:00');
      expect(stripDashSpace('08:00 - 09:40'), '08:00 - 09:40');
    });
  });

  // ---------- 今日课程状态 ----------
  group('computeLessonStates', () {
    final periods = <Period>[
      period('p1', '第1节', '08:00', '08:45'),
      period('p2', '第2节', '08:55', '09:40'),
      period('p3', '第3节', '10:00', '10:45'),
    ];

    test('三种状态：还没到 / 正在上 / 已上完', () {
      // 10:30：p1（08:00-08:45）、p2（08:55-09:40）已上完，p3（10:00-10:45）正在上
      final states = computeLessonStates(
        <Lesson>[lesson('a', 1, 'p3'), lesson('b', 1, 'p1'), lesson('c', 1, 'p2')],
        periods,
        10 * 60 + 30,
      );
      expect(states.map((s) => s.lesson.id).toList(), <String>['b', 'c', 'a'],
          reason: '按开始时间排序');
      expect(states[0].status, 'done');
      expect(states[1].status, 'done');
      expect(states[2].status, 'now');

      // 07:50：三节都还没到，全部 upcoming
      final upcoming = computeLessonStates(
        <Lesson>[lesson('b', 1, 'p1'), lesson('c', 1, 'p2')],
        periods,
        7 * 60 + 50,
      );
      expect(upcoming[0].status, 'upcoming');
      expect(upcoming[0].next, isTrue, reason: '第一个 upcoming 是「下一节」');
      expect(upcoming[1].status, 'upcoming');
      expect(upcoming[1].next, isFalse);
    });

    test('「下一节」只标第一个 upcoming，全上完就没有', () {
      final early = computeLessonStates(
        <Lesson>[lesson('a', 1, 'p1'), lesson('b', 1, 'p2')],
        periods,
        7 * 60,
      );
      expect(early[0].next, isTrue);
      expect(early[1].next, isFalse);

      final late = computeLessonStates(
        <Lesson>[lesson('a', 1, 'p1'), lesson('b', 1, 'p2')],
        periods,
        20 * 60,
      );
      expect(late.every((s) => !s.next), isTrue);
    });

    test('跨节次的课用 spanEnd 的结束时间', () {
      // p1 连上到 p2：08:00 - 09:40，08:50 时还「正在上」
      final states = computeLessonStates(
        <Lesson>[lesson('a', 1, 'p1', spanEnd: 'p2')],
        periods,
        8 * 60 + 50,
      );
      expect(states.single.status, 'now');
      expect(states.single.periodRange, '08:00 - 09:40');
    });

    test('结束早于开始按跨零点处理', () {
      final night = <Period>[period('n1', '晚课', '23:00', '00:30')];
      final states = computeLessonStates(
        <Lesson>[lesson('a', 1, 'n1')],
        night,
        23 * 60 + 30,
      );
      expect(states.single.status, 'now');
    });

    test('节次缺失或没设时间 → unknown，且排到最后', () {
      final states = computeLessonStates(
        <Lesson>[lesson('a', 1, 'nope'), lesson('b', 1, 'p1')],
        periods,
        7 * 60,
      );
      expect(states[0].lesson.id, 'b');
      expect(states[1].lesson.id, 'a');
      expect(states[1].status, 'unknown');
      expect(states[1].begin, isNull);
    });

    test('时间没设齐时的文案：空区间给「时间未设置」', () {
      final half = <Period>[period('h1', '第1节', '08:00', '')];
      final states = computeLessonStates(
        <Lesson>[lesson('a', 1, 'h1')],
        half,
        7 * 60,
      );
      expect(states.single.status, 'unknown');
      expect(states.single.periodRange, '08:00');
    });

    test('periodLabel 用节次名字原文，空就是空', () {
      final anon = <Period>[period('x1', '', '08:00', '08:45')];
      final states = computeLessonStates(
        <Lesson>[lesson('a', 1, 'x1')],
        anon,
        7 * 60,
      );
      expect(states.single.periodLabel, '');
    });
  });

  // ---------- 备忘录速览 ----------
  group('previewNotes', () {
    test('未归档、最多 3 条、置顶在前、改过的在前', () {
      final notes = <Note>[
        note('a', title: '甲', updatedAt: '2026-09-19T08:00:00+08:00'),
        note('b', title: '乙', pinned: true, updatedAt: '2026-09-19T07:00:00+08:00'),
        note('c', title: '丙', archived: true),
        note('d', title: '丁', updatedAt: '2026-09-19T09:00:00+08:00'),
        note('e', title: '戊', updatedAt: '2026-09-19T06:00:00+08:00'),
        note('f', title: '己'),
      ];
      final out = previewNotes(notes);
      expect(out.length, 3);
      // 置顶乙最先；然后按 updatedAt 倒序：丁、甲
      expect(out.map((n) => n.id).toList(), <String>['b', 'd', 'a']);
    });

    test('清单摘要 x/y 项完成（0 项也给），笔记摘要取正文第一行截 24 字', () {
      final notes = <Note>[
        note('t1', type: NoteType.todo, items: <NoteItem>[]),
        note('t2', type: NoteType.todo,
            items: <NoteItem>[NoteItem(text: '买', done: true), NoteItem(text: '卖')]),
        note('t3', body: '甲乙丙丁戊己庚辛壬癸甲乙丙丁戊己庚辛壬癸甲乙丙丁戊己庚辛壬癸\n第二行'),
      ];
      final out = previewNotes(notes);
      expect(out[0].summary, '0/0 项完成');
      expect(out[1].summary, '1/2 项完成');
      expect(out[2].summary.length, 24);
      expect(out[2].summary.contains('第二行'), isFalse,
          reason: '摘要只取第一行，不能跨行');
    });

    test('清单只摊前 6 项，moreItems 记账', () {
      final items = <NoteItem>[
        for (var i = 1; i <= 8; i++) NoteItem(text: '第$i项', done: i % 2 == 0),
      ];
      final out = previewNotes(<Note>[note('t', type: NoteType.todo, items: items)]);
      final p = out.single;
      expect(p.items.length, 6);
      expect(p.moreItems, 2);
      expect(p.itemsDone, 4);
      expect(p.itemsTotal, 8);
    });

    test('正文截 200 字并标 bodyCut，标题空给「无标题」', () {
      final long = '长' * 250;
      final out = previewNotes(<Note>[
        note('a', body: long),
        note('b', body: '短'),
        note('c'),
      ]);
      expect(out[0].body.length, 200);
      expect(out[0].bodyCut, isTrue);
      expect(out[1].bodyCut, isFalse);
      expect(out[2].title, '无标题');
      expect(out[2].body, '');
    });

    test('标签原样带出去，置顶标出来', () {
      final out = previewNotes(<Note>[
        note('a', title: '甲', pinned: true, tags: <String>['学习', '生活']),
      ]);
      expect(out.single.tags, <String>['学习', '生活']);
      expect(out.single.pinned, isTrue);
    });
  });

  // ---------- 清单勾选 ----------
  group('toggleNoteItem', () {
    test('只翻转指定那一项，没显示出来的项原样保留', () {
      final items = <NoteItem>[
        NoteItem(text: '一', done: false),
        NoteItem(text: '二', done: false),
        NoteItem(text: '三', done: true),
      ];
      final notes = Notes(notes: <Note>[note('t', type: NoteType.todo, items: items)]);
      final saved = toggleNoteItem(notes, 't', 1, nowIso: () => '2026-09-19T10:00:00+08:00');
      expect(saved, isNotNull);
      expect(notes.notes.single.items[0].done, isFalse);
      expect(notes.notes.single.items[1].done, isTrue);
      expect(notes.notes.single.items[2].done, isTrue, reason: '没动的项不能被重置');
      expect(notes.notes.single.updatedAt, '2026-09-19T10:00:00+08:00');
    });

    test('找不到笔记 / 序号越界返回 null 且什么都不改', () {
      final items = <NoteItem>[NoteItem(text: '一')];
      final notes = Notes(notes: <Note>[note('t', type: NoteType.todo, items: items)]);
      expect(toggleNoteItem(notes, 'nope', 0, nowIso: () => 'x'), isNull);
      expect(toggleNoteItem(notes, 't', -1, nowIso: () => 'x'), isNull);
      expect(toggleNoteItem(notes, 't', 5, nowIso: () => 'x'), isNull);
      expect(notes.notes.single.items.single.done, isFalse);
      expect(notes.notes.single.updatedAt, '2026-09-19T08:00:00+08:00');
    });

    test('再勾一次能翻回来', () {
      final items = <NoteItem>[NoteItem(text: '一', done: false)];
      final notes = Notes(notes: <Note>[note('t', type: NoteType.todo, items: items)]);
      var clock = 0;
      toggleNoteItem(notes, 't', 0, nowIso: () => 't${clock++}');
      expect(notes.notes.single.items.single.done, isTrue);
      toggleNoteItem(notes, 't', 0, nowIso: () => 't${clock++}');
      expect(notes.notes.single.items.single.done, isFalse);
    });
  });
}
