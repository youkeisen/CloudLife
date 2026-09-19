/// 课表导入（PDF 第二种格式）：「班级课表」PDF。
///
/// 特征（和第一种「学生课表」完全不同）：
/// - 整行表格会被提取成一行文字（星期表头也是一整条），不能按词分格；
/// - 节次行用中文数字（一、二、三…）竖排在左侧的标签列；
/// - 课程块是几行文字，第一行带「[周次]周 起止节」标记：
///     药理学 3 张瑞 [1-12]周 1-
///     2节 针灸推拿2025[1-3]班
///     305 弋江校区
/// - 同一段文字会被画两遍（描边），要按位置去重。
///
/// 解析：按 x 聚簇分列（含最多中文数字的列是标签列，扔掉）→
/// 其余列按 x 顺序当星期一…星期日 → 每列按 y 排序、
/// 遇到「[周次]周」标记行就开新课块 → 连接后用正则取字段。
library;

import 'pdf_timetable.dart' show RectLine;
import 'timetable.dart';

bool _isCnNum(String t) {
  final s = t.trim();
  if (s.isEmpty || s.length > 2) return false;
  for (final ch in s.runes) {
    if (!_cnNumChars.contains(String.fromCharCode(ch))) return false;
  }
  return true;
}

const _cnNumChars = '一二三四五六七八九十';

/// 去掉「画两遍」的重复行：同文字且位置几乎相同。
List<RectLine> dedupeLines(List<RectLine> lines) {
  final out = <RectLine>[];
  for (final f in lines) {
    var dup = false;
    for (final g in out) {
      if (g.text == f.text &&
          (g.bounds.center.dx - f.bounds.center.dx).abs() < 3 &&
          (g.bounds.center.dy - f.bounds.center.dy).abs() < 3) {
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

  // ---------- 按 x 聚簇分列（中心间隔 > 25 视为新列） ----------
  final sorted = items.toList()
    ..sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));
  final columns = <List<RectLine>>[];
  double? lastX;
  for (final f in sorted) {
    if (lastX == null || f.bounds.center.dx - lastX > 25) {
      columns.add(<RectLine>[f]);
    } else {
      columns.last.add(f);
    }
    lastX = f.bounds.center.dx;
  }

  // ---------- 标签列：含最多「中文数字」的列，扔掉 ----------
  var labelIdx = -1;
  var labelCount = 0;
  for (var i = 0; i < columns.length; i++) {
    var n = 0;
    for (final f in columns[i]) {
      if (_isCnNum(f.text)) n++;
    }
    if (n > labelCount) {
      labelCount = n;
      labelIdx = i;
    }
  }
  if (labelIdx < 0) {
    throw TimetableError('没认出节次标签列，确认一下是不是课表 PDF');
  }
  final dayColumns = <List<RectLine>>[];
  for (var i = 0; i < columns.length; i++) {
    if (i != labelIdx) dayColumns.add(columns[i]);
  }
  if (dayColumns.isEmpty) {
    throw TimetableError('没找到任何课程列，确认一下是不是课表 PDF');
  }

  // ---------- 每列按 y 排序，用「[周次]周 数字[-数字]」标记切课程块 ----------
  final courses = <ParsedCourse>[];
  final warnings = <String>[];
  final seen = <String>{};
  var maxPeriod = 0;
  final weeksRe = RegExp(r'\[([^\]]+)\]\s*周');

  for (var d = 0; d < dayColumns.length; d++) {
    final day = d + 1;
    final columnLines = dayColumns[d]
      ..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

    var curLines = <RectLine>[];
    var curMarkerLine = '';

    void flush() {
      if (curLines.isEmpty || curMarkerLine.isEmpty) {
        curLines = <RectLine>[];
        curMarkerLine = '';
        return;
      }
      // 换行全部拼上再去掉空白：'...周 1-' + '2节 ...' 拼成 '...周1-2节...'
      final joined = curLines.map((l) => l.text).join().replaceAll(
          RegExp(r'\s+'), '');
      final weeksM = RegExp(r'\[([^\]]+)\]周').firstMatch(joined);
      final perM = RegExp(r']周(\d+)(?:[-–](\d+))?节').firstMatch(joined);
      if (weeksM == null || perM == null) {
        curLines = <RectLine>[];
        curMarkerLine = '';
        return;
      }
      final weeks = parseWeeks(weeksM.group(1)!);
      final from = int.parse(perM.group(1)!);
      final to = int.tryParse(perM.group(2) ?? '') ?? from;

      // 标记行：名字 学分 教师 [周次]周 …
      final hm = RegExp(r'^(.*?)(\d+)\s+([\u4e00-\u9fa5]{2,4})\s*\[')
          .firstMatch(curMarkerLine);
      var name = (hm?.group(1) ?? '')
          .replaceAll(RegExp(r'^星期[一二三四五六日天]\s*'), '')
          .trim();
      final teacher = hm?.group(3)?.trim() ?? '';
      if (name.isEmpty) {
        curLines = <RectLine>[];
        curMarkerLine = '';
        return;
      }

      // 教室：节次之后的文字，去掉班级段（到「班」为止）和结尾的校区
      final afterJie = joined.indexOf('节');
      var room = '';
      if (afterJie >= 0 && afterJie + 1 < joined.length) {
        room = joined.substring(afterJie + 1);
        final banIdx = room.indexOf('班');
        if (banIdx >= 0 && banIdx + 1 < room.length) {
          room = room.substring(banIdx + 1);
        }
        room = room.replaceAll(RegExp(r'[\u4e00-\u9fa5]{2,6}校区$'), '').trim();
      }

      final key = '$day|$name|$from|$to|${weeks.join(",")}';
      if (seen.add(key)) {
        if (to > maxPeriod) maxPeriod = to;
        courses.add(ParsedCourse(
          day: day,
          periodFrom: '$from',
          periodTo: '$to',
          name: name,
          className: '',
          teacher: teacher,
          room: room,
          weekText: '[${weeksM.group(1)}]',
          weeks: weeks,
          raw: joined,
        ));
      }
      curLines = <RectLine>[];
      curMarkerLine = '';
    }

    for (final line in columnLines) {
      if (weeksRe.hasMatch(line.text)) {
        flush();
        curMarkerLine = line.text;
        curLines.add(line);
      } else if (curLines.isNotEmpty) {
        curLines.add(line);
      }
      // 标记行之前的首行碎文字（列头等）直接跳过
    }
    flush();
  }
  if (courses.isEmpty) {
    throw TimetableError('这份 PDF 里没读到任何带周次的课程，确认一下是不是课表本身');
  }

  final maxPeriodSeen = courses.fold<int>(0, (m, c) {
    final t = int.tryParse(c.periodTo) ?? 0;
    return t > m ? t : m;
  });

  final maxTo = maxPeriodSeen < 1 ? 12 : maxPeriodSeen;
  return ParsedTimetable(
    sheet: 'PDF',
    title: '',
    student: '',
    courses: courses,
    warnings: warnings,
    periodRows: [for (var i = 1; i <= maxTo; i++) '$i'],
  );
}
