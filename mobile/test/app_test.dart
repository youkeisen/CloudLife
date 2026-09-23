// 界面骨架的测试：底部 Tab 能切换，每页都有该有的空态文案。
// v1.3.0 起底部栏改成「首页 / 功能 / 设置」三个入口 + 中间凸起「＋」，
// 课程、天气、备忘录收进「功能」页里。
// 数据层不真跑（用临时目录），所以这个测试不需要真机。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/app.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/ui/design.dart';

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

  testWidgets('功能页「快捷操作 → 记一笔」进去只有一个顶栏', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('功能').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();

    // 记账编辑页自带 Scaffold + 「记一笔 / 完成」顶栏，
    // 外面再包一层带 AppBar 的 Scaffold 就会出现两个顶栏
    // （凯森 v2.1.2 反馈的截图就是这个）。
    expect(find.byType(AppBar), findsOneWidget,
        reason: '双层 Scaffold 会出两个顶栏');
    expect(find.text('记一笔'), findsOneWidget);
    // 顶栏右侧的「完成」：键盘上也有一个「完成」键，所以这里只要求至少一个
    expect(find.text('完成'), findsWidgets);
  });

  testWidgets('底栏没有凸起的加号（v1.3.2 应凯森要求去掉）', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('tab-quick-add')), findsNothing);
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
    // v1.6.0 起界面中文化，日期选择器的按钮变成「确定」
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('week-pill')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-pill-off')), findsNothing);
    // v2.0：周次胶囊是个自绘组件（WeekChip），断言它里面的文案。
    // 用正则而不是写死「第 1 教学周」：日期选择器里点的那个「1」不一定落在本周。
    final pillTexts = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('week-pill')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(
      pillTexts.any((t) => RegExp(r'^第 \d+ 教学周$').hasMatch(t)),
      isTrue,
      reason: '胶囊文案应是「第 N 教学周」，实际：$pillTexts',
    );
  });

  test('深浅色两套主题都能构建，配色跟主题走（v2.0 令牌）', () {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);

    // 底色是**不透明实色**（不再是 transparent + 每页自己垫背景）：
    // 这条守着「任何 Scaffold 都自带底色」，独立整页不会再有黑屏。
    expect(light.scaffoldBackgroundColor, Tone.light.bg);
    expect(dark.scaffoldBackgroundColor, Tone.dark.bg);
    expect(light.scaffoldBackgroundColor.a, 1.0,
        reason: '底色必须不透明，否则独立整页会露出路由遮罩的黑底');
    expect(dark.scaffoldBackgroundColor.a, 1.0);

    expect(light.cardTheme.color, Tone.light.surface);
    expect(dark.cardTheme.color, Tone.dark.surface);

    // 主色是靛蓝，深浅色各一档（v2.0 换掉了刺眼的纯蓝）。
    expect(light.colorScheme.primary, Tone.light.primary);
    expect(dark.colorScheme.primary, Tone.dark.primary);

    // 深色模式背景不用纯黑。
    expect(Tone.dark.bg, isNot(const Color(0xFF000000)),
        reason: '深色底用 #131720，纯黑太硬');

    // 层级靠极浅阴影 + 1px 边框，不用 Material 的 elevation。
    expect(light.cardTheme.elevation, 0);
    expect(dark.cardTheme.elevation, 0);
  });
}
