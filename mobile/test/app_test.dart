// 界面骨架的测试：五个底部 Tab 能切换，每页都有该有的空态文案。
// 数据层不真跑（用临时目录），所以这个测试不需要真机。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/app.dart';
import 'package:my_day_phone/store.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-shell-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MyDayApp(store: store));
    await tester.pumpAndSettle();
  }

  testWidgets('默认落在首页，顶栏显示教学周', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('page-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-pill-off')), findsOneWidget,
        reason: '没设第 1 周周一时要提示「教学周未设置」');
    // M6 起首页是真页面：空数据下三个区块各有自己的空态
    expect(find.text('还没有任何节次'), findsOneWidget);
    expect(find.text('还没选城市'), findsOneWidget);
    expect(find.text('还没有备忘录'), findsOneWidget);
  });

  testWidgets('设了第 1 周周一，顶栏显示第几教学周', (tester) async {
    // 用「本周的周一」当第 1 周周一，今天必然落在第 1 周，期望值就与日期无关
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    String pad(int n) => n < 10 ? '0$n' : '$n';
    final iso = '${monday.year}-${pad(monday.month)}-${pad(monday.day)}';

    final s = store.settings()..week1Monday = iso;
    store.saveSettings(s);
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('week-pill')), findsOneWidget);
    expect(find.text('第 1 教学周'), findsOneWidget);
  });

  testWidgets('五个 Tab 依次能切', (tester) async {
    await pumpApp(tester);

    final cases = <String, String>{
      // 课程页（M3）/ 备忘录页（M4）/ 天气页（M5）/ 首页（M6）/ 设置页（M7）都是真页面了
      '天气': '先选一个城市',
      '备忘录': '这里还没有东西',
      '设置': '基本',
      '首页': '还没有任何节次',
    };
    for (final entry in cases.entries) {
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey<String>('page-${_pageKey(entry.key)}')), findsOneWidget,
          reason: '切到「${entry.key}」后应该显示它的空态');
      expect(find.text(entry.value), findsOneWidget);
    }
    // 课程 Tab：真页面，要有添加课程按钮
    await tester.tap(find.text('课程').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-courses')), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget);
    // 备忘录 Tab：真页面，要有新建按钮
    await tester.tap(find.text('备忘录').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-notes')), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-new-note')), findsOneWidget);
  });

  testWidgets('设置页改了第 1 周周一，顶栏教学周圆牌立刻跟上（M7）', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('week-pill-off')), findsOneWidget);

    // 进设置页选日期：日历选 1 日并确认
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('s-week1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // 顶栏跟着变：本周的周一必然 >= 所选日期，圆牌应显示「第 N 教学周」
    expect(find.byKey(const ValueKey('week-pill')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-pill-off')), findsNothing);
    final pill = tester.widget<Container>(find.byKey(const ValueKey('week-pill')));
    final pillText = ((pill.child as Text?)!.data)!;
    expect(RegExp(r'^第 \d+ 教学周$').hasMatch(pillText), isTrue,
        reason: '圆牌文案应是「第 N 教学周」，实际：$pillText');
  });

  test('深浅色两套主题都能构建，玻璃染色自适应', () {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    // Liquid Glass：壳子透明，颜色来自底下的渐变背景
    expect(light.scaffoldBackgroundColor, Colors.transparent);
    expect(dark.scaffoldBackgroundColor, Colors.transparent);
    expect(light.cardTheme.color, isNot(dark.cardTheme.color),
        reason: '玻璃染色的深浅要跟主题走');
    expect(light.dialogTheme.backgroundColor, isNot(dark.dialogTheme.backgroundColor));
  });
}

String _pageKey(String label) {
  switch (label) {
    case '首页':
      return 'home';
    case '课程':
      return 'courses';
    case '天气':
      return 'weather';
    case '备忘录':
      return 'notes';
    case '设置':
      return 'settings';
  }
  throw ArgumentError(label);
}
