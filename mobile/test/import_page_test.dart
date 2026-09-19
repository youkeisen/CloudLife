// 课程页「导入课表」入口的测试：选文件 → 预览确认 → 落库。
// 文件选择器靠注入，不真的弹系统选框。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/ui/courses_page.dart';

const String xmlNs =
    'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';

List<int> smallTimetableXlsx() {
  const content =
      '<sst $xmlNs><si><t>节次</t></si><si><t>星期一</t></si><si><t>导入的课(考试)软件技术2501{1-2周 王老师 A-101}</t></si></sst>';
  final sheetXml = '<worksheet $xmlNs><sheetData>'
      '<row r="1"><c r="B1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
      '<row r="2"><c r="B2" t="inlineStr"><is><t>1</t></is></c>'
      '<c r="C2" t="s"><v>2</v></c></row>'
      '</sheetData></worksheet>';
  final workbook =
      '<workbook $xmlNs><sheets><sheet name="课表" sheetId="1"/></sheets></workbook>';
  final archive = Archive()
    ..addFile(ArchiveFile(
        'xl/workbook.xml', utf8.encode(workbook).length, utf8.encode(workbook)))
    ..addFile(ArchiveFile('xl/worksheets/sheet1.xml', utf8.encode(sheetXml).length,
        utf8.encode(sheetXml)))
    ..addFile(ArchiveFile(
        'xl/sharedStrings.xml', utf8.encode(content).length, utf8.encode(content)));
  return ZipEncoder().encode(archive)!;
}

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-import-page-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pastToast(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
  }

  testWidgets('导入流程：选文件 → 确认覆盖 → 课表出现', (tester) async {
    final bytes = smallTimetableXlsx();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CoursesPage(
          store: store,
          pickTimetable: () async => bytes,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn-import')));
    await tester.pumpAndSettle();
    expect(find.text('确认导入课表'), findsOneWidget);
    expect(find.textContaining('1 门课'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-overwrite')));
    await tester.pumpAndSettle();

    // 落库：第 1、2 周各有两节连堂，节次也建出来了
    final week1 = store.listWeek(1);
    expect(week1, hasLength(1));
    expect(week1.single.name, '导入的课');
    // 只会建「被课程用到」的节次：这张表只有一个节次，所以不会建出第 2 节
    expect(store.settings().periods.map((p) => p.label), <String>['第 1 节']);
    expect(find.textContaining('导入完成'), findsOneWidget);
    await pastToast(tester);
  });

  testWidgets('取消导入：数据不动', (tester) async {
    final bytes = smallTimetableXlsx();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CoursesPage(
          store: store,
          pickTimetable: () async => bytes,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-cancel')));
    await tester.pumpAndSettle();

    expect(store.courses().weeks, isEmpty, reason: '取消就一个字都不写');
    expect(store.settings().periods, isEmpty);
  });

  testWidgets('选了个不是 xlsx 的文件：提示原因，数据不动', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CoursesPage(
          store: store,
          pickTimetable: () async => utf8.encode('这不是压缩包'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('btn-import')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不是 xlsx'), findsOneWidget);
    expect(store.courses().weeks, isEmpty);
    await pastToast(tester);
  });
}
