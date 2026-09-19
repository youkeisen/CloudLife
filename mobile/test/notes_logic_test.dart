// 备忘录纯逻辑的测试：分组统计、过滤搜索、标签解析、副标题文案。
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
  List<String> tags = const <String>[],
  bool pinned = false,
  bool archived = false,
  String updatedAt = '',
}) {
  return Note(
    id: id,
    title: title,
    type: type,
    body: body,
    items: items,
    tags: tags,
    pinned: pinned,
    archived: archived,
    updatedAt: updatedAt,
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

    test('标签分组只数未归档的，按首次出现顺序排', () {
      final notes = <Note>[
        mkNote('a', tags: <String>['生活']),
        mkNote('b', tags: <String>['生活', '学习']),
        mkNote('c', tags: <String>['学习'], archived: true), // 归档的不计数
        mkNote('d', tags: <String>['生活']), // 重复标签累加
      ];
      final groups = noteGroups(notes);
      final tagKeys = groups.map((g) => g.key).skip(2).take(groups.length - 3);
      expect(tagKeys, <String>['tag:生活', 'tag:学习']);
      expect(groups.firstWhere((g) => g.key == 'tag:生活').count, 3);
      expect(groups.firstWhere((g) => g.key == 'tag:学习').count, 1);
    });

    test('空字符串标签不进分组', () {
      final notes = <Note>[mkNote('a', tags: <String>['', '  '])];
      expect(noteGroups(notes).where((g) => g.key.startsWith('tag:')), isEmpty);
    });
  });

  group('过滤与搜索', () {
    final notes = <Note>[
      mkNote('a', title: '购物清单', pinned: true),
      mkNote('b', body: '第一行\n第二行'),
      mkNote('c', type: 'todo', items: <NoteItem>[NoteItem(text: '买牛奶')]),
      mkNote('d', title: '已归档的', archived: true),
      mkNote('e', tags: <String>['生活'], title: '带标签的'),
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

    test('tag 分组：只要带该标签且未归档', () {
      expect(filteredNotes(notes, 'tag:生活', '').map((n) => n.id), <String>['e']);
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

  group('标签解析', () {
    test('逗号 / 中文逗号 / 顿号都能分，去首尾空白', () {
      expect(parseTags('a, b，c、d'), <String>['a', 'b', 'c', 'd']);
    });

    test('空段丢掉，不合并重复（和电脑版一致）', () {
      expect(parseTags('a,,、 b '), <String>['a', 'b']);
      expect(parseTags('x、x'), <String>['x', 'x']);
      expect(parseTags(''), isEmpty);
    });
  });

  group('列表副标题', () {
    test('笔记：类型 · 标签 · 正文第一行', () {
      final n = mkNote('a', body: '第一行\n第二行', tags: <String>['生活', '学习']);
      expect(noteSubLine(n), '笔记 · 生活、学习 · 第一行');
    });

    test('没标签就不写「未分类」', () {
      expect(noteSubLine(mkNote('a', body: '内容')), '笔记 · 内容');
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
}
