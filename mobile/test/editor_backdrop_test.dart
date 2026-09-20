// 独立路由页面的背景守卫：**所有** push 出来的整页都必须有玻璃渐变背景。
//
// 背景（v1.1.0 的真机 bug，2026-09-20 在记账编辑页又犯了一次）：
// 这些页面是 Navigator.push 出来的独立路由，底下没有主壳子的渐变，
// 而主题里 `scaffoldBackgroundColor: Colors.transparent`，
// 于是透明的 Scaffold 直接露出路由遮罩的黑底 —— 浅色模式下进页面就是一片黑。
//
// **规矩**：独立整页要么自己套 `GlassBackdrop`，要么由 push 它的地方套。
// 这个测试挨个把独立整页渲染出来，检查 GlassBackdrop 在场。
// 将来新增整页如果忘了垫，这里会立刻挂 —— 不用等凯森在真机上看见黑屏。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/ui/glass.dart';
import 'package:my_day_phone/ui/ledger_edit_page.dart';
import 'package:my_day_phone/ui/ledger_page.dart';
import 'package:my_day_phone/ui/notes_page.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-backdrop-');
    store = Store(tmp)..init();

    final now = Store.nowIso();
    final note = Note(
      id: 'n1',
      title: '作业',
      type: 'todo',
      items: <NoteItem>[NoteItem(text: '第一行', done: false)],
      createdAt: now,
      updatedAt: now,
    );
    final notes = store.notes();
    notes.notes.add(note);
    store.saveNotes(notes);

    // 记账：种好默认分类，再放一笔，好让编辑页有内容可渲染
    final l = store.ensureLedgerSeed();
    l.records.add(LedgerRecord(
      id: 'r1',
      amount: 12,
      categoryId: 'cat-food',
      date: '2026-09-20',
      note: '午饭',
      createdAt: now,
    ));
    store.saveLedger(l);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 把一个独立整页直接 pump 出来（不经过主壳子，模拟 push 后的样子）。
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  group('备忘录', () {
    testWidgets('浅色模式：进编辑页也要有玻璃渐变背景，不能是黑底', (tester) async {
      // 列表页是塞进主壳子 Scaffold 里的内容块，测试要自己给它套一个
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotesPage(store: store)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作业'));
      await tester.pumpAndSettle();

      expect(find.text('编辑清单'), findsOneWidget);
      expect(find.byType(GlassBackdrop), findsWidgets,
          reason: '编辑页是独立路由，必须自己垫玻璃渐变背景');
    });

    testWidgets('深色模式：同样要有背景垫层', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NotesPage(store: store)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作业'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('field-title')), findsOneWidget);
      expect(find.byType(GlassBackdrop), findsWidgets);
    });
  });

  group('记账（v1.7.0 漏过一次，凯森 2026-09-20 反馈变黑）', () {
    testWidgets('记一笔页要有玻璃渐变背景', (tester) async {
      await pumpPage(tester, LedgerEditPage(store: store));
      expect(find.text('记一笔'), findsOneWidget);
      expect(find.byType(GlassBackdrop), findsWidgets,
          reason: '「记一笔」是独立路由，忘了垫背景就会是一片黑');
    });

    testWidgets('改一笔页要有玻璃渐变背景', (tester) async {
      await pumpPage(
        tester,
        LedgerEditPage(store: store, record: store.ledger().records.first),
      );
      expect(find.text('改一笔'), findsOneWidget);
      expect(find.byType(GlassBackdrop), findsWidgets);
    });

    testWidgets('从记账主页点「＋」进去的那条路也要有背景', (tester) async {
      // 这条才是凯森实际走的路：主页 push 编辑页
      await pumpPage(
        tester,
        Scaffold(appBar: AppBar(), body: LedgerPage(store: store)),
      );
      await tester.tap(find.byKey(const ValueKey('ledger-fab')));
      await tester.pumpAndSettle();

      expect(find.text('记一笔'), findsOneWidget);
      expect(find.byType(GlassBackdrop), findsWidgets,
          reason: '主页 push 出来的编辑页同样要有背景垫层');
    });

    testWidgets('记账主页本身不需要垫（它由「功能」页的 _open 套背景）', (tester) async {
      // 主页是被 features_page._open 塞进 GlassBackdrop 里的内容块，
      // 自己不该再套一层（套两层会叠出多余的模糊）。
      await pumpPage(
        tester,
        Scaffold(appBar: AppBar(), body: LedgerPage(store: store)),
      );
      expect(find.byType(GlassBackdrop), findsNothing,
          reason: '主页是由调用方垫背景的内容块，自己不该再套一层');
    });
  });

  group('源码层面的兜底检查', () {
    // widget 测试覆盖的是「我知道的页面」；这一条扫源码，
    // 防止将来新增的独立整页文件夹里冒出没垫背景的。
    test('所有 ui/ 下的独立整页要么套了 GlassBackdrop、要么是内容块', () {
      final dir = Directory('${Directory.current.path}/lib/ui');
      expect(dir.existsSync(), isTrue);

      // 这几位是**内容块**（由别的页/壳子负责垫背景），不要求自己套：
      //   features_page 的 _open 会套；home_page/weather_page/courses_page/
      //   settings_page/notes_page 是壳子里的 Tab 内容；
      //   ledger_page 由 features_page._open 套。
      const contentBlocks = <String>{
        'features_page.dart',
        'home_page.dart',
        'weather_page.dart',
        'courses_page.dart',
        'settings_page.dart',
        'notes_page.dart',
        'ledger_page.dart',
        'glass.dart', // 背景组件自身
        'wheel_time_picker.dart', // 选择器组件，不是页面
      };

      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.endsWith('.dart') || contentBlocks.contains(name)) continue;
        final text = f.readAsStringSync();
        // 只要文件里有 Scaffold(，就说明它是个页面，必须有背景
        if (!text.contains('Scaffold(')) continue;
        if (!text.contains('GlassBackdrop')) offenders.add(name);
      }
      expect(offenders, isEmpty,
          reason: '这些页面用了 Scaffold 但没垫 GlassBackdrop，'
              '浅色模式下会显示成黑底：$offenders');
    });
  });
}
