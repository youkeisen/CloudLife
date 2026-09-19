// 课表 PDF 解析的手动验证工具（不依赖任何真实数据文件）。
// 用法：$env:MYDAY_PDF='<pdf路径>'; flutter test tool/pdf_check_test.dart
// 会打印解析出的课程明细，用来人工核对；不设置 MYDAY_PDF 时自动跳过。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/pdf_timetable.dart';
import 'package:my_day_phone/timetable.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  final path = Platform.environment['MYDAY_PDF'];
  if (path == null || !File(path).existsSync()) {
    test('跳过（未设置 MYDAY_PDF 环境变量）', () {
      markTestSkipped('设置 MYDAY_PDF 环境变量后再跑这个验证');
    });
    return;
  }

    test('解析课表 PDF：$path', () {
    final parsed = parsePdfTimetable(File(path).readAsBytesSync());
    final out = StringBuffer();
    out.writeln('课程块数: ${parsed.courses.length}');
    out.writeln('节次行: ${parsed.periodRows.join(" ")}');
    out.writeln('周次覆盖: ${weekSpan(parsed).join(",")}');
    out.writeln('总课时: ${totalLessons(parsed)}');
    if (parsed.warnings.isNotEmpty) {
      out.writeln('警告: ${parsed.warnings.join("；")}');
    }
    final sorted = parsed.courses.toList()
      ..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        if (byDay != 0) return byDay;
        return a.periodFrom.compareTo(b.periodFrom);
      });
    for (final c in sorted) {
      out.writeln('周${c.day} ${c.periodFrom}-${c.periodTo} ${c.name} '
          '[${c.room}] ${c.teacher} 周:${c.weeks.first}-${c.weeks.last}'
          '(${c.weeks.length}周)');
    }
    // 让输出出现在测试日志里，方便人工核对
    // ignore: avoid_print
    print(out.toString());
    expect(parsed.courses, isNotEmpty);
  });

  test('诊断：打印词与坐标（设 MYDAY_PDF_DEBUG 才跑）', () {
    if (Platform.environment['MYDAY_PDF_DEBUG'] == null) {
      markTestSkipped('诊断模式');
    }
    final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
    final extractor = PdfTextExtractor(doc);
    final out = StringBuffer();
    final dayWords = <String>['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final lines = extractor.extractTextLines();
    out.writeln('lines=${lines.length}');
    var n = 0;
    for (final line in lines) {
      for (final w in line.wordCollection) {
        final t = w.text.trim();
        if (t.isEmpty) continue;
        if (dayWords.any(t.contains) ||
            RegExp(r'^\d{1,2}$').hasMatch(t) && n < 80) {
          out.writeln('${w.bounds.left.toStringAsFixed(1)},'
              '${w.bounds.center.dy.toStringAsFixed(1)}  "$t"');
          n++;
        }
      }
    }
    // ignore: avoid_print
    print(out.toString());
    doc.dispose();
  });

  test('诊断2：解析结果（设 MYDAY_PDF_DEBUG 才跑）', () {
    if (Platform.environment['MYDAY_PDF_DEBUG'] == null) {
      markTestSkipped('诊断模式');
    }
    final parsed = parsePdfTimetable(File(path).readAsBytesSync());
    final buf = StringBuffer();
    buf.writeln('courses=${parsed.courses.length} '
        'periodRows=${parsed.periodRows.join(",")}');
    for (final c in parsed.courses) {
      buf.writeln('${c.day} ${c.periodFrom}-${c.periodTo} ${c.name} '
          '[${c.room}] ${c.teacher} 周${c.weekText}');
    }
    // ignore: avoid_print
    print(buf.toString());
  });
}
