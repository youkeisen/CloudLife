// 课表导入（M8）的测试：xlsx 解析、单元格内容拆分、按周落库。
// 测试里用 archive 包现场拼一个 xlsx（它本来就是 zip），不用任何真实课表。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/import_logic.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/timetable.dart';

const String xmlNs =
    'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';

/// 用共享字符串 + 单元格引用拼一张最小可用的 xlsx。
List<int> buildXlsx({
  required Map<int, String> shared,
  required Map<String, dynamic> cells,
  List<String> merges = const <String>[],
  String inline = '',
}) {
  final si = shared.entries
      .map((e) => '<si><t>${e.value}</t></si>')
      .join('');
  final sst = '<sst $xmlNs count="${shared.length}" uniqueCount="${shared.length}">$si</sst>';

  // 按行组装单元格
  final byRow = <int, List<String>>{};
  cells.forEach((ref, value) {
    final row = int.parse(RegExp(r'\d+').firstMatch(ref)!.group(0)!);
    byRow.putIfAbsent(row, () => <String>[]);
    if (value is int) {
      byRow[row]!.add('<c r="$ref" t="s"><v>$value</v></c>');
    } else {
      byRow[row]!.add('<c r="$ref" t="inlineStr"><is><t>$value</t></is></c>');
    }
  });
  final rowsXml = byRow.entries.map((e) {
    return '<row r="${e.key}">${e.value.join()}</row>';
  }).join();
  final mergeXml = merges.isEmpty
      ? ''
      : '<mergeCells count="${merges.length}">'
          '${merges.map((m) => '<mergeCell ref="$m"/>').join()}'
          '</mergeCells>';
  final sheetXml = '<worksheet $xmlNs><sheetData>$rowsXml</sheetData>$mergeXml</worksheet>';
  final workbook = '<workbook $xmlNs><sheets><sheet name="学生课表" sheetId="1"/></sheets></workbook>';

  final archive = Archive()
    ..addFile(_file('xl/workbook.xml', workbook))
    ..addFile(_file('xl/worksheets/sheet1.xml', sheetXml))
    ..addFile(_file('xl/sharedStrings.xml', sst));
  if (inline.isNotEmpty) {
    archive.addFile(_file('xl/worksheets/sheet2.xml', inline));
  }
  return ZipEncoder().encode(archive)!;
}

ArchiveFile _file(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}

/// 一张两节连堂的课表：
///   行3 = 表头（时间|节次|周一…周五）
///   行4/5 = 第 1、2 节；C4:C5 纵向合并（周一两节连堂）
///   行6 = 第 3 节
List<int> sampleXlsx({bool duplicateMergedValue = false}) {
  final shared = <int, String>{
    0: '2026-2027学年第一学期课程表',
    1: '学号：000000 姓名：测试同学',
    2: '时间',
    3: '节次',
    4: '星期一',
    5: '星期二',
    6: '星期三',
    7: '星期四',
    8: '星期五',
    9: '示例课程(考试)(必修课)软件技术2501{4-17周 王老师 A-101}',
    10: '另一门课(考查)软件技术2502{5-8周 李老师 B-202}',
    11: '没周次的课',
    12: '软件技术2501{1-10单周 赵老师 C-303}',
    13: '理论课(考试)软件技术2501{1,3,5周 钱老师 D-404}',
  };
  return buildXlsx(
    shared: shared,
    cells: <String, dynamic>{
      'A1': 0,
      'B2': 1,
      'A3': 2, 'B3': 3, 'C3': 4, 'D3': 5, 'E3': 6, 'F3': 7, 'G3': 8,
      'B4': '1', 'C4': 9, 'D4': 10, 'E4': 13,
      if (duplicateMergedValue) 'C5': 9,
      'B5': '2',
      'B6': '3', 'F6': 12,
    },
    merges: const <String>['C4:C5'],
  );
}

void main() {
  group('xlsx 基础读取', () {
    test('不是 zip 就报错', () {
      expect(
        () => readXlsx(utf8.encode('这不是一个压缩包')),
        throwsA(isA<TimetableError>().having(
            (e) => e.message, 'message', contains('不是 xlsx'))),
      );
    });

    test('空内容报错', () {
      expect(() => readXlsx(<int>[]),
          throwsA(isA<TimetableError>().having((e) => e.message, 'message', contains('文件内容'))));
    });

    test('读第一张表、共享字符串、合并单元格', () {
      final book = readXlsx(sampleXlsx());
      expect(book.sheet, '学生课表');
      expect(book.cells[(1, 1)], '2026-2027学年第一学期课程表');
      expect(book.maxRow, 6);
      expect(book.merges, <(int, int, int, int)>[(4, 3, 5, 3)]);
    });
  });

  group('单元格内容拆分', () {
    test('课程名 + 班级 + 周次 + 老师 + 教室', () {
      final one = parseCourseLine('示例课程(考试)(必修课)软件技术2501{4-17周 王老师 A-101}')!;
      expect(one.name, '示例课程');
      expect(one.className, '软件技术2501');
      expect(one.weekText, '4-17周');
      expect(one.weeks, List<int>.generate(14, (i) => i + 4));
      expect(one.teacher, '王老师');
      expect(one.room, 'A-101');
    });

    test('括号里的标注要剥干净', () {
      expect(stripTailTags('示例课程(考试)(必修课)'), '示例课程');
      expect(stripTailTags('示例课程(考查)'), '示例课程');
      expect(stripTailTags('体育(考试)(俱乐部)'), '体育(考试)(俱乐部)',
          reason: '不在标注词表里的括号不能乱剥');
    });

    test('课程名和班级之间没有括号时也能拆', () {
      final (name, className) = splitClass('大学语文软件技术2501');
      expect(name, '大学语文');
      expect(className, '软件技术2501');
    });

    test('周次：区间 / 列表 / 单双周', () {
      expect(parseWeeks('4-17周'), List<int>.generate(14, (i) => i + 4));
      expect(parseWeeks('1,3,5周'), <int>[1, 3, 5]);
      expect(parseWeeks('1-10单周'), List<int>.generate(5, (i) => i * 2 + 1));
      expect(parseWeeks('2-10双周'), List<int>.generate(5, (i) => i * 2 + 2));
      expect(parseWeeks('17-4周'), List<int>.generate(14, (i) => i + 4),
          reason: '写反了也要能救回来');
      expect(parseWeeks('第3-5周'), <int>[3, 4, 5]);
      expect(parseWeeks('40-50周'), isEmpty, reason: '超过 30 周的按垃圾数据丢掉');
      expect(parseWeeks(''), isEmpty);
    });

    test('节次名：纯数字加「第 节」，别的原样保留', () {
      expect(periodLabelText('1'), '第 1 节');
      expect(periodLabelText('12'), '第 12 节');
      expect(periodLabelText('中午1'), '中午1');
    });
  });

  group('整张表解析', () {
    test('认出表头、标题、学生行，课程铺出来', () {
      final parsed = parseTimetable(sampleXlsx());
      expect(parsed.title, contains('课程表'));
      expect(parsed.student, contains('学号'));
      expect(parsed.courses, hasLength(4));

      final mon = parsed.courses.firstWhere((c) => c.day == 1);
      expect(mon.periodFrom, '1');
      expect(mon.periodTo, '2', reason: 'C4:C5 合并 = 第 1-2 节连堂');
      expect(mon.name, '示例课程');
      expect(mon.weeks, List<int>.generate(14, (i) => i + 4));

      final tue = parsed.courses.firstWhere((c) => c.day == 2);
      expect(tue.name, '另一门课');
      expect(tue.weeks, <int>[5, 6, 7, 8]);

      final thu = parsed.courses.firstWhere((c) => c.day == 4);
      expect(thu.periodFrom, '3');
      expect(thu.periodTo, '3');
      expect(thu.name, '软件技术2501', reason: '没有括号时也能把课程名和班级拆开');

      expect(parsed.warnings, isEmpty);
      expect(periodLabels(parsed), <String>['1', '2', '3']);
      expect(totalLessons(parsed), 14 + 4 + 3 + 5);
    });

    test('合并区每个格子都存了同一份值时，不重复算课', () {
      final parsed = parseTimetable(sampleXlsx(duplicateMergedValue: true));
      expect(parsed.courses.where((c) => c.day == 1), hasLength(1),
          reason: '合并区被盖住的格子不能再读一遍');
    });

    test('一格两门课（换行分隔）', () {
      final xlsx = buildXlsx(
        shared: <int, String>{
          0: '节次', 1: '星期一',
        },
        cells: <String, dynamic>{
          'B1': 0, 'C1': 1,
          'B2': '1',
          'C2': '上午课(考试)软件技术2501{1-4周 王老师 A-101}\n'
              '下午课(考查)软件技术2502{5-8周 李老师 B-202}',
        },
      );
      final parsed = parseTimetable(xlsx);
      expect(parsed.courses, hasLength(2));
      expect(parsed.courses.map((c) => c.name), <String>['上午课', '下午课']);
    });

    test('没写周次的课跳过并给警告', () {
      final xlsx = buildXlsx(
        shared: <int, String>{
          0: '节次', 1: '星期一',
        },
        cells: <String, dynamic>{
          'B1': 0, 'C1': 1,
          'B2': '1',
          'C2': '没周次的课\n上午课(考试)软件技术2501{1-4周 王老师 A-101}',
        },
      );
      final parsed = parseTimetable(xlsx);
      expect(parsed.courses, hasLength(1), reason: '只有写周次的那门课算数');
      expect(parsed.warnings, hasLength(1));
      expect(parsed.warnings.single, contains('没写周次'));
    });

    test('整张表一门带周次的课都没有就报错', () {
      final xlsx = buildXlsx(
        shared: <int, String>{
          0: '节次', 1: '星期一', 2: '没周次的课',
        },
        cells: <String, dynamic>{'B1': 0, 'C1': 1, 'B2': '1', 'C2': 2},
      );
      expect(
        () => parseTimetable(xlsx),
        throwsA(isA<TimetableError>()
            .having((e) => e.message, 'message', contains('带周次的课程'))),
      );
    });

    test('不是课表就报错', () {
      final xlsx = buildXlsx(
        shared: <int, String>{0: '随便一个表格', 1: 'A', 2: 'B'},
        cells: <String, dynamic>{'A1': 0, 'A2': 1, 'A3': 2},
      );
      expect(
        () => parseTimetable(xlsx),
        throwsA(isA<TimetableError>()
            .having((e) => e.message, 'message', contains('表头'))),
      );
    });

    test('空表报错', () {
      final xlsx = buildXlsx(shared: <int, String>{}, cells: <String, dynamic>{});
      expect(() => parseTimetable(xlsx), throwsA(isA<TimetableError>()));
    });
  });

  group('导入落库', () {
    late Directory tmp;
    late Store store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('myday-import-test-');
      store = Store(tmp)..init();
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('预览不落盘', () {
      final before = store.settings().periods.length;
      final plan = buildImportPlan(sampleXlsx(), store.settings());
      expect(plan.courseCount, 4);
      expect(plan.totalLessons, 26);
      expect(plan.weeks, <int>[1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);
      expect(plan.newPeriods, <String>['第 1 节', '第 2 节', '第 3 节']);
      expect(plan.reusePeriods, isEmpty);
      expect(store.settings().periods.length, before, reason: '预览不该建节次');
      expect(store.courses().weeks, isEmpty, reason: '预览不该写课程');
    });

    test('导入：建节次、按周写课、spanEnd 对上、先留备份', () {
      final parsed = parseTimetable(sampleXlsx());
      final plan = buildImportPlan(sampleXlsx(), store.settings());
      final result = applyImport(store, plan, parsed, 'overwrite');

      expect(result.added, 26, reason: '14 + 4 + 3 + 5 个「课 × 周」');
      expect(result.weeks, <int>[1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);

      // 节次补齐且时间留空
      final periods = store.settings().periods;
      expect(periods.map((p) => p.label), containsAll(<String>['第 1 节', '第 2 节', '第 3 节']));
      expect(periods.where((p) => p.label == '第 1 节').single.start, '', reason: '导入不替用户猜作息');

      // 连堂课的 spanEnd（用第 5 周：四门课都在）
      final week5 = store.listWeek(5);
      final mon = week5.firstWhere((l) => l.day == 1);
      final first = periods.firstWhere((p) => p.label == '第 1 节');
      final second = periods.firstWhere((p) => p.label == '第 2 节');
      expect(mon.slot, first.id);
      expect(mon.spanEnd, second.id);
      expect(mon.note, contains('软件技术2501'));
      expect(mon.location, 'A-101');

      // 单双周
      final thu = week5.firstWhere((l) => l.day == 4);
      expect(thu.note, contains('单周'), reason: '单周课的备注里带着周次原文');
      expect(week5.where((l) => l.day == 4), hasLength(1), reason: '第 5 周是单周');

      // 备份留了
      final backups = Directory('${tmp.path}${Platform.pathSeparator}backups');
      expect(backups.existsSync(), isTrue, reason: '导入前要自动留一份');
    });

    test('merge 追加不覆盖，overwrite 覆盖整周', () {
      final parsed = parseTimetable(sampleXlsx());
      final plan = buildImportPlan(sampleXlsx(), store.settings());
      store.saveWeek(4, <Lesson>[Lesson(id: 'old', day: 5, slot: 'p1', name: '手工加的')]);

      applyImport(store, plan, parsed, 'merge');
      final merged = store.listWeek(4);
      expect(merged.where((l) => l.name == '手工加的'), hasLength(1),
          reason: 'merge 不该把原有的课冲掉');
      final before = merged.length;

      applyImport(store, plan, parsed, 'overwrite');
      final overwritten = store.listWeek(4);
      expect(overwritten.where((l) => l.name == '手工加的'), isEmpty,
          reason: 'overwrite 就是整周换掉');
      expect(overwritten.length, lessThan(before));
    });

    test('节次同名复用，不重复建', () {
      final s = store.settings()
        ..periods = <Period>[Period(id: 'p9', label: '第 1 节', start: '08:10', end: '08:55')];
      store.saveSettings(s);
      final plan = buildImportPlan(sampleXlsx(), store.settings());
      expect(plan.reusePeriods, contains('第 1 节'));

      final (mapping, created) = ensurePeriods(store, plan.periodLabels);
      expect(mapping['第 1 节'], 'p9', reason: '同名节次直接复用');
      expect(created.map((p) => p.label), <String>['第 2 节', '第 3 节']);
      expect(store.settings().periods.where((p) => p.label == '第 1 节'), hasLength(1));
    });
  });
}
