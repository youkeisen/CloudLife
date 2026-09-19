/// 课表导入（PDF 版）：解析教务系统导出的课表 PDF。
///
/// 思路：用 Syncfusion 提取带坐标的文字，先认出「星期」词的位置判断表格方向——
/// - 经典布局：星期是列（沿 x 铺开），节次行在左侧；
/// - 转置布局：星期是行（沿 y 铺开），节次是横着的列（凯森学校这份就是）。
///
/// 解析分两条路互补：
/// A. 分桶解析——转置布局按「文字行左边缘」定列。名字和周次最准，
///    但跨列的长课块换行文字会散到隔壁桶，场地/教师常常缺；
/// B. 按天整行重解析——把一天的全部文字按坐标排序后用「(起-止节)」标记切，
///    场地/教师最全，但同一基线上的两门课会并名。
/// 最后按 (天, 名字, 起始节) 合并：A 为主，B 补缺的场地/教师。
/// 解析完汇成 [ParsedTimetable]，下游（预览/落库/备份）全部复用。
library;

import 'dart:ui' show Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'timetable.dart';

/// 判断一个文件是不是 PDF（看魔数，不依赖扩展名）。
bool looksLikePdf(List<int> bytes) {
  if (bytes.length < 5) return false;
  const head = [0x25, 0x50, 0x44, 0x46]; // %PDF
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != head[i]) return false;
  }
  return true;
}

ParsedTimetable parsePdfTimetable(List<int> bytes) {
  if (!looksLikePdf(bytes)) {
    throw TimetableError('这个文件不是 PDF。请用教务系统导出的课表 PDF 再试');
  }
  final doc = PdfDocument(inputBytes: bytes);
  final lines = <TextLine>[];
  try {
    lines.addAll(PdfTextExtractor(doc).extractTextLines());
  } catch (e) {
    throw TimetableError('PDF 内容读不出来：$e');
  } finally {
    doc.dispose();
  }
  if (lines.isEmpty) {
    throw TimetableError('这份 PDF 里没有提取到文字，可能是扫描件，暂时导不了');
  }

  // ---------- 星期词的位置：决定表格方向 ----------
  final dayPos = <int, Rect>{};
  for (final line in lines) {
    for (final w in line.wordCollection) {
      final d = dayOf(w.text);
      if (d != null && !dayPos.containsKey(d)) dayPos[d] = w.bounds;
    }
  }
  if (dayPos.isEmpty) {
    throw TimetableError('没认出课表的表头：PDF 里要有「星期一…星期日」这些列');
  }
  double minDayX = double.infinity, maxDayX = -double.infinity;
  double minDayY = double.infinity, maxDayY = -double.infinity;
  for (final r in dayPos.values) {
    if (r.center.dx < minDayX) minDayX = r.center.dx;
    if (r.center.dx > maxDayX) maxDayX = r.center.dx;
    if (r.center.dy < minDayY) minDayY = r.center.dy;
    if (r.center.dy > maxDayY) maxDayY = r.center.dy;
  }
  final transposed = (maxDayY - minDayY) > (maxDayX - minDayX);

  // 星期行/列的几何：按位置分带，文字落到哪一带就算哪一天
  final dayBands = dayPos.entries
      .map((e) => (
            y: transposed ? e.value.center.dy : e.value.center.dx,
            day: e.key
          ))
      .toList()
    ..sort((a, b) => a.y.compareTo(b.y));
  final rowHalfGap = dayBands.length > 1
      ? (dayBands[1].y - dayBands[0].y).abs() / 2
      : 100.0;
  int? dayOfPosition(double p) {
    for (var i = 0; i < dayBands.length; i++) {
      final top = i == 0
          ? dayBands.first.y - 100
          : (dayBands[i - 1].y + dayBands[i].y) / 2;
      final bottom = i == dayBands.length - 1
          ? dayBands.last.y + rowHalfGap
          : (dayBands[i].y + dayBands[i + 1].y) / 2;
      if (p >= top && p < bottom) return dayBands[i].day;
    }
    return null;
  }

  // ---------- 节次编号表 ----------
  final numberLabel = <String, String>{};
  List<String> rowLabels;

  // 每条文字行的归属：A 用（天@列 桶），B 用（天 行）
  final lineBuckets = <String, List<String>>{}; // '天@列' -> 文字行
  final dayLines = <int, List<RectLine>>{}; // 天 -> 行（含坐标）

  void putLine(int day, String bucketKey, String text, TextLine line) {
    lineBuckets.putIfAbsent(bucketKey, () => <String>[]).add(text);
    dayLines
        .putIfAbsent(day, () => <RectLine>[])
        .add(RectLine(text, line.bounds));
  }

  if (transposed) {
    // 节次列：不在星期行 y 范围里的数字词，按 y 聚带，取最大的一带
    final outside = <(double, double, String)>[];
    for (final line in lines) {
      if (line.bounds.center.dy >= minDayY - 20 &&
          line.bounds.center.dy <= maxDayY + 20) {
        continue;
      }
      for (final w in line.wordCollection) {
        final t = w.text.trim();
        if (t.isNotEmpty && double.tryParse(t) != null) {
          outside.add((w.bounds.center.dx, w.bounds.center.dy, t));
        }
      }
    }
    final bands = <int, List<(double, double, String)>>{};
    for (final w in outside) {
      bands.putIfAbsent((w.$2 / 25).round(), () => []).add(w);
    }
    List<(double, double, String)>? best;
    for (final list in bands.values) {
      if (best == null || list.length > best.length) best = list;
    }
    if (best == null || best.isEmpty) {
      throw TimetableError('没找到节次列，确认一下是不是课表 PDF');
    }
    best.sort((a, b) => a.$1.compareTo(b.$1));
    final colXs = <double>[];
    final colLabels = <String>[];
    for (final w in best) {
      if (colXs.isEmpty || (w.$1 - colXs.last).abs() > 5) {
        colXs.add(w.$1);
        colLabels.add(w.$3);
      }
    }
    rowLabels = colLabels;
    for (final label in rowLabels) {
      numberLabel[label] = label;
    }

    for (final line in lines) {
      final day = dayOfPosition(line.bounds.center.dy);
      // 用行的左边缘定列：跨列课块的文字从它第一列的左边开始；
      // 第一列以左是「时间段」标签列，跳过。
      final left = line.bounds.left;
      if (left < colXs.first - 15) continue;
      final dayOrNull = day;
      if (dayOrNull == null) continue;
      var col = colLabels.first;
      for (var i = colXs.length - 1; i >= 0; i--) {
        if (left >= colXs[i] - 8) {
          col = colLabels[i];
          break;
        }
      }
      putLine(dayOrNull, '$dayOrNull@$col', line.text, line);
    }
  } else {
    // 经典布局：节次行在星期列以左（y 分带）
    final periodRows = <(double, String)>[];
    for (final line in lines) {
      if (line.bounds.center.dx >= minDayX) continue;
      for (final w in line.wordCollection) {
        final t = w.text.trim();
        if (t.isNotEmpty && double.tryParse(t) != null) {
          periodRows.add((w.bounds.center.dy, t));
        }
      }
    }
    periodRows.sort((a, b) => a.$1.compareTo(b.$1));
    final deduped = <(double, String)>[];
    for (final row in periodRows) {
      if (deduped.isEmpty || (row.$1 - deduped.last.$1).abs() > 2) {
        deduped.add(row);
      }
    }
    if (deduped.isEmpty) throw TimetableError('没找到节次行，确认一下是不是课表 PDF');
    rowLabels = deduped.map((e) => e.$2).toList();
    for (final label in rowLabels) {
      numberLabel[label] = label;
    }

    int? rowIndexOf(double y) {
      for (var i = 0; i < deduped.length; i++) {
        final top = i == 0
            ? deduped.first.$1 - 100
            : (deduped[i - 1].$1 + deduped[i].$1) / 2;
        final bottom = i == deduped.length - 1
            ? deduped.last.$1 + 1000
            : (deduped[i].$1 + deduped[i + 1].$1) / 2;
        if (y >= top && y < bottom) return i;
      }
      return null;
    }

    for (final line in lines) {
      final c = line.bounds.center;
      if (c.dx < minDayX) continue; // 标签列
      int? day;
      double best = double.infinity;
      dayPos.forEach((d, r) {
        final dist = (c.dx - r.center.dx).abs();
        if (dist < best) {
          best = dist;
          day = d;
        }
      });
      final row = rowIndexOf(c.dy);
      final dayOrNull = day;
      if (dayOrNull == null || row == null) continue;
      putLine(dayOrNull, '$dayOrNull@${rowLabels[row]}', line.text, line);
    }
  }

  // ---------- A：逐桶解析（名字/周次最准） ----------
  final courses = <ParsedCourse>[];
  final warnings = <String>[];
  final bucketKeys = lineBuckets.keys.toList()..sort();
  for (final key in bucketKeys) {
    final parts = key.split('@');
    final day = int.parse(parts[0]);
    final bucketText = lineBuckets[key]!.join('\n');
    final blocks = splitPdfCourseBlocks(bucketText);
    for (final block in blocks) {
      final parsed = parsePdfCell(block, day, numberLabel);
      if (parsed == null) continue;
      if (parsed.weeks.isEmpty) {
        warnings.add('${dayCn[day] ?? ''} ${parsed.periodFrom} 的「'
            '${parsed.name.length > 16 ? parsed.name.substring(0, 16) : parsed.name}」没写周次，已跳过');
        continue;
      }
      courses.add(parsed);
    }
  }

  // ---------- B：按天重建格子（x 区间重叠聚簇），回填 A 缺的场地/教师 ----------
  //
  // 同一格子的换行文字 x 区间相互嵌套（居中对齐），邻格的不相交；
  // 所以按「x 区间是否重叠」聚簇就能把一天的文字重新分成格子，
  // 每簇按 (y, x) 排序后用「(起-止节)」标记切课程。这样场地/教师最全。
  // ignore: avoid_print
  print('[debug] buckets=${lineBuckets.length} coursesAfterA=${courses.length}');
  lineBuckets.forEach((k, v) {
    // ignore: avoid_print
    print('[bucket] $k => ${v.join(' | ').substring(0, v.join(' | ').length > 100 ? 100 : v.join(' | ').length)}');
  });
  final byKey = <String, int>{};
  for (var i = 0; i < courses.length; i++) {
    final c = courses[i];
    byKey['${c.day}|${c.name}|${c.periodFrom}'] = i;
  }
  for (final day in dayLines.keys.toList()..sort()) {
    final items = dayLines[day]!
      ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    final clusters = <List<RectLine>>[];
    double curLeft = -1, curRight = -1;
    for (final it in items) {
      final l = it.bounds.left, r = it.bounds.right;
      if (clusters.isEmpty || l > curRight + 5) {
        curLeft = l;
        curRight = r;
        clusters.add(<RectLine>[it]);
        continue;
      }
      if (l < curLeft) curLeft = l;
      if (r > curRight) curRight = r;
      clusters.last.add(it);
    }
    for (final cluster in clusters) {
      cluster.sort((a, b) {
        final byY = a.bounds.center.dy.compareTo(b.bounds.center.dy);
        if (byY != 0) return byY;
        return a.bounds.left.compareTo(b.bounds.left);
      });
      final cellText = cluster.map((t) => t.text).join('\n');
      for (final block in splitPdfCourseBlocks(cellText)) {
        final parsed = parsePdfCell(block, day, numberLabel);
        if (parsed == null || parsed.weeks.isEmpty) continue;
        final key = '$day|${parsed.name}|${parsed.periodFrom}';
        final idx = byKey[key];
        if (idx == null) {
          byKey[key] = courses.length;
          courses.add(parsed);
          continue;
        }
        final have = courses[idx];
        if ((have.room.isEmpty && parsed.room.isNotEmpty) ||
            (have.teacher.isEmpty && parsed.teacher.isNotEmpty)) {
          courses[idx] = ParsedCourse(
            day: have.day,
            periodFrom: have.periodFrom,
            periodTo: have.periodTo,
            name: have.name,
            className: have.className,
            teacher: have.teacher.isEmpty ? parsed.teacher : have.teacher,
            room: have.room.isEmpty ? parsed.room : have.room,
            weekText: have.weekText,
            weeks: have.weeks,
            raw: have.raw,
          );
        }
      }
    }
  }
  if (courses.isEmpty) {
    throw TimetableError('这份 PDF 里没读到任何带周次的课程，确认一下是不是课表本身');
  }
  // ignore: avoid_print
  print('[debug] coursesAfterB=${courses.length}');

  return ParsedTimetable(
    sheet: 'PDF',
    title: '',
    student: '',
    courses: courses,
    warnings: warnings,
    periodRows: rowLabels,
  );
}

/// B 路线用的一行文字：内容 + 坐标（x 区间用来聚簇重建格子）。
class RectLine {
  RectLine(this.text, this.bounds);

  final String text;
  final Rect bounds;
}

/// 把一格/一天的文字按课程切开：每门课都带一个「(起-止节)」标记，
/// 标记前是课程名。没带标记的碎文字不算课。
List<String> splitPdfCourseBlocks(String cellText) {
  final marker = RegExp(r'[(（]\s*\d+\s*(?:[-–]\s*\d+\s*)?节[)）]');
  final blocks = <String>[];
  final matches = marker.allMatches(cellText).toList();
  if (matches.isEmpty) return const <String>[];
  for (var i = 0; i < matches.length; i++) {
    final start = i == 0 ? 0 : matches[i - 1].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : cellText.length;
    final block = cellText.substring(start, end).trim();
    if (block.isNotEmpty) blocks.add(block);
  }
  return blocks;
}

/// 解析单个课程块（名称 + (起-止节)周次/校区/场地/教师）。
/// 起止节直接从标记里取。
ParsedCourse? parsePdfCell(
    String block, int day, Map<String, String> numberLabel) {
  final marker = RegExp(r'[(（]\s*(\d+)\s*(?:[-–]\s*(\d+)\s*)?节[)）]');
  final m = marker.firstMatch(block);
  if (m == null) return null;
  final startLabel = numberLabel[m.group(1)!];
  if (startLabel == null) return null;
  final endNum = m.group(2);
  final periodTo =
      endNum != null ? (numberLabel[endNum] ?? startLabel) : startLabel;

  // 课程名：标记前的文字。教务系统在名字末尾打 ★/☆；邻格的场地/教师碎片
  // 可能串进来（它们带 / 或 : ），所以取最后一段不含 / : 的文字当名字。
  var name = block.substring(0, m.start).replaceAll('\n', ' ');
  name = RegExp(r'[^/:／：]+$').firstMatch(name)?.group(0) ?? name;
  name = name.replaceAll(RegExp(r'[★☆]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return null;

  final rest = block.substring(m.start).replaceAll('\n', '').trim();
  final slash = rest.indexOf('/');
  final weekText = (slash >= 0 ? rest.substring(0, slash) : rest).trim();
  final weeks = parseWeeks(weekText);

  final room = RegExp(r'/场地[:：](.*?)(?=/教师|/校区|/上课|$)')
          .firstMatch(rest)
          ?.group(1)
          ?.trim() ??
      '';
  final teacher =
      RegExp(r'/教师[:：](.*)$').firstMatch(rest)?.group(1)?.trim() ?? '';

  return ParsedCourse(
    day: day,
    periodFrom: startLabel,
    periodTo: periodTo,
    name: name,
    className: '',
    teacher: teacher,
    room: room,
    weekText: weekText,
    weeks: weeks,
    raw: block.replaceAll('\n', ' '),
  );
}
