// 备忘录界面的测试：列表、分组、搜索、新建、自动保存、清单勾选、删除。
// 数据层用临时目录真跑（同步读写，测试里可以直接验证落盘结果）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/app.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/notification_service.dart';
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
    // 编辑页加了「定时提醒」行后更高了，测试视口放大到手机常见尺寸，
    // 不然底部工具栏（置顶/归档/删除）会被挤到屏外（v1.5.0）。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
    // v1.6.0 界面中文化后，返回键的 tooltip 从 "Back" 变成「返回」，
      // flutter_test 的 pageBack() 只认英文 tooltip，这里改成点返回图标本身
      await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    expect(find.text('购物'), findsOneWidget);
  });

  testWidgets('列表显示置顶星标和副标题（类型 · 摘要）', (tester) async {
    seedNote('a', title: '置顶的', pinned: true, body: '第一行\n第二行');
    seedNote('b', title: '清单的', type: 'todo', items: <NoteItem>[
      NoteItem(text: '甲', done: true),
      NoteItem(text: '乙'),
    ]);
    await pumpApp(tester);

    expect(find.text('★ 置顶的'), findsOneWidget);
    // v1.9.1：副标题不再拼标签，就算数据里还带着
    expect(find.text('笔记 · 第一行'), findsOneWidget);
    expect(find.text('清单的'), findsOneWidget);
    expect(find.text('清单 · 1/2 项完成'), findsOneWidget);
  });

  testWidgets('分组切换：全部 / 置顶 / 归档（v1.9.1 起没有标签分组）', (tester) async {
    seedNote('a', title: '置顶的', pinned: true);
    seedNote('b', title: '普通的');
    seedNote('c', title: '归档的', archived: true);
    seedNote('d', title: '第四条的');
    await pumpApp(tester);

    // 去掉标签功能后不该再有标签分组
    expect(find.textContaining('生活'), findsNothing,
        reason: '标签分组已经删掉了');
    expect(find.text('全部 3'), findsOneWidget);

    // 默认「全部 3」：归档的不在
    expect(find.text('普通的'), findsOneWidget);
    expect(find.text('归档的'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('note-group-pinned')));
    await tester.pumpAndSettle();
    expect(find.text('★ 置顶的'), findsOneWidget);
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
    // v1.6.0 界面中文化后，返回键的 tooltip 从 "Back" 变成「返回」，
      // flutter_test 的 pageBack() 只认英文 tooltip，这里改成点返回图标本身
      await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();

    expect(notesJson()['notes'].first['title'], '刚敲的字');
    expect(find.text('刚敲的字'), findsOneWidget);
  });

  testWidgets('v1.9.0：编辑页没有标签输入框，存过之后数据里也没有 tags', (tester) async {
    seedNote('a', title: '随便记');
    await pumpApp(tester);
    await openFirst(tester, '随便记');

    expect(find.byKey(const ValueKey('field-tags')), findsNothing,
        reason: '凯森要求把笔记里的标签删掉');
    expect(find.text('标签（用逗号或顿号分开）'), findsNothing,
        reason: '那个输入框的标签文字也不该在');

    await tester.enterText(find.byKey(const ValueKey('field-title')), '改过标题');
    await tester.pump(const Duration(milliseconds: 600));
    final saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
    expect(saved['title'], '改过标题');
    expect(saved.containsKey('tags'), isFalse, reason: '写出去的 JSON 里不该再有 tags');
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
    // v1.6.0 界面中文化后，返回键的 tooltip 从 "Back" 变成「返回」，
      // flutter_test 的 pageBack() 只认英文 tooltip，这里改成点返回图标本身
      await tester.tap(find.byIcon(Icons.arrow_back).first);
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
  // ---------- v1.9.1：定时提醒（先选时间，再选方式） ----------
  // 凯森 2026-09-21 的要求：
  //   1) 点提醒**直接选时分**，不选日期
  //   2) 滚轮默认停在**当前时间**（以前是 +1 小时）
  //   3) 设好时间后，**在编辑页上**选 单次 / 每天 / N 天后

  group('定时提醒（v1.9.1）', () {
    String two(int n) => n < 10 ? '0$n' : '$n';

    testWidgets('点提醒直接进时间滚轮，不选日期；默认停在当前时间', (tester) async {
      seedNote('a', title: '续火花', body: '记得回消息');
      await pumpApp(tester);
      await openFirst(tester, '续火花');

      await tester.tap(find.byKey(const ValueKey('field-remind')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('wheel-hour')), findsOneWidget);
      expect(find.text('选择时间'), findsOneWidget);
      expect(find.text('选提醒日期'), findsNothing, reason: '不该再有日期选择器');

      // 默认停在当前时间（凯森要求不要往后调一小时）
      final t = TimeOfDay.fromDateTime(DateTime.now());
      expect(find.text(two(t.hour)), findsWidgets,
          reason: '滚轮默认该停在当前的小时');
    });

    testWidgets('选完时间后，编辑页上出现「单次 / 每天 / N 天后」', (tester) async {
      seedNote('a', title: '续火花');
      await pumpApp(tester);
      await openFirst(tester, '续火花');

      expect(find.byKey(const ValueKey('remind-mode-once')), findsNothing,
          reason: '还没设提醒时不该有方式选择');

      await tester.tap(find.byKey(const ValueKey('field-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wheel-ok')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('remind-mode-once')), findsOneWidget);
      expect(find.byKey(const ValueKey('remind-mode-daily')), findsOneWidget);
      expect(find.byKey(const ValueKey('remind-mode-days')), findsOneWidget);
      expect(find.text('提醒方式'), findsOneWidget);
      expect(find.byKey(const ValueKey('field-remind-days')), findsNothing,
          reason: '天数输入框只在选了 N 天后才出现');

      final saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindAt'], isNotEmpty);
      expect(saved['remindRepeat'], '', reason: '刚设好默认是单次');
    });

    testWidgets('点「每天」：落盘 daily，排给系统的是每天重复', (tester) async {
      seedNote('a', title: '续火花');
      await pumpApp(tester);
      await openFirst(tester, '续火花');
      await tester.tap(find.byKey(const ValueKey('field-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wheel-ok')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('remind-mode-daily')));
      await tester.pumpAndSettle();

      final saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindRepeat'], 'daily');

      final t = TimeOfDay.fromDateTime(DateTime.now());
      expect(find.text('每天 ${two(t.hour)}:${two(t.minute)}'), findsOneWidget);

      final last = NotificationService.debugLastSchedule;
      expect(last, isNotNull);
      expect(last!.daily, isTrue, reason: '没带每天重复参数的话只会响一次');
      expect(last.when.isAfter(DateTime.now()), isTrue,
          reason: '插件只排未来的时刻');
    });

    testWidgets('点「N 天后」：出现天数输入框，默认 1 天', (tester) async {
      seedNote('a', title: '续火花');
      await pumpApp(tester);
      await openFirst(tester, '续火花');
      await tester.tap(find.byKey(const ValueKey('field-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wheel-ok')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('remind-mode-days')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('field-remind-days')), findsOneWidget);
      final saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindRepeat'], 'days');
      expect(saved['remindDays'], 1, reason: '默认 1 天，不该是 0');
      expect(find.textContaining('明天'), findsOneWidget);

      final last = NotificationService.debugLastSchedule!;
      final now = DateTime.now();
      expect(last.daily, isFalse);
      expect(
        last.when,
        DateTime(now.year, now.month, now.day + 1, last.when.hour, last.when.minute),
        reason: '1 天后 = 明天那个时:分',
      );
    });

    testWidgets('改天数：3 天后 → 落盘并显示「3 天后」', (tester) async {
      seedNote('a', title: '续火花');
      await pumpApp(tester);
      await openFirst(tester, '续火花');
      await tester.tap(find.byKey(const ValueKey('field-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wheel-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remind-mode-days')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('field-remind-days')), '3');
      await tester.pumpAndSettle();

      final saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindDays'], 3);
      expect(find.textContaining('3 天后'), findsOneWidget);
    });

    testWidgets('在方式之间来回切：天数会清掉，不残留', (tester) async {
      seedNote('a', title: '续火花');
      await pumpApp(tester);
      await openFirst(tester, '续火花');
      await tester.tap(find.byKey(const ValueKey('field-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wheel-ok')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('remind-mode-days')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('field-remind-days')), '7');
      await tester.pumpAndSettle();
      expect((notesJson()['notes'] as List).first['remindDays'], 7);

      // 切到每天：天数归零（不然下次切回来会冒出个 7）
      await tester.tap(find.byKey(const ValueKey('remind-mode-daily')));
      await tester.pumpAndSettle();
      var saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindRepeat'], 'daily');
      expect(saved['remindDays'], 0);

      // 再切回 N 天后：**界面上记着刚填的 7**（不该把用户刚敲的数字弄丢）
      await tester.tap(find.byKey(const ValueKey('remind-mode-days')));
      await tester.pumpAndSettle();
      saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindRepeat'], 'days');
      expect(saved['remindDays'], 7,
          reason: '数据层切走时清了 0，但输入框留着 7，切回来该恢复成 7');
    });

    testWidgets('取消提醒：时间、方式、天数一起清掉', (tester) async {
      final notes = store.notes();
      notes.notes.add(Note(
        id: 'a',
        title: '续火花',
        remindAt: '2026-09-21T08:00:00',
        remindRepeat: Note.remindRepeatDays,
        remindDays: 3,
        createdAt: '2026-09-19T08:00:00+08:00',
        updatedAt: '2026-09-19T08:00:00+08:00',
      ));
      store.saveNotes(notes);

      await pumpApp(tester);
      await openFirst(tester, '续火花');
      expect(find.text('3 天后 08:00'), findsOneWidget, reason: '先进来确认是 N 天后');

      expect(find.byKey(const ValueKey('btn-clear-remind')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('btn-clear-remind')));
      await tester.pumpAndSettle();

      final saved = (notesJson()['notes'] as List).first as Map<String, dynamic>;
      expect(saved['remindAt'], '');
      expect(saved['remindRepeat'], '');
      expect(saved['remindDays'], 0);
      expect(find.text('不提醒'), findsOneWidget);
      expect(find.byKey(const ValueKey('remind-mode-once')), findsNothing,
          reason: '没提醒了就不该再显示方式选择');
    });
  });
}
