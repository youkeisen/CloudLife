// 备忘录纯逻辑的测试：分组统计、过滤搜索、副标题文案。
// v1.9.1 起标签功能去掉了（凯森要求），原来那几条标签用例一并删除。
// 行为基准是电脑版 app.js 的 noteGroupsHtml / filteredNotes / noteSubLine。
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/notes_logic.dart';

Note mkNote(
  String id, {
  String title = '',
  String type = 'text',
  String body = '',
  List<NoteItem>? items,
  bool pinned = false,
  bool archived = false,
  String updatedAt = '',
  String remindAt = '',
  String remindRepeat = '',
  int remindDays = 0,
}) {
  return Note(
    id: id,
    title: title,
    type: type,
    body: body,
    items: items,
    pinned: pinned,
    archived: archived,
    updatedAt: updatedAt,
    remindAt: remindAt,
    remindRepeat: remindRepeat,
    remindDays: remindDays,
  );
}

void main() {
  group('分组统计', () {
    test('空数据：三个基础分组都是 0', () {
      final groups = noteGroups(<Note>[]);
      expect(groups.map((g) => g.key).toList(),
          <String>['all', 'pinned', 'archived']);
      expect(groups.every((g) => g.count == 0), isTrue);
    });

    test('全部=未归档，置顶=未归档且置顶，归档=已归档', () {
      final notes = <Note>[
        mkNote('a', pinned: true),
        mkNote('b'),
        mkNote('c', archived: true),
      ];
      final groups = noteGroups(notes);
      expect(groups.firstWhere((g) => g.key == 'all').count, 2);
      expect(groups.firstWhere((g) => g.key == 'pinned').count, 1);
      expect(groups.firstWhere((g) => g.key == 'archived').count, 1);
    });

    test('v1.9.0：不再有标签分组，就三个', () {
      // 以前会按标签生成 tag:xxx 分组，去掉标签功能后只留三个。
      final notes = <Note>[
        mkNote('a'),
        mkNote('b'),
        mkNote('c', archived: true),
      ];
      expect(noteGroups(notes).map((g) => g.key).toList(),
          <String>['all', 'pinned', 'archived']);
    });
  });

  group('过滤与搜索', () {
    final notes = <Note>[
      mkNote('a', title: '购物清单', pinned: true),
      mkNote('b', body: '第一行\n第二行'),
      mkNote('c', type: 'todo', items: <NoteItem>[NoteItem(text: '买牛奶')]),
      mkNote('d', title: '已归档的', archived: true),
      mkNote('e', title: '第五条'),
    ];

    test('all：不含归档', () {
      final ids = filteredNotes(notes, 'all', '').map((n) => n.id).toList();
      expect(ids, <String>['a', 'b', 'c', 'e']);
    });

    test('pinned：只要置顶且未归档', () {
      expect(filteredNotes(notes, 'pinned', '').map((n) => n.id), <String>['a']);
    });

    test('archived：只要归档', () {
      expect(filteredNotes(notes, 'archived', '').map((n) => n.id), <String>['d']);
    });

    test('v1.9.0：tag:xxx 不再是有效分组，兜底返回全部', () {
      expect(filteredNotes(notes, 'tag:生活', '').length, 5,
          reason: '去掉标签功能后 tag: 开头是认不出来的键，走兜底');
    });

    test('认不出来的分组键兜底返回全部（含归档，与电脑版一致）', () {
      expect(filteredNotes(notes, '别的', '').length, 5);
    });

    test('搜索覆盖标题、正文、清单项', () {
      expect(filteredNotes(notes, 'all', '购物').map((n) => n.id), <String>['a']);
      expect(filteredNotes(notes, 'all', '第二行').map((n) => n.id), <String>['b']);
      expect(filteredNotes(notes, 'all', '牛奶').map((n) => n.id), <String>['c']);
    });

    test('搜索大小写不敏感、先分组后搜索', () {
      final withEn = <Note>[mkNote('x', title: 'Buy MILK')];
      expect(filteredNotes(withEn, 'all', 'milk'), hasLength(1));
      // 归档的不出现在 all 组里，搜得到也没用
      expect(filteredNotes(notes, 'all', '已归档'), isEmpty);
      expect(filteredNotes(notes, 'archived', '已归档').map((n) => n.id),
          <String>['d']);
    });

    test('搜索词首尾空白忽略', () {
      expect(filteredNotes(notes, 'all', '  购物  ').map((n) => n.id),
          <String>['a']);
    });
  });

  group('列表副标题', () {
    test('笔记：类型 · 正文第一行', () {
      final n = mkNote('a', body: '第一行\n第二行');
      expect(noteSubLine(n), '笔记 · 第一行');
    });

    test('v1.9.0：从带旧标签的 JSON 读进来，副标题也不显示标签', () {
      // 老数据里可能留着 tags（存量文件还没被清过的那种），
      // 读进来不能炸、也不能把它显示出来。
      final n = Note.fromJson(<String, dynamic>{
        'id': 'a',
        'body': '内容',
        'tags': <String>['生活', '学习'],
      });
      expect(noteSubLine(n), '笔记 · 内容');
    });

    test('笔记正文第一行截 20 个字符', () {
      final n = mkNote('a', body: '一二三四五六七八九十一二三四五六七八九十一二三');
      expect(noteSummaryText(n).length, 20);
      expect(noteSummaryText(n), '一二三四五六七八九十一二三四五六七八九十');
    });

    test('清单：进度摘要，空的清单没有摘要', () {
      final n = mkNote('a', type: 'todo', items: <NoteItem>[
        NoteItem(text: '甲', done: true),
        NoteItem(text: '乙'),
        NoteItem(text: '丙'),
      ]);
      expect(noteSubLine(n), '清单 · 1/3 项完成');
      expect(noteSubLine(mkNote('b', type: 'todo')), '清单');
    });

    test('标题为空的清单项文字也进搜索全文', () {
      final n = mkNote('a', type: 'todo',
          items: <NoteItem>[NoteItem(text: '交作业')]);
      expect(noteHaystack(n).contains('交作业'), isTrue);
    });
  });

  // ---------- 定时提醒（v1.8.2） ----------
  // 凯森要求「在定时这里加上每天和单次的选项」。

  group('提醒文案（v1.8.2 起，v1.9.1 加「N 天后」）', () {
    test('没设提醒 → 空字符串', () {
      expect(remindLabel(mkNote('a')), '');
      expect(remindLabel(mkNote('b', remindAt: '不是时间')), '');
    });

    test('单次说「今天 / 明天」，不写死日期', () {
      final now = DateTime(2026, 9, 21, 7, 0);
      // 今天 08:05 还没到
      expect(
        remindLabel(mkNote('a', remindAt: '2026-09-21T08:05:00'), now: now),
        '今天 08:05',
      );
      // 今天 06:05 已经过了 → 说的是明天那一次
      expect(
        remindLabel(mkNote('b', remindAt: '2026-09-21T06:05:00'), now: now),
        '明天 06:05',
      );
    });

    test('每天带「每天」', () {
      expect(
        remindLabel(mkNote('b',
            remindAt: '2026-09-22T08:05:00', remindRepeat: 'daily')),
        '每天 08:05',
      );
    });

    test('N 天后：0 写「今天」、1 写「明天」、其余写数字', () {
      String label(int days) => remindLabel(mkNote('a',
          remindAt: '2026-09-21T08:05:00',
          remindRepeat: 'days',
          remindDays: days));
      expect(label(0), '今天 08:05');
      expect(label(1), '明天 08:05');
      expect(label(3), '3 天后 08:05');
      expect(label(30), '30 天后 08:05');
    });
  });

  group('N 天后的时刻（v1.9.1）', () {
    test('3 天后：日期加 3、时:分不变', () {
      final now = DateTime(2026, 9, 21, 20, 0);
      final base = DateTime(2026, 9, 21, 8, 5);
      expect(
        afterDaysOccurrence(base, 3, now),
        DateTime(2026, 9, 24, 8, 5),
      );
    });

    test('跨月：9月30日 + 3 天 = 10月3日', () {
      final now = DateTime(2026, 9, 30, 20, 0);
      final base = DateTime(2026, 9, 30, 8, 5);
      expect(afterDaysOccurrence(base, 3, now), DateTime(2026, 10, 3, 8, 5));
    });

    test('0 天退回「最近一次」（今天没过就今天、过了就明天）', () {
      final base = DateTime(2026, 9, 21, 8, 5);
      expect(
        afterDaysOccurrence(base, 0, DateTime(2026, 9, 21, 7, 0)),
        DateTime(2026, 9, 21, 8, 5),
      );
      expect(
        afterDaysOccurrence(base, 0, DateTime(2026, 9, 21, 9, 0)),
        DateTime(2026, 9, 22, 8, 5),
      );
    });

    test('负天数也当 0 处理，不会算到过去', () {
      final now = DateTime(2026, 9, 21, 7, 0);
      final base = DateTime(2026, 9, 21, 8, 5);
      expect(afterDaysOccurrence(base, -5, now).isAfter(now), isTrue);
    });

    test('单次的「最近一次」：今天没过就是今天', () {
      final base = DateTime(2026, 9, 21, 23, 30);
      expect(
        nextOnceOccurrence(base, DateTime(2026, 9, 21, 20, 0)),
        DateTime(2026, 9, 21, 23, 30),
      );
      expect(
        nextOnceOccurrence(base, DateTime(2026, 9, 21, 23, 59)),
        DateTime(2026, 9, 22, 23, 30),
      );
    });
  });

  group('每天提醒的下一次时刻（v1.8.2）', () {
    // 为什么需要这个函数：每天重复的提醒存的是「设的那天的时刻」，
    // 早就过去了；而插件要求给一个未来时刻才会排进去。

    test('今天的点还没到 → 就是今天', () {
      final now = DateTime(2026, 9, 21, 7, 0);
      final base = DateTime(2026, 9, 21, 8, 0);
      expect(nextDailyOccurrence(base, now), DateTime(2026, 9, 21, 8, 0));
    });

    test('今天的点已经过了 → 顺延到明天', () {
      final now = DateTime(2026, 9, 21, 9, 0);
      final base = DateTime(2026, 9, 21, 8, 0);
      expect(nextDailyOccurrence(base, now), DateTime(2026, 9, 22, 8, 0));
    });

    test('正好等于当前时刻 → 算过了，顺延（免得排一个「现在」出去）', () {
      final now = DateTime(2026, 9, 21, 8, 0);
      final base = DateTime(2026, 9, 21, 8, 0);
      expect(nextDailyOccurrence(base, now), DateTime(2026, 9, 22, 8, 0));
    });

    test('跨月：9月30日的下一次是10月1日', () {
      final now = DateTime(2026, 9, 30, 9, 0);
      final base = DateTime(2026, 9, 30, 8, 0);
      expect(nextDailyOccurrence(base, now), DateTime(2026, 10, 1, 8, 0));
    });

    test('跨年：12月31日的下一次是次年1月1日', () {
      final now = DateTime(2026, 12, 31, 23, 0);
      final base = DateTime(2026, 12, 31, 22, 30);
      expect(nextDailyOccurrence(base, now), DateTime(2027, 1, 1, 22, 30));
    });

    test('设的是很久以前（比如半年前）也能算到今天之前的下一次', () {
      final now = DateTime(2026, 9, 21, 9, 0);
      final base = DateTime(2026, 3, 1, 8, 0); // 日期早就没意义了，只看时分
      final next = nextDailyOccurrence(base, now);
      expect(next, DateTime(2026, 9, 22, 8, 0),
          reason: '日期部分应被忽略，只按时分往下一次算');
      expect(next.isAfter(now), isTrue);
    });
  });
}
