/// 课表导入（PDF 第二种格式）：「班级课表」PDF。
///
/// 特征（和第一种「学生课表」完全不同）：
/// - 节次行用中文数字（一、二、三…）竖排在左侧，还有「上午 / 下午」分段；
/// - 课程格的文字碎成很多小段，按「课程名 学分 教师 [周次]周 节次 班级 教室 校区」
///   的顺序排（例：药理学 3 张瑞 [1-12]周 1-2节 针灸推拿2025[1-3]班 305 弋江校区）；
/// - 同一段文字会被画两遍（描边效果），要先去重。
///
/// 解析：认出「星期」表头列 → 认出左侧的中文数字节次行 → 文字按 (天, 节次) 分桶 →
/// 每桶按 (y, x) 排序后按片段位置解析出各字段。
library;

import 'pdf_timetable.dart' show RectLine, splitPdfCourseBlocks;
import 'timetable.dart';

const _cnNum = <String, int>{
  '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
  '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
};

bool _isCnNum(String t) => _cnNum.containsKey(t.trim());

bool _isDigits(String t) {
  if (t.isEmpty) return false;
  for (final ch in t.runes) {
    if (ch < 0x30 || ch > 0x39) return false;
  }
  return true;
}

/// 去掉「画两遍」的重复碎片：同文字且位置几乎相同。
List<RectLine> dedupeLines(List<RectLine> lines) {
  final out = <RectLine>[];
  for (final f in lines) {
    var dup = false;
    for (final g in out) {
      if (g.text == f.text &&
          (g.bounds.center.dx - f.bounds.center.dx).abs() < 2 &&
          (g.bounds.center.dy - f.bounds.center.dy).abs() < 2) {
        dup = true;
        break;
      }
    }
    if (!dup) out.add(f);
  }
  return out;
}

/// 第二种格式的解析入口。解析不出就抛 [TimetableError]。
ParsedTimetable parsePdfTimetableV2(List<RectLine> lines) {
  final items = dedupeLines(lines);
  if (items.isEmpty) {
    throw TimetableError('这份 PDF 里没有提取到文字，可能是扫描件，暂时导不了');
  }

  // ---------- 星期表头列（最靠上的「星期」词，按 x 排成最多 7 列） ----------
  final dayFrags = items.where((f) => f.text.contains('星期')).toList()
    ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
  if (dayFrags.isEmpty) {
    throw TimetableError('没认出课表的表头：PDF 里要有「星期一…星期日」这些列');
  }
  final colXs = <double>[];
  final dayCols = <int>[];
  var day = 0;
  for (final f in dayFrags) {
    final x = f.bounds.center.dx;
    if (colXs.isEmpty || (x - colXs.last).abs() > 5) {
      colXs.add(x);
      day += 1;
      dayCols.add(day);
    }
  }
  if (dayCols.isEmpty) {
    throw TimetableError('没认出课表的表头：PDF 里要有「星期一…星期日」这些列');
  }
  final minDayX = colXs.first;

  // ---------- 节次行：星期列以左的中文数字词（按 y 排，去重） ----------
  final periodRows = <(double, int)>[];
  for (final f in items) {
    if (f.bounds.center.dx >= minDayX - 10) continue;
    final d = _isCnNum(f.text) ? _cnNum[f.text.trim()] : null;
    if (d != null) periodRows.add((f.bounds.center.dy, d));
  }
  periodRows.sort((a, b) => a.$1.compareTo(b.$1));
  final deduped = <(double, int)>[];
  for (final row in periodRows) {
    if (deduped.isEmpty || (row.$1 - deduped.last.$1).abs() > 2) {
      deduped.add(row);
    }
  }
  if (deduped.isEmpty) throw TimetableError('没找到节次行，确认一下是不是课表 PDF');
  final rowLabels = deduped.map((e) => '${e.$2}').toList();
  final numberLabel = <String, String>{};
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

  // ---------- 文字按 (天, 节次) 分桶 ----------
  final cells = <String, List<RectLine>>{};
  for (final f in items) {
    if (f.text.contains('星期')) continue; // 表头
    final c = f.bounds.center;
    if (c.dx < minDayX) continue; // 标签列
    int? day;
    double best = double.infinity;
    for (var i = 0; i < colXs.length; i++) {
      final dist = (c.dx - colXs[i]).abs();
      if (dist < best) {
        best = dist;
        day = dayCols[i];
      }
    }
    final row = rowIndexOf(c.dy);
    if (day == null || row == null) continue;
    cells.putIfAbsent('$day@${rowLabels[row]}', () => <RectLine>[]).add(f);
  }

  // ---------- 逐桶解析（格式二：按片段位置取字段） ----------
  final courses = <ParsedCourse>[];
  final warnings = <String>[];
  final keys = cells.keys.toList()..sort();
  for (final key in keys) {
    final parts = key.split('@');
    final day = int.parse(parts[0]);
    final rowLabel = parts[1];
    final frags = cells[key]!
      ..sort((a, b) {
        final byY = a.bounds.center.dy.compareTo(b.bounds.center.dy);
        if (byY != 0) return byY;
        return a.bounds.left.compareTo(b.bounds.left);
      });
    final cellText = frags.map((f) => f.text).join('\n');
    for (final block in splitPdfCourseBlocks(cellText)) {
      final parsed = parsePdfCellV2(block, day, rowLabel, numberLabel);
      if (parsed == null) continue;
      if (parsed.weeks.isEmpty) {
        warnings.add('${dayCn[day] ?? ''} ${parsed.periodFrom} 的「'
            '${parsed.name.length > 16 ? parsed.name.substring(0, 16) : parsed.name}」没写周次，已跳过');
        continue;
      }
      courses.add(parsed);
    }
  }
  if (courses.isEmpty) {
    throw TimetableError('这份 PDF 里没读到任何带周次的课程，确认一下是不是课表本身');
  }

  return ParsedTimetable(
    sheet: 'PDF',
    title: '',
    student: '',
    courses: courses,
    warnings: warnings,
    periodRows: rowLabels,
  );
}

/// 解析「班级课表」格式的课程块（片段以换行相连后的整段文字）。
/// 片段顺序：课程名 [学分] 教师 [周次]周 节次 班级 教室… 校区。
ParsedCourse? parsePdfCellV2(
    String block, int day, String rowLabel, Map<String, String> numberLabel) {
  final marker = RegExp(r'(\d+)\s*[-–]\s*(\d+)\s*节|(\d+)\s*节');
  final m = marker.firstMatch(block);
  if (m == null) return null;
  final startNum = m.group(1) ?? m.group(3);
  final endNum = m.group(2);
  if (startNum == null) return null;
  final periodFrom = numberLabel[startNum];
  if (periodFrom == null) return null;
  final periodTo =
      endNum != null ? (numberLabel[endNum] ?? periodFrom) : periodFrom;

  final weeksM = RegExp(r'\[([\d\-，,\s]+)\]\s*周').firstMatch(block);
  final weeks = weeksM != null ? parseWeeks(weeksM.group(1)!) : const <int>[];

  // 按空白切段，定位「节次」段，往前往后取字段
  final segs = block
      .split(RegExp(r'\s+'))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  var markerSeg = -1;
  for (var i = 0; i < segs.length; i++) {
    if (marker.hasMatch(segs[i])) {
      markerSeg = i;
      break;
    }
  }
  if (markerSeg < 0) return null;

  // 课程名：节次段之前，跳过学分数字段
  final nameSegs = <String>[];
  for (var i = markerSeg - 1; i >= 0; i--) {
    final s = segs[i];
    if (_isDigits(s) && nameSegs.isEmpty) continue; // 学分
    if (s.contains('[') || s.contains('节') || _isDigits(s)) break;
    nameSegs.insert(0, s);
  }
  final name = nameSegs.join(' ').trim();
  if (name.isEmpty) return null;

  // 教师：周次段前一段（2-4 个汉字）
  var teacher = '';
  if (markerSeg >= 2) {
    final t = segs[markerSeg - 2].trim();
    if (!t.contains('[') && !_isDigits(t)) teacher = t;
  }

  // 班级 / 教室 / 校区：节次段之后。班级段带「班」；最后一段按校区算
  final after = segs.sublist(markerSeg + 1);
  final roomSegs = <String>[];
  var campus = '';
  for (var i = 0; i < after.length; i++) {
    final s = after[i];
    if (s.contains('节') || s.contains('周')) continue;
    if (i == after.length - 1) {
      campus = s;
    } else {
      roomSegs.add(s);
    }
  }
  final room = roomSegs.join(' ').trim();

  return ParsedCourse(
    day: day,
    periodFrom: periodFrom,
    periodTo: periodTo,
    name: name,
    className: campus,
    teacher: teacher,
    room: room,
    weekText: weeksM?.group(1) ?? '',
    weeks: weeks,
    raw: block,
  );
}
