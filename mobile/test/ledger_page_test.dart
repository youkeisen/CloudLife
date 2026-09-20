// 记账界面的测试（v1.7.0，需求文档第 3 条）：
// 入口、主页合计与分组、记一笔、改一笔、删一笔、分类管理。
// 数据层用临时目录真跑，能直接验证落盘结果。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/app.dart';
import 'package:my_day_phone/backup.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/ui/ledger_page.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-ledger-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 塞一笔账进数据层。
  LedgerRecord seed(
    String id, {
    double amount = 10,
    String categoryId = 'cat-food',
    String date = '2026-09-19',
    String note = '',
    String createdAt = '2026-09-19T12:00:00+08:00',
    String kind = ledgerKindExpense,
  }) {
    final r = LedgerRecord(
      id: id,
      amount: amount,
      categoryId: categoryId,
      date: date,
      note: note,
      createdAt: createdAt,
      kind: kind,
    );
    final l = store.ensureLedgerSeed();
    l.records.add(r);
    store.saveLedger(l);
    return r;
  }

  Map<String, dynamic> ledgerJson() =>
      jsonDecode(File('${tmp.path}/ledger.json').readAsStringSync())
          as Map<String, dynamic>;

  List<dynamic> recordsJson() => ledgerJson()['records'] as List<dynamic>;

  List<dynamic> catsJson() => ledgerJson()['categories'] as List<dynamic>;

  /// 从「功能」页进记账。视口放大，免得键盘那几行被挤出屏幕。
  Future<void> pumpLedger(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MyDayApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('功能').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记账'));
    await tester.pumpAndSettle();
  }

  /// 进「记一笔」页，并把自带键盘滚进视口。
  ///
  /// 编辑页是个 ListView（金额卡 / 日期 / 分类网格 / 键盘），键盘在最底下，
  /// 测试视口再高也可能在屏幕外——**必须滚到它**，不然 tap 找不到 key-3。
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ledger-fab')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('ledger-edit-body')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
  }

  /// 点自带键盘上的数字（key 是 key-0 ~ key-9 / key-dot / key-del …）。
  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final ch in digits.split('')) {
      final key = ch == '.' ? 'key-dot' : 'key-$ch';
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }
  }

  /// 把记账主页切到 [target] 那个月（`YYYY-MM`）。
  ///
  /// 主页一进来落在**当前月**，而测试数据固定用 2026-09，所以要先按
  /// 「差几个月」点几次左右箭头。**差值按「屏幕上现在显示哪个月」算**，
  /// 不能按「今天」算——这个函数会被连续调用（8 月 → 7 月 → 9 月），
  /// 用今天当基准第二次就错了。同样也不能写死点几次：测试跑在哪天
  /// 不是我们能定的，写死会在跨月那天挂掉。
  Future<void> gotoMonth(WidgetTester tester, String target) async {
    for (var guard = 0; guard < 240; guard++) {
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('ledger-month-label')))
          .data!;
      final m = RegExp(r'^(\d{4})年(\d{1,2})月$').firstMatch(label)!;
      final cur = int.parse(m.group(1)!) * 12 + int.parse(m.group(2)!);
      final want = int.parse(target.substring(0, 4)) * 12 +
          int.parse(target.substring(5, 7));
      if (cur == want) return;
      await tester.tap(find.byKey(
          ValueKey(cur < want ? 'ledger-next-month' : 'ledger-prev-month')));
      await tester.pumpAndSettle();
    }
    fail('切不到 $target');
  }

  /// 直接把主页渲染成某个月（省去点箭头），用于只关心某个月内容的用例。
  ///
  /// **必须套一层 Scaffold**：LedgerPage 自己只有 Stack，删除后弹的
  /// 提示条（SnackBar）要靠上级的 ScaffoldMessenger，没有 Scaffold 会炸。
  Future<void> pumpLedgerAt(WidgetTester tester, String month) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('记账')),
        body: LedgerPage(store: store, initialMonth: month),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('功能页有记账入口，进去是空态 + 默认分类已种好', (tester) async {
    await pumpLedger(tester);
    expect(find.byKey(const ValueKey('ledger-empty')), findsOneWidget);
    expect(find.text('这个月还没有记账'), findsOneWidget);

    // 本月的月份标题
    expect(find.byKey(const ValueKey('ledger-month-label')), findsOneWidget);
    // 默认分类落了盘（7 个）
    expect(catsJson().length, 7);
    expect(ledgerJson()['catsSeeded'], true);
  });

  testWidgets('主页算合计：支出总额、笔数、日均、最大单笔；收入只在有收入时显示',
      (tester) async {
    seed('a', amount: 12, date: '2026-09-19');
    seed('b', amount: 20, date: '2026-09-19');
    seed('c', amount: 100, date: '2026-09-01');
    // 上个月的不该算进来
    seed('d', amount: 999, date: '2026-08-31');

    await pumpLedger(tester);
    // 主页默认落在当前月，这里固定要看 2026-09
    await gotoMonth(tester, '2026-09');

    expect(find.byKey(const ValueKey('ledger-total')), findsOneWidget);
    // 12 + 20 + 100 = 132
    expect(find.text('¥132.00'), findsOneWidget);
    // 天数 2 → 日均 66
    expect(find.text('¥66.00'), findsOneWidget);
    // 最大单笔 100
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // 笔数
    // 全是支出 → 不显示收入行
    expect(find.textContaining('本月收入'), findsNothing);
  });

  testWidgets('收入单独汇总，且不拉高支出合计', (tester) async {
    seed('a', amount: 50, date: '2026-09-10');
    seed('b', amount: 3000, date: '2026-09-10', kind: ledgerKindIncome);

    await pumpLedgerAt(tester, '2026-09');

    // 支出只算支出（用合计卡的 key 断言，因为 ¥50.00 还会出现在日均等处）
    expect(
      tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('ledger-summary')),
        matching: find.byKey(const ValueKey('ledger-total')),
      )).data,
      '¥50.00',
    );
    expect(find.textContaining('本月收入 ¥3,000.00'), findsOneWidget);
    expect(find.text('笔数'), findsOneWidget);
  });

  testWidgets('列表按日期倒序分组，带当日小计和备注；收入显示成加号', (tester) async {
    seed('a', amount: 12, date: '2026-09-18', note: '食堂');
    seed('b', amount: 88, date: '2026-09-19', note: '');
    seed('c', amount: 500, date: '2026-09-19',
        kind: ledgerKindIncome, note: '兼职');

    await pumpLedgerAt(tester, '2026-09');

    expect(find.byKey(const ValueKey('ledger-day-2026-09-19')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-day-2026-09-18')), findsOneWidget);
    // 日期倒序：19 号那组在 18 号前面
    final y19 = tester.getTopLeft(find.byKey(const ValueKey('ledger-day-2026-09-19'))).dy;
    final y18 = tester.getTopLeft(find.byKey(const ValueKey('ledger-day-2026-09-18'))).dy;
    expect(y19 < y18, isTrue, reason: '新的日期要排在前面');
    expect(find.text('食堂'), findsOneWidget);
    // 09-19 当日支出 = 88（收入不算进「当日」支出）
    expect(find.text('当日 ¥88.00'), findsOneWidget);
    expect(find.text('+500.00'), findsOneWidget);
    expect(find.text('-88.00'), findsOneWidget);
  });

  testWidgets('记一笔：键盘输入金额 → 选分类 → 填备注 → 保存落盘', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);

    expect(find.byKey(const ValueKey('ledger-edit-body')), findsOneWidget);
    await typeAmount(tester, '32.5');
    await tester.enterText(find.byKey(const ValueKey('ledger-note')), '二分奶茶');
    await tester.tap(find.byKey(const ValueKey('ledger-cat-cat-drink')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();

    final recs = recordsJson();
    expect(recs.length, 1);
    expect((recs.first as Map)['amount'], 32.5);
    expect((recs.first as Map)['categoryId'], 'cat-drink');
    expect((recs.first as Map)['note'], '二分奶茶');
    expect((recs.first as Map)['kind'], 'expense');
    // 日期是今天（YYYY-MM-DD）
    expect(
      ((recs.first as Map)['date'] as String)
          .startsWith(DateTime.now().year.toString()),
      isTrue,
    );
    // 回到主页，能看到这笔
    expect(find.text('二分奶茶'), findsOneWidget);
  });

  testWidgets('金额为 0 时不让保存，提示要大于 0', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);

    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ledger-error')), findsOneWidget);
    expect(recordsJson(), isEmpty);
  });

  testWidgets('键盘：小数点只出一个、最多两位小数、清零', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);

    await typeAmount(tester, '1.2.3');
    expect(find.text('1.23'), findsOneWidget); // 第二个点被忽略

    await typeAmount(tester, '45');
    expect(find.text('1.23'), findsOneWidget); // 两位小数后不再进

    await tester.tap(find.byKey(const ValueKey('key-clear')));
    await tester.pump();
    // 清空后显示占位 0（键盘上也有个「0」键，所以按金额那个 key 断言）
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('ledger-amount'))).data,
      '0',
    );

    await typeAmount(tester, '7');
    await tester.tap(find.byKey(const ValueKey('key-00')));
    await tester.pump();
    expect(find.text('700'), findsOneWidget);
  });

  testWidgets('改一笔：点条目进编辑页，改金额后落盘', (tester) async {
    seed('a', amount: 12, date: '2026-09-19');

    await pumpLedgerAt(tester, '2026-09');

    await tester.tap(find.byKey(const ValueKey('ledger-record-a')));
    await tester.pumpAndSettle();
    expect(find.text('改一笔'), findsOneWidget);
    // 已有金额被塞回输入框（12 → 显示 12，不带 .00）
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('key-clear')));
    await tester.pump();
    await typeAmount(tester, '25');
    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();

    expect(recordsJson().length, 1);
    expect((recordsJson().first as Map)['amount'], 25);
    expect(find.text('-25.00'), findsOneWidget);
  });

  testWidgets('删一笔：长按确认后消失', (tester) async {
    seed('a', amount: 12, date: '2026-09-19');

    await pumpLedgerAt(tester, '2026-09');

    await tester.longPress(find.byKey(const ValueKey('ledger-record-a')));
    await tester.pumpAndSettle();
    expect(find.text('删除这笔账？'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('del-record-cancel')));
    await tester.pumpAndSettle();
    expect(recordsJson().length, 1); // 取消了，还在

    await tester.longPress(find.byKey(const ValueKey('ledger-record-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('del-record-ok')));
    await tester.pumpAndSettle();

    expect(recordsJson(), isEmpty);
    expect(find.byKey(const ValueKey('ledger-empty')), findsOneWidget);
  });

  testWidgets('分类管理：新建一个分类并落盘', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);

    await tester.tap(find.byKey(const ValueKey('ledger-manage-cats')));
    await tester.pumpAndSettle();
    expect(find.text('分类管理'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cat-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cat-name')), '水果');
    await tester.tap(find.byKey(const ValueKey('cat-icon-goods')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cat-submit')));
    await tester.pumpAndSettle();

    final cats = catsJson();
    expect(cats.length, 8);
    final added = cats.firstWhere((c) => (c as Map)['name'] == '水果') as Map;
    expect(added['icon'], 'goods');
    expect(added['id'], isNotEmpty);
  });

  testWidgets('分类名重复或超长会被拦住', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('ledger-manage-cats')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cat-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cat-name')), '餐饮');
    await tester.tap(find.byKey(const ValueKey('cat-submit')));
    await tester.pumpAndSettle();
    expect(find.text('已经有同名分类了'), findsOneWidget);
    expect(catsJson().length, 7); // 没建进去

    // 空名字也要拦
    await tester.enterText(find.byKey(const ValueKey('cat-name')), '   ');
    await tester.tap(find.byKey(const ValueKey('cat-submit')));
    await tester.pumpAndSettle();
    expect(find.text('分类名不能为空'), findsOneWidget);
    expect(catsJson().length, 7);
  });

  testWidgets('分类名输入框最多只让打 6 个字（超了打不进去）', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('ledger-manage-cats')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cat-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('cat-name')), '一二三四五六七');
    await tester.pumpAndSettle();

    // maxLength 会在输入层截到 6 个字，所以第 7 个字根本进不来
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('cat-name')))
          .controller!
          .text,
      '一二三四五六',
    );
  });

  testWidgets('删分类：有账时提示条数，删掉后账变成未分类但金额还在', (tester) async {
    seed('a', amount: 12, date: '2026-09-19', categoryId: 'cat-food');

    await pumpLedger(tester);
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('ledger-manage-cats')));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('cat-cat-food')));
    await tester.pumpAndSettle();
    expect(find.text('删除「餐饮」？'), findsOneWidget);
    expect(find.textContaining('还有 1 笔账'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('del-cat-ok')));
    await tester.pumpAndSettle();

    expect(catsJson().length, 6);
    expect(recordsJson().length, 1); // 账没跟着删
    expect((recordsJson().first as Map)['categoryId'], 'cat-food');
    // 回编辑页，那个分类格子没了，账对应不上 → 主页显示未分类
    await tester.tap(find.byKey(const ValueKey('cats-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    await gotoMonth(tester, '2026-09');
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('-12.00'), findsOneWidget);
  });

  testWidgets('删分类：被删的正是当前选中项时，自动改选第一个分类', (tester) async {
    await pumpLedger(tester);
    await openEditor(tester);

    // 默认选中第一个（餐饮），把它删掉
    await tester.tap(find.byKey(const ValueKey('ledger-manage-cats')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('cat-cat-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('del-cat-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cats-done')));
    await tester.pumpAndSettle();

    // 还能正常记账（选中项已换成奶茶饮料之类，不是空）
    await typeAmount(tester, '9');
    await tester.tap(find.byKey(const ValueKey('ledger-save')));
    await tester.pumpAndSettle();
    expect(recordsJson().length, 1);
  });

  testWidgets('在编辑页改了分类名，直接按返回键退出，主页也要跟着变', (tester) async {
    seed('a', amount: 12, date: '2026-09-19', categoryId: 'cat-food');

    await pumpLedgerAt(tester, '2026-09');
    expect(find.text('餐饮'), findsOneWidget);

    // 进编辑页 → 分类管理 → 把「餐饮」改名叫「饭堂」
    await tester.tap(find.byKey(const ValueKey('ledger-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ledger-manage-cats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cat-cat-food')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cat-name')), '饭堂');
    await tester.tap(find.byKey(const ValueKey('cat-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cats-done')));
    await tester.pumpAndSettle();

    // **按返回键**退出编辑页（不是点「完成」）——这是关键：
    // 早先主页只在「保存过」时才刷新，这样退出会挂着旧名字（v1.7.0 修的）
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();

    expect(find.text('饭堂'), findsOneWidget);
    expect(find.text('餐饮'), findsNothing);
  });

  testWidgets('切月份看的是那个月的数据', (tester) async {
    seed('a', amount: 12, date: '2026-09-19');
    seed('b', amount: 77, date: '2026-08-05');

    await pumpLedger(tester);
    await gotoMonth(tester, '2026-08');

    // 8 月那天在分组里
    expect(find.byKey(const ValueKey('ledger-day-2026-08-05')), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-day-2026-09-19')), findsNothing);

    // 再往前一个月是 7 月，空的
    await tester.tap(find.byKey(const ValueKey('ledger-prev-month')));
    await tester.pumpAndSettle();
    expect(find.text('2026年7月'), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger-empty')), findsOneWidget);

    // 回到 9 月，那笔又回来了
    await gotoMonth(tester, '2026-09');
    expect(find.byKey(const ValueKey('ledger-day-2026-09-19')), findsOneWidget);
  });

  testWidgets('记账数据打进备份 zip，还原时能回来', (tester) async {
    seed('a', amount: 66, date: '2026-09-19', note: '备份我');

    final bytes = buildBackupZip(store);
    // 换一个干净目录还原
    final tmp2 = Directory.systemTemp.createTempSync('myday-ledger-restore-');
    addTearDown(() {
      if (tmp2.existsSync()) tmp2.deleteSync(recursive: true);
    });
    final store2 = Store(tmp2)..init();
    final res = restoreBackup(store2, bytes);
    expect((res['restored'] as List).contains('ledger.json'), isTrue);

    final back = store2.ledger();
    expect(back.records.length, 1);
    expect(back.records.first.amount, 66);
    expect(back.records.first.note, '备份我');
    // 分类也在
    expect(back.categories.length, 7);
  });
}
