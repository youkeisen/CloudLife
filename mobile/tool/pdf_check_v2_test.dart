// 第二种课表 PDF（班级课表）的手动验证工具。
// 用法：$env:MYDAY_PDF='<pdf路径>'; flutter test tool/pdf_check_v2_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/pdf_timetable.dart';
import 'package:my_day_phone/pdf_timetable_v2.dart';
import 'package:my_day_phone/timetable.dart';

void main() {
  final path = Platform.environment['MYDAY_PDF'];
  if (path == null || !File(path).existsSync()) {
    test('跳过（未设置 MYDAY_PDF 环境变量）', () {
      markTestSkipped('设置 MYDAY_PDF 环境变量后再跑这个验证');
    });
    return;
  }

  test('解析班级课表 PDF：$path', () {
    final parsed =
        parsePdfTimetableV2(extractPdfLines(File(path).readAsBytesSync()));
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
    // ignore: avoid_print
    print(out.toString());
    expect(parsed.courses, isNotEmpty);
  });

  test('诊断：v2 的识别过程（设 MYDAY_PDF_DEBUG 才跑）', () {
    if (Platform.environment['MYDAY_PDF_DEBUG'] == null) {
      markTestSkipped('诊断模式');
    }
    final frags =
        dedupeLines(extractPdfLines(File(path).readAsBytesSync()));
    final buf = StringBuffer();
    buf.writeln('deduped=${frags.length}');
    final star = frags.where((f) => f.text.contains('星期')).toList()
      ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    buf.writeln('星期碎片 ${star.length} 个：');
    for (final f in star.take(10)) {
      buf.writeln('  x=${f.bounds.center.dx.toStringAsFixed(1)} '
          'y=${f.bounds.center.dy.toStringAsFixed(1)} "${f.text}"');
    }
    if (star.isNotEmpty) {
      final minX = star.map((f) => f.bounds.center.dx).reduce(
          (a, b) => a < b ? a : b);
      final left = frags
          .where((f) => f.bounds.center.dx < minX - 10)
          .toList()
        ..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
      buf.writeln('左侧碎片 ${left.length} 个：');
      for (final f in left.take(25)) {
        buf.writeln('  x=${f.bounds.center.dx.toStringAsFixed(1)} '
            'y=${f.bounds.center.dy.toStringAsFixed(1)} "${f.text}"');
      }
    }
    // ignore: avoid_print
    print(buf.toString());
  });
}
