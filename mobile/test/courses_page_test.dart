// 课程页的测试：渲染、增删改、清空本周、整周复制、周次切换、没节次的引导。
// 全部用临时目录 + 虚构数据，不需要真机。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/ui/courses_page.dart';

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-courses-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void addPeriods() {
    final s = store.settings();
    s.periods = <Period>[
      Period(id: 'p1', label: '第1节', start: '08:10', end: '08:50'),
      Period(id: 'p2', label: '第2节', start: '09:00', end: '09:40'),
      Period(id: 'p3', label: '第3节', start: '10:00', end: '10:40'),
    ];
    store.saveSettings(s);
  }

  void addLesson(Lesson l, {int week = 1}) {
    final list = store.listWeek(week)..add(l);
    store.saveWeek(week, list);
  }

  Lesson lesson(String id, {int day = 1, String slot = 'p1', String spanEnd = '',
      String name = '课', String location = ''}) {
    return Lesson(
      id: id, day: day, slot: slot, spanEnd: spanEnd,
      name: name, location: location,
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CoursesPage(store: store)),
    ));
    await tester.pumpAndSettle();
  }

  /// SnackBar 有自动关闭的定时器，测试结束前必须把时间推过去，否则报 pending timer。
  Future<void> pastToast(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
  }

  testWidgets('没设节次时显示引导', (tester) async {
    await pumpPage(tester);
    expect(find.text('还没有任何节次'), findsOneWidget);
    expect(find.textContaining('作息与节次'), findsOneWidget,
        reason: '要告诉用户去哪里加节次');
  });

  testWidgets('长按复制 / 粘贴（v1.4.2）', (tester) async {
    addPeriods();
    addLesson(lesson('l1', name: '高等数学', location: 'A101'));
    await pumpPage(tester);

    // 长按有课的格子 → 复制
    await tester.longPress(find.byKey(const ValueKey('lesson-l1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已复制「高等数学」'), findsOneWidget);
    await pastToast(tester);

    // 长按空格子（周三 p1）→ 粘贴成单节
    await tester.longPress(find.byKey(const ValueKey('cell-3-p1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已粘贴「高等数学」'), findsOneWidget);
    final lessons = store.listWeek(1);
    expect(lessons.length, 2);
    final pasted = lessons.firstWhere((l) => l.id != 'l1');
    expect(pasted.day, 3);
    expect(pasted.slot, 'p1');
    expect(pasted.spanEnd, '', reason: '粘贴只贴单节，不带走跨节次');
    expect(pasted.name, '高等数学');
    expect(pasted.location, 'A101');
    await pastToast(tester);

    // 长按空格子（周四 p1，剪贴板已有内容）→ 再贴一份，id 不重复
    await tester.longPress(find.byKey(const ValueKey('cell-4-p1')));
    await tester.pumpAndSettle();
    final list2 = store.listWeek(1);
    expect(list2.length, 3);
    expect(list2.map((l) => l.id).toSet().length, 3);
    await pastToast(tester);
  });

  testWidgets('渲染课表：课块内容齐全，跨节次的格子被跳过', (tester) async {
    addPeriods();
    addLesson(lesson('l1', name: '高等数学', location: 'A101'));
    addLesson(lesson('l2', day: 2, slot: 'p2', spanEnd: 'p3',
        name: '大学英语', location: 'B202'));
    await pumpPage(tester);

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('A101'), findsOneWidget);
    expect(find.text('大学英语'), findsOneWidget);
    expect(find.text('第1节'), findsWidgets, reason: '节次列和课块里都会出现节次名');
    expect(find.text('08:10 - 08:50'), findsOneWidget);
    expect(find.byKey(const ValueKey('lesson-l2')), findsOneWidget);
    // l2 跨第 2-3 节：第 2 天第 3 节的空格子不应该出现（被跨节次的课块盖住）
    expect(find.byKey(const ValueKey('cell-2-p3')), findsNothing);
  });

  testWidgets('点课块打开编辑，改名能存回去', (tester) async {
    addPeriods();
    addLesson(lesson('l1', name: '高等数学', location: 'A101'));
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('lesson-l1')));
    await tester.pumpAndSettle();
    expect(find.text('编辑课程'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '高等数学（下）');
    await tester.tap(find.byKey(const ValueKey('btn-save-course')));
    await pastToast(tester);

    final got = store.listWeek(1);
    expect(got.single.name, '高等数学（下）');
    expect(got.single.id, 'l1', reason: '编辑是改原课，不是新建');
  });

  testWidgets('添加课程：空名被拦下，填了名字才进库', (tester) async {
    addPeriods();
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('btn-add-course')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('btn-save-course')), findsOneWidget);

    // 空名字直接点保存：要报错、面板不能关
    await tester.tap(find.byKey(const ValueKey('btn-save-course')));
    await tester.pumpAndSettle();
    expect(find.text('课程名不能为空'), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-save-course')), findsOneWidget,
        reason: '校验不过时面板不能关闭');

    await tester.enterText(find.byType(TextField).first, '大学物理');
    await tester.tap(find.byKey(const ValueKey('btn-save-course')));
    await pastToast(tester);

    final got = store.listWeek(1);
    expect(got.single.name, '大学物理');
    expect(got.single.id, isNot(''), reason: '新课程要有 id');
    expect(got.single.slot, 'p1', reason: '默认落在第一个节次');
  });

  testWidgets('编辑面板里能删课', (tester) async {
    addPeriods();
    addLesson(lesson('l1', name: '高等数学'));
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('lesson-l1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('btn-del-course')));
    await pastToast(tester);

    expect(store.listWeek(1), isEmpty);
  });

  testWidgets('清空本周：清完这周的键还在（和电脑版 save_week 语义一致）', (tester) async {
    addPeriods();
    addLesson(lesson('l1', name: '高等数学'));
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('btn-clear-week')));
    await tester.pumpAndSettle();
    expect(find.text('会删掉这一周的全部课程，不可撤销。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('btn-confirm-clear')));
    await pastToast(tester);

    final courses = store.courses();
    expect(courses.week(1), isEmpty);
    expect(courses.weeks.containsKey(1), isTrue, reason: '空周保留键');
  });

  testWidgets('整周复制：默认选中下一周，覆盖后目标周换上新 id 的课', (tester) async {
    addPeriods();
    addLesson(lesson('src', name: '高等数学'));
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('btn-copy-week')));
    await tester.pumpAndSettle();
    expect(find.text('复制第 1 周的课表'), findsOneWidget);
    // 不动任何选择，直接开始复制（默认已选第 2 周）
    await tester.tap(find.byKey(const ValueKey('btn-do-copy')));
    await pastToast(tester);

    final src = store.listWeek(1);
    final dst = store.listWeek(2);
    expect(dst.length, 1);
    expect(dst.single.name, '高等数学');
    expect(dst.single.id, isNot('src'), reason: '复制过去的课必须换新 id');
    expect(src.single.id, 'src', reason: '来源周不动');
  });

  testWidgets('周次切换：切到第 2 周看到第 2 周的课', (tester) async {
    addPeriods();
    addLesson(lesson('l1', name: '高等数学'));
    addLesson(lesson('l2', name: '电路基础'), week: 2);
    await pumpPage(tester);

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('电路基础'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('week-sel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 2 周').last);
    await tester.pumpAndSettle();

    expect(find.text('电路基础'), findsOneWidget);
    expect(find.text('高等数学'), findsNothing);
  });

  testWidgets('设了第 1 周周一，切走后「回到今天」能切回来', (tester) async {
    addPeriods();
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    String pad(int n) => n < 10 ? '0$n' : '$n';
    final s = store.settings()
      ..week1Monday = '${monday.year}-${pad(monday.month)}-${pad(monday.day)}';
    store.saveSettings(s);
    await pumpPage(tester); // initState 直接落在今天所在的第 1 周

    await tester.tap(find.byKey(const ValueKey('week-sel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 3 周').last);
    await tester.pumpAndSettle();
    expect(find.text('第 3 周'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('btn-today')));
    await tester.pumpAndSettle();
    expect(find.text('第 3 周'), findsNothing, reason: '切走后不该还停在第 3 周');
    expect(find.text('第 1 周'), findsOneWidget, reason: '回到今天后周次切回第 1 周');
  });

  testWidgets('没设第 1 周周一时，「回到今天」要提示', (tester) async {
    addPeriods();
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('btn-today')));
    await tester.pumpAndSettle();
    expect(find.text('还没设置第 1 周周一，去设置页填一下'), findsOneWidget);
    await pastToast(tester);
  });

  testWidgets('没节次时点「添加课程」弹出引导对话框', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('btn-add-course')));
    await tester.pumpAndSettle();
    expect(find.text('还不能添加课程'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });
}
