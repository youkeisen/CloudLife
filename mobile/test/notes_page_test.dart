// 备忘录界面的测试：列表、分组、搜索、新建、自动保存、清单勾选、删除。
// 数据层用临时目录真跑（同步读写，测试里可以直接验证落盘结果）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/app.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-notes-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note seedNote(
    String id, {
    String title = '',
    String type = 'text',
    String body = '',
    List<NoteItem>? items,
    List<String> tags = const <String>[],
    bool pinned = false,
    bool archived = false,
  }) {
    final now = '2026-09-19T08:00:00+08:00';
    final n = Note(
      id: id,
      title: title,
      type: type,
      body: body,
      items: items,
      tags: tags,
      pinned: pinned,
      archived: archived,
      createdAt: now,
      updatedAt: now,
    );
    final notes = store.notes();
    notes.notes.add(n);
    store.saveNotes(notes);
    return n;
  }

  Map<String, dynamic> notesJson() =>
      jsonDecode(File('${tmp.path}/notes.json').readAsStringSync())
          as Map<String, dynamic>;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MyDayApp(store: store));
    await tester.pumpAndSettle();
    // v1.3.0 起：备忘录收进「功能」页，路径是 首页 → 功能 → 备忘录
    await tester.tap(find.text('功能').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('备忘录'));
    await tester.pumpAndSettle();
  }

  Future<void> openFirst(WidgetTester tester, String title) async {
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
  }

  testWidgets('空态有引导，新建后进编辑页，标题自动保存并落盘', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('notes-empty')), findsOneWidget);
    expect(find.text('这里还没有东西'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn-new-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-note-edit')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('field-title')), '购物');
    await tester.pump(); // 状态文案先变
    expect(find.text('有改动…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600)); // 防抖到点，自动保存
    expect(find.text('已保存'), findsOneWidget);

    final raw = notesJson();
    expect((raw['notes'] as List).first['title'], '购物');
    expect(((raw['notes'] as List).first['createdAt'] as String).isNotEmpty,
        isTrue);

    // 返回列表，能看到这条
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('购物'), findsOneWidget);
  });

  testWidgets('列表显示置顶星标和副标题（类型 · 标签 · 摘要）', (tester) async {
    seedNote('a', title: '置顶的', pinned: true, tags: <String>['生活'],
        body: '第一行\n第二行');
    seedNote('b', title: '清单的', type: 'todo', items: <NoteItem>[
      NoteItem(text: '甲', done: true),
      NoteItem(text: '乙'),
    ]);
    await pumpApp(tester);

    expect(find.text('★ 置顶的'), findsOneWidget);
    expect(find.text('笔记 · 生活 · 第一行'), findsOneWidget);
    expect(find.text('清单的'), findsOneWidget);
    expect(find.text('清单 · 1/2 项完成'), findsOneWidget);
  });

  testWidgets('分组切换：置顶 / 标签 / 归档', (tester) async {
    seedNote('a', title: '置顶的', pinned: true, tags: <String>['生活']);
    seedNote('b', title: '普通的');
    seedNote('c', title: '归档的', archived: true);
    seedNote('d', title: '带标签的', tags: <String>['生活']);
    await pumpApp(tester);

    // 默认「全部 3」：归档的不在
    expect(find.text('普通的'), findsOneWidget);
    expect(find.text('归档的'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('note-group-pinned')));
    await tester.pumpAndSettle();
    expect(find.text('★ 置顶的'), findsOneWidget);
    expect(find.text('普通的'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('note-group-tag:生活')));
    await tester.pumpAndSettle();
    expect(find.text('★ 置顶的'), findsOneWidget);
    expect(find.text('带标签的'), findsOneWidget);
    expect(find.text('普通的'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('note-group-archived')));
    await tester.pumpAndSettle();
    expect(find.text('归档的'), findsOneWidget);
    expect(find.text('★ 置顶的'), findsNothing);
  });

  testWidgets('搜索：命中标题和清单项，没结果给提示', (tester) async {
    seedNote('a', title: '买东西');
    seedNote('b', type: 'todo', items: <NoteItem>[NoteItem(text: '交作业')]);
    seedNote('c', title: '别的');
    await pumpApp(tester);

    await tester.enterText(find.byKey(const ValueKey('notes-search')), '交作业');
    await tester.pumpAndSettle();
    expect(find.text('清单的'), findsNothing);
    expect(find.text('别的'), findsNothing);
    // 命中的是清单那条（无标题显示「无标题」）
    expect(find.text('无标题'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('notes-search')), '不存在的词');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-no-match')), findsOneWidget);
    expect(find.text('没有符合条件的内容'), findsOneWidget);
  });

  testWidgets('编辑标题：防抖自动保存，落盘验证', (tester) async {
    seedNote('a', title: '旧标题');
    await pumpApp(tester);
    await openFirst(tester, '旧标题');
    expect(find.byKey(const ValueKey('page-note-edit')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('field-title')), '新标题');
    await tester.pump(const Duration(milliseconds: 600));

    expect(notesJson()['notes'].first['title'], '新标题');
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('切走前补存：没等防抖到点就返回，改动也不能丢', (tester) async {
    seedNote('a', title: '旧标题');
    await pumpApp(tester);
    await openFirst(tester, '旧标题');

    await tester.enterText(find.byKey(const ValueKey('field-title')), '刚敲的字');
    // 只往前走一小步，500ms 防抖还没到点
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(notesJson()['notes'].first['title'], '刚敲的字');
    expect(find.text('刚敲的字'), findsOneWidget);
  });

  testWidgets('标签输入框改标签，按逗号顿号切分后落盘', (tester) async {
    seedNote('a', title: '带标签', tags: <String>['旧标签']);
    await pumpApp(tester);
    await openFirst(tester, '带标签');

    await tester.enterText(find.byKey(const ValueKey('field-tags')), '甲，乙、丙');
    await tester.pump(const Duration(milliseconds: 600));
    expect(notesJson()['notes'].first['tags'], <String>['甲', '乙', '丙']);
  });

  testWidgets('正文笔记：编辑内容自动保存', (tester) async {
    seedNote('a', title: '笔记', body: '');
    await pumpApp(tester);
    await openFirst(tester, '笔记');

    await tester.enterText(find.byKey(const ValueKey('field-body')), '第一段文字');
    await tester.pump(const Duration(milliseconds: 600));
    expect(notesJson()['notes'].first['body'], '第一段文字');
  });

  testWidgets('切成清单：给一行空的，输入文字、勾选、加一行都落盘', (tester) async {
    seedNote('a', title: '会变清单');
    await pumpApp(tester);
    await openFirst(tester, '会变清单');

    // 类型下拉：切成「清单」
    await tester.tap(find.byKey(const ValueKey('field-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清单').last);
    await tester.pumpAndSettle();

    // 切过去就有一行空的，并且立即保存了类型
    expect(find.byKey(const ValueKey('todo-row-0')), findsOneWidget);
    expect(notesJson()['notes'].first['type'], 'todo');

    await tester.enterText(find.byKey(const ValueKey('todo-text-0')), '买牛奶');
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      (notesJson()['notes'].first['items'] as List).first['text'],
      '买牛奶',
    );

    // 勾上 = 做完，立即保存
    await tester.tap(find.byKey(const ValueKey('todo-check-0')));
    await tester.pumpAndSettle();
    expect(
      (notesJson()['notes'].first['items'] as List).first['done'],
      isTrue,
    );

    // 加一行
    await tester.ensureVisible(find.byKey(const ValueKey('btn-add-todo')));
    await tester.tap(find.byKey(const ValueKey('btn-add-todo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo-row-1')), findsOneWidget);
    expect((notesJson()['notes'].first['items'] as List), hasLength(2));

    // 删掉第二行（空的那行），第一行「买牛奶」还在
    await tester.tap(find.byKey(const ValueKey('todo-del-1')));
    await tester.pumpAndSettle();
    expect((notesJson()['notes'].first['items'] as List), hasLength(1));
    expect(
      (notesJson()['notes'].first['items'] as List).first['text'],
      '买牛奶',
    );
  });

  testWidgets('置顶 / 归档按钮立即保存，归档后进归档分组', (tester) async {
    seedNote('a', title: '会置顶');
    await pumpApp(tester);
    await openFirst(tester, '会置顶');

    await tester.ensureVisible(find.byKey(const ValueKey('btn-pin')));
    await tester.tap(find.byKey(const ValueKey('btn-pin')));
    await tester.pumpAndSettle();
    expect(notesJson()['notes'].first['pinned'], isTrue);
    expect(find.text('取消置顶'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('btn-archive')));
    await tester.tap(find.byKey(const ValueKey('btn-archive')));
    await tester.pumpAndSettle();
    expect(notesJson()['notes'].first['archived'], isTrue);

    // 回列表：全部里没有，归档里有（置顶过所以带 ★ 前缀）
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('会置顶'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('note-group-archived')));
    await tester.pumpAndSettle();
    expect(find.text('★ 会置顶'), findsOneWidget);
  });

  testWidgets('删除要二次确认，确认后列表和文件都没了', (tester) async {
    seedNote('a', title: '要删的');
    await pumpApp(tester);
    await openFirst(tester, '要删的');

    await tester.ensureVisible(find.byKey(const ValueKey('btn-delete-note')));
    await tester.tap(find.byKey(const ValueKey('btn-delete-note')));
    await tester.pumpAndSettle();
    expect(find.text('删除这条备忘录'), findsOneWidget);
    expect(find.text('删除后不可恢复。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn-confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('已删除'), findsOneWidget);
    expect(notesJson()['notes'], isEmpty);
    expect(find.byKey(const ValueKey('notes-empty')), findsOneWidget);
  });

  testWidgets('点保存键立刻落盘，不用等防抖', (tester) async {
    seedNote('a', title: '旧');
    await pumpApp(tester);
    await openFirst(tester, '旧');

    await tester.enterText(find.byKey(const ValueKey('field-title')), '手动存');
    // 只走一小步，防抖没到点
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('btn-save-note')));
    await tester.pumpAndSettle();
    expect(notesJson()['notes'].first['title'], '手动存');
    expect(find.text('已保存'), findsOneWidget);
  });
}
