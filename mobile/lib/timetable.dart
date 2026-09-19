/// 课表导入：解析教务系统导出的 xlsx 课表。
///
/// 是电脑版 `D:\App\MyDay\app\timetable.py` 的移植，解析规则逐条对齐，
/// 这样同一个文件在两边解析出的结果一致（凯森在电脑上导入过的课表，
/// 手机上再导一次结果应该一样）。
///
/// 认得的表格形状（教务系统「学生课表」常见样式）：
///   第 1 行  标题：学校 + 学期
///   第 2 行  学号 / 姓名
///   第 3 行  表头：时间 | 节次 | 星期一 … 星期日
///   第 4 行起  一行一个节次；课程格常按两节纵向合并
///
/// 单元格内容是打包写的：课程名(考核方式)(课程类别)专业班级{周次 教师 教室}
/// 一个格子里有多门课时用换行分隔。解析只发生在内存里，不落盘。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 单元格末段那些括号里的说明，抽课程名时要剥掉。
const Set<String> tailTags = <String>{
  '必修', '必修课', '选修', '选修课', '限选', '限选课', '公选', '公选课',
  '任选', '任选课', '专业必修', '专业选修', '考试', '考查', '考核', '练习',
  '其他', '补考', '重修',
};

const Map<String, int> dayWords = <String, int>{
  '星期一': 1, '周一': 1, '礼拜一': 1,
  '星期二': 2, '周二': 2, '礼拜二': 2,
  '星期三': 3, '周三': 3, '礼拜三': 3,
  '星期四': 4, '周四': 4, '礼拜四': 4,
  '星期五': 5, '周五': 5, '礼拜五': 5,
  '星期六': 6, '周六': 6, '礼拜六': 6,
  '星期日': 7, '星期天': 7, '周日': 7, '周天': 7, '礼拜日': 7,
};

const Map<int, String> dayCn = <int, String>{
  1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日',
};

const int maxWeeks = 30;

class TimetableError implements Exception {
  TimetableError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------- 基础小工具 ----------
int colIndex(String ref) {
  final letters = StringBuffer();
  for (final ch in ref.runes) {
    final c = String.fromCharCode(ch);
    final code = c.toUpperCase().codeUnitAt(0);
    if (code >= 65 && code <= 90) letters.writeCharCode(code);
  }
  final s = letters.toString();
  if (s.isEmpty) throw TimetableError('单元格坐标看不懂：$ref');
  var n = 0;
  for (final ch in s.codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n;
}

(int, int) splitRef(String ref) {
  final digits = StringBuffer();
  for (final ch in ref.runes) {
    final c = String.fromCharCode(ch);
    if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) digits.write(c);
  }
  final s = digits.toString();
  if (s.isEmpty) throw TimetableError('单元格坐标看不懂：$ref');
  return (int.parse(s), colIndex(ref));
}

Iterable<XmlElement> _local(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);

String? _childText(XmlElement el, String name) {
  for (final c in el.childElements) {
    if (c.name.local == name) return c.innerText;
  }
  return null;
}

// ---------- xlsx 基础读取 ----------
class XlsxBook {
  XlsxBook({
    required this.sheet,
    required this.cells,
    required this.merges,
    required this.maxRow,
    required this.maxCol,
  });

  final String sheet;

  /// key 是 (行, 列)，都是 1 起；只放左上角有值的格。
  final Map<(int, int), String> cells;
  final List<(int, int, int, int)> merges;
  final int maxRow;
  final int maxCol;
}

XlsxBook readXlsx(List<int> raw) {
  if (raw.isEmpty) throw TimetableError('没有拿到文件内容');
  Archive? archive;
  try {
    archive = ZipDecoder().decodeBytes(raw);
  } catch (_) {
    throw TimetableError('这个文件不是 xlsx。请用 Excel 打开后「另存为」.xlsx 再试');
  }
  String? content(String name) {
    for (final f in archive!.files) {
      if (f.name.replaceAll('\\', '/') == name) {
        return utf8.decode(f.content as List<int>, allowMalformed: true);
      }
    }
    return null;
  }

  final hasXl = archive.files.any((f) => f.name.startsWith('xl/'));
  if (!hasXl) throw TimetableError('文件里没有工作表，确认一下是不是真正的 .xlsx');

  // 工作表名（拿第一张的名字展示用）
  var sheetName = '';
  final workbookXml = content('xl/workbook.xml');
  if (workbookXml != null) {
    try {
      final root = XmlDocument.parse(workbookXml);
      for (final el in _local(root, 'sheet')) {
        sheetName = el.getAttribute('name') ?? '';
        break;
      }
    } catch (_) {
      sheetName = '';
    }
  }

  // 取编号最小的第一张工作表
  String? sheetPath;
  var best = -1;
  for (final f in archive.files) {
    final name = f.name.replaceAll('\\', '/');
    final m = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$').firstMatch(name);
    if (m == null) continue;
    final n = int.parse(m.group(1)!);
    if (best == -1 || n < best) {
      best = n;
      sheetPath = name;
    }
  }
  if (sheetPath == null) throw TimetableError('这个 xlsx 里没有找到工作表');

  final sheetXml = content(sheetPath);
  if (sheetXml == null) throw TimetableError('工作表内容读不出来');
  XmlDocument root;
  try {
    root = XmlDocument.parse(sheetXml);
  } catch (e) {
    throw TimetableError('工作表内容读不出来：$e');
  }

  // 共享字符串
  final sst = <String>[];
  final sstXml = content('xl/sharedStrings.xml');
  if (sstXml != null) {
    try {
      final sstRoot = XmlDocument.parse(sstXml);
      for (final si in _local(sstRoot, 'si')) {
        final buf = StringBuffer();
        for (final t in _local(si, 't')) {
          buf.write(t.innerText);
        }
        sst.add(buf.toString());
      }
    } catch (_) {
      // 没有 sharedStrings 也能继续
    }
  }

  final cells = <(int, int), String>{};
  final merges = <(int, int, int, int)>[];
  for (final el in _local(root, 'c')) {
    final ref = el.getAttribute('r') ?? '';
    if (ref.isEmpty) continue;
    final (int row, int col) = splitRef(ref);
    final ctype = el.getAttribute('t') ?? '';
    var text = '';
    if (ctype == 's') {
      final v = _childText(el, 'v');
      if (v != null) {
        final idx = int.tryParse(v.trim()) ?? -1;
        if (idx >= 0 && idx < sst.length) text = sst[idx];
      }
    } else if (ctype == 'inlineStr') {
      final buf = StringBuffer();
      for (final t in _local(el, 't')) {
        buf.write(t.innerText);
      }
      text = buf.toString();
    } else {
      text = _childText(el, 'v') ?? '';
    }
    text = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (text.isNotEmpty) cells[(row, col)] = text;
  }
  for (final el in _local(root, 'mergeCell')) {
    final ref = el.getAttribute('ref') ?? '';
    if (!ref.contains(':')) continue;
    final pair = ref.split(':');
    if (pair.length < 2) continue;
    try {
      final (r1, c1) = splitRef(pair[0]);
      final (r2, c2) = splitRef(pair[1]);
      merges.add((
        r1 < r2 ? r1 : r2,
        c1 < c2 ? c1 : c2,
        r1 > r2 ? r1 : r2,
        c1 > c2 ? c1 : c2,
      ));
    } on TimetableError {
      continue;
    }
  }

  if (cells.isEmpty) throw TimetableError('这张表是空的，没读到任何内容');
  var maxRow = 0;
  var maxCol = 0;
  cells.forEach((key, _) {
    if (key.$1 > maxRow) maxRow = key.$1;
    if (key.$2 > maxCol) maxCol = key.$2;
  });
  return XlsxBook(
    sheet: sheetName,
    cells: cells,
    merges: merges,
    maxRow: maxRow,
    maxCol: maxCol,
  );
}

// ---------- 单元格内容解析 ----------
int? dayOf(String? text) {
  if (text == null) return null;
  final key = text.replaceAll(RegExp(r'\s+'), '');
  return dayWords[key];
}

String stripTailTags(String head) {
  var name = head.trim();
  while (true) {
    final m = RegExp(r'[（(]([^（()）]{1,8})[）)]\s*$').firstMatch(name);
    if (m == null) break;
    final tag = m.group(1)!.trim();
    if (!tailTags.contains(tag)) break;
    name = name.substring(0, m.start).trim();
  }
  return name;
}

final RegExp _classRe =
    RegExp(r'[\u4e00-\u9fa5]{2,10}?(?:技术|专业|班|学院|系|方向)\s*\d{2,4}');
final RegExp _classListRe = RegExp(
    r'[\u4e00-\u9fa5]{2,10}?(?:技术|专业|班|学院|系|方向)\s*\d{2,4}'
    r'(?:\s*[,，、]\s*[\u4e00-\u9fa5]{2,10}?(?:技术|专业|班|学院|系|方向)\s*\d{2,4})*');

bool _fullMatch(RegExp re, String s) {
  final m = re.firstMatch(s);
  return m != null && m.start == 0 && m.end == s.length;
}

/// 把「课程名 + 班级」拆开。
///
/// 教务系统的写法是：课程名(考核方式)(课程类别)专业班级，班级长这样
/// 「电气自动化技术251」= 专业名 + 年级号。课程名和班级之间没有分隔符，
/// 所以优先用括号标注当分界：最后一个 ')' 后面剩下的就是班级。
/// 没有括号时，再从末尾往前找最靠后的、能延到末尾的班级。
(String, String) splitClass(String head) {
  head = head.trim();
  final cut = head.lastIndexOf(')');
  if (cut >= 0) {
    final tail = head.substring(cut + 1).trim();
    final front = head.substring(0, cut + 1).trim();
    if (tail.isNotEmpty && front.isNotEmpty && _fullMatch(_classListRe, tail)) {
      return (front, tail);
    }
  }
  for (var start = head.length - 1; start > 0; start--) {
    final sub = head.substring(start);
    if (_fullMatch(_classRe, sub)) {
      return (head.substring(0, start).trim(), sub.trim());
    }
  }
  return (head, '');
}

List<int> parseWeeks(String? text) {
  var t = (text ?? '').trim();
  if (t.isEmpty) return const <int>[];
  final odd = t.contains('单');
  final even = t.contains('双');
  t = t.replaceAll('周', ' ');
  t = t.replaceAll(RegExp(r'[（()）第单双]+'), ' ');
  final weeks = <int>{};
  for (final part in t.split(RegExp(r'[,，、;；/\s]+'))) {
    if (part.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*[-–~至]\s*(\d+)$').firstMatch(part);
    if (m != null) {
      var a = int.parse(m.group(1)!);
      var b = int.parse(m.group(2)!);
      if (a > b) {
        final tmp = a;
        a = b;
        b = tmp;
      }
      for (var w = a; w <= b; w++) {
        weeks.add(w);
      }
    } else {
      final single = int.tryParse(part);
      if (single != null) weeks.add(single);
    }
  }
  if (odd) weeks.removeWhere((w) => w.isOdd ? false : true);
  if (even) weeks.removeWhere((w) => w.isEven ? false : true);
  final out = weeks.where((w) => w >= 1 && w <= maxWeeks).toList()..sort();
  return out;
}

class CourseLine {
  CourseLine({
    required this.name,
    required this.className,
    required this.teacher,
    required this.room,
    required this.weekText,
    required this.weeks,
    required this.raw,
  });

  final String name;
  final String className;
  final String teacher;
  final String room;
  final String weekText;
  final List<int> weeks;
  final String raw;
}

CourseLine? parseCourseLine(String? line) {
  var text = (line ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  var meta = '';
  var head = text;
  final metaMatch = RegExp(r'\{(.*)\}').firstMatch(text);
  if (metaMatch != null) {
    head = (text.substring(0, metaMatch.start) + text.substring(metaMatch.end))
        .trim();
    meta = metaMatch.group(1)!.trim();
  }
  // 全角括号统一成半角，方便用最后一个 ')' 当班级的分界
  head = head.replaceAll('（', '(').replaceAll('）', ')');

  var weekText = '';
  var teacher = '';
  var room = '';
  if (meta.isNotEmpty) {
    final parts = meta.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      weekText = parts.first;
      final rest = parts.sublist(1);
      if (rest.isNotEmpty) {
        // 教室一般带数字或 #，教师是纯中文姓名
        if (RegExp(r'[\d#]').hasMatch(rest.last)) {
          room = rest.last;
          teacher = rest.sublist(0, rest.length - 1).join(' ');
        } else {
          teacher = rest.join(' ');
        }
      }
    }
  }

  // 先按「班级」把尾巴切出去，再剥 (考试)(必修课) 这些标注——
  // 顺序反了的话，标注后面还跟着班级，就不在末尾了，剥不掉。
  final (String name0, String className) = splitClass(head);
  final name = stripTailTags(name0);
  if (name.isEmpty) return null;
  return CourseLine(
    name: name,
    className: className,
    teacher: teacher,
    room: room,
    weekText: weekText,
    weeks: parseWeeks(weekText),
    raw: text,
  );
}

// ---------- 整张表解析 ----------
class ParsedCourse {
  ParsedCourse({
    required this.day,
    required this.periodFrom,
    required this.periodTo,
    required this.name,
    required this.className,
    required this.teacher,
    required this.room,
    required this.weekText,
    required this.weeks,
    required this.raw,
  });

  final int day;
  final String periodFrom;
  final String periodTo;
  final String name;
  final String className;
  final String teacher;
  final String room;
  final String weekText;
  final List<int> weeks;
  final String raw;
}

class ParsedTimetable {
  ParsedTimetable({
    required this.sheet,
    required this.title,
    required this.student,
    required this.courses,
    required this.warnings,
    required this.periodRows,
  });

  final String sheet;
  final String title;
  final String student;
  final List<ParsedCourse> courses;
  final List<String> warnings;

  /// 表格里从上到下的节次名。
  final List<String> periodRows;
}

ParsedTimetable parseTimetable(List<int> raw) {
  final book = readXlsx(raw);
  final cells = book.cells;
  final merges = book.merges;
  final rows = cells.keys.map((k) => k.$1).toSet().toList()..sort();

  // 表头：同一行里既有「节次」列，又有「星期一…星期日」列
  int? headerRow;
  int? periodCol;
  final dayCols = <int, int>{};
  for (final r in rows) {
    final rowCells = <int, String>{};
    cells.forEach((key, value) {
      if (key.$1 == r) rowCells[key.$2] = value;
    });
    int? pcol;
    for (final entry in rowCells.entries) {
      final v = entry.value.replaceAll(RegExp(r'\s+'), '');
      if (v == '节次' || v == '节数' || v == '节') {
        pcol = entry.key;
        break;
      }
    }
    final days = <int, int>{};
    rowCells.forEach((c, v) {
      final d = dayOf(v);
      if (d != null) days[d] = c;
    });
    if (pcol != null && days.isNotEmpty) {
      headerRow = r;
      periodCol = pcol;
      dayCols
        ..clear()
        ..addAll(days);
      break;
    }
  }
  if (headerRow == null) {
    throw TimetableError('没认出课表的表头：表里要有「节次」这一列和「星期一…星期日」这些列');
  }

  var title = '';
  var student = '';
  for (final r in rows) {
    if (r >= headerRow) continue;
    final cols = cells.keys.where((k) => k.$1 == r).map((k) => k.$2).toList()..sort();
    final line = cols.map((cc) => cells[(r, cc)]!).join(' ').trim();
    if (line.isEmpty) continue;
    if ((line.contains('学号') || line.contains('姓名')) && student.isEmpty) {
      student = line;
    } else if (title.isEmpty) {
      title = line;
    }
  }

  // 有些教务系统会把合并区的值在每个格子里都存一遍，所以：
  // covered = 被合并盖住、不是左上角的格子；resolved = 和 Excel 显示一致的网格。
  final covered = <(int, int)>{};
  final resolved = Map<(int, int), String>.from(cells);
  for (final (r1, c1, r2, c2) in merges) {
    final top = cells[(r1, c1)];
    for (var rr = r1; rr <= r2; rr++) {
      for (var cc = c1; cc <= c2; cc++) {
        if (rr == r1 && cc == c1) continue;
        covered.add((rr, cc));
        if (top != null) resolved[(rr, cc)] = top;
      }
    }
  }

  // 纵向合并：左上角那股跨到哪一行
  final spanEnd = <(int, int), int>{};
  for (final (r1, c1, r2, c2) in merges) {
    if (c1 == c2 && r2 > r1) spanEnd[(r1, c1)] = r2;
  }

  final periodRowList = <(int, String)>[];
  for (final r in rows) {
    if (r <= headerRow) continue;
    final label = resolved[(r, periodCol!)];
    if (label != null && label.isNotEmpty) periodRowList.add((r, label));
  }
  if (periodRowList.isEmpty) throw TimetableError('表头下面没有找到任何节次行');
  final lastPeriodRow = periodRowList.last.$1;

  final courses = <ParsedCourse>[];
  final warnings = <String>[];
  for (final (r, _) in periodRowList) {
    final dayKeys = dayCols.keys.toList()..sort();
    for (final day in dayKeys) {
      final c = dayCols[day]!;
      if (covered.contains((r, c))) continue;
      final text = cells[(r, c)];
      if (text == null) continue;
      final end = spanEnd[(r, c)] ?? r;
      final limit = end < lastPeriodRow ? end : lastPeriodRow;
      final span = periodRowList
          .where((pr) => r <= pr.$1 && pr.$1 <= limit)
          .map((pr) => pr.$2)
          .toList();
      if (span.isEmpty) continue;
      for (final line in text.split('\n')) {
        final one = parseCourseLine(line);
        if (one == null) continue;
        if (one.weeks.isEmpty) {
          warnings.add('${dayCn[day] ?? ''} ${span.first} 的「'
              '${one.name.length > 16 ? one.name.substring(0, 16) : one.name}」没写周次，已跳过');
          continue;
        }
        courses.add(ParsedCourse(
          day: day,
          periodFrom: span.first,
          periodTo: span.last,
          name: one.name,
          className: one.className,
          teacher: one.teacher,
          room: one.room,
          weekText: one.weekText,
          weeks: one.weeks,
          raw: one.raw,
        ));
      }
    }
  }

  if (courses.isEmpty) {
    throw TimetableError('这张表里没读到任何带周次的课程，确认一下是不是课表本身');
  }

  return ParsedTimetable(
    sheet: book.sheet,
    title: title,
    student: student,
    courses: courses,
    warnings: warnings,
    periodRows: periodRowList.map((e) => e.$2).toList(),
  );
}

/// 按表格里的行序，给出真正被课程用到的节次名。
List<String> periodLabels(ParsedTimetable parsed) {
  final used = <String>{};
  for (final c in parsed.courses) {
    used.add(c.periodFrom);
    used.add(c.periodTo);
  }
  return parsed.periodRows.where((pl) => used.contains(pl)).toList();
}

/// '1' -> '第 1 节'；'中午1' 这种原样保留。
String periodLabelText(String label) {
  final text = label.trim();
  if (RegExp(r'^\d+$').hasMatch(text)) return '第 $text 节';
  return text;
}

int totalLessons(ParsedTimetable parsed) {
  var n = 0;
  for (final c in parsed.courses) {
    n += c.weeks.length;
  }
  return n;
}

List<int> weekSpan(ParsedTimetable parsed) {
  final weeks = <int>{};
  for (final c in parsed.courses) {
    weeks.addAll(c.weeks);
  }
  final out = weeks.toList()..sort();
  return out;
}
