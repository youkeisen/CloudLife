// 界面骨架的测试：底部 Tab 能切换，每页都有该有的空态文案。
// v1.3.0 起底部栏改成「首页 / 功能 / 设置」三个入口 + 中间凸起「＋」，
// 课程、天气、备忘录收进「功能」页里。
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
    expect(find.text('还没有任何节次'), findsOneWidget);
    expect(find.text('还没选城市'), findsOneWidget);
    expect(find.text('还没有备忘录'), findsOneWidget);
  });

  testWidgets('设了第 1 周周一，顶栏显示第几教学周', (tester) async {
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

  testWidgets('三个入口依次能切：首页 / 功能 / 设置', (tester) async {
    await pumpApp(tester);

    // 功能页：课程 / 天气 / 备忘录三张卡
    await tester.tap(find.text('功能').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-features')), findsOneWidget);
    expect(find.text('课程'), findsOneWidget);
    expect(find.text('天气'), findsOneWidget);
    expect(find.text('备忘录'), findsOneWidget);

    // 设置页
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-settings')), findsOneWidget);
    expect(find.text('基本'), findsOneWidget);

    // 回首页
    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-home')), findsOneWidget);
    expect(find.text('还没有任何节次'), findsOneWidget);
  });

  testWidgets('功能页点「课程」进入课程页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('功能').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-courses')), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget);
  });

  testWidgets('底栏中间的「＋」新建备忘录并进编辑页', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-quick-add')));
    await tester.pumpAndSettle();
    expect(find.text('编辑笔记'), findsOneWidget,
        reason: '＋ 是快速新建备忘录，直接进编辑页');
    // 落盘了
    expect(store.notes().notes, hasLength(1));
  });

  testWidgets('设置页改了第 1 周周一，顶栏教学周圆牌立刻跟上（M7）', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('week-pill-off')), findsOneWidget);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('s-week1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

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
    expect(light.scaffoldBackgroundColor, Colors.transparent);
    expect(dark.scaffoldBackgroundColor, Colors.transparent);
    expect(light.cardTheme.color, isNot(dark.cardTheme.color),
        reason: '玻璃染色的深浅要跟主题走');
    expect(light.dialogTheme.backgroundColor, isNot(dark.dialogTheme.backgroundColor));
  });
}
