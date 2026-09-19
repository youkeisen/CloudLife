/// 导入课表：从解析结果生成预览，确认后按周写进课程数据。
///
/// 对应电脑版 server.py 的 `_import_plan` / `api_import`：
/// - 预览只解析不落盘；
/// - 导入前先自动留一份安全备份，手滑了能退回来；
/// - 节次按名字复用，缺的补建（时间留空，不替用户猜作息）；
/// - merge 追加 / overwrite 覆盖整周。
library;

import 'models.dart';
import 'store.dart';
import 'backup.dart';
import 'timetable.dart';

class PlanCourse {
  PlanCourse({
    required this.day,
    required this.dayText,
    required this.periodFrom,
    required this.periodTo,
    required this.name,
    required this.className,
    required this.teacher,
    required this.room,
    required this.weekText,
    required this.weeks,
  });

  final int day;
  final String dayText;
  final String periodFrom;
  final String periodTo;
  final String name;
  final String className;
  final String teacher;
  final String room;
  final String weekText;
  final List<int> weeks;

  int get lessonCount => weeks.length;
}

class ImportPlan {
  ImportPlan({
    required this.sheet,
    required this.title,
    required this.student,
    required this.courses,
    required this.warnings,
    required this.periodLabels,
    required this.newPeriods,
    required this.reusePeriods,
    required this.weeks,
    required this.totalLessons,
  });

  final String sheet;
  final String title;
  final String student;
  final List<PlanCourse> courses;
  final List<String> warnings;
  final List<String> periodLabels;
  final List<String> newPeriods;
  final List<String> reusePeriods;
  final List<int> weeks;
  final int totalLessons;

  int get courseCount => courses.length;
}

/// 只解析给用户看，一个字都不写盘。
ImportPlan buildImportPlan(List<int> raw, Settings settings) {
  final parsed = parseTimetable(raw);
  final labels = periodLabels(parsed).map(periodLabelText).toList();
  final existing = settings.periods.map((p) => p.label.trim()).toSet();
  final courses = <PlanCourse>[];
  for (final c in parsed.courses) {
    courses.add(PlanCourse(
      day: c.day,
      dayText: dayCn[c.day] ?? '',
      periodFrom: periodLabelText(c.periodFrom),
      periodTo: periodLabelText(c.periodTo),
      name: c.name,
      className: c.className,
      teacher: c.teacher,
      room: c.room,
      weekText: c.weekText,
      weeks: c.weeks,
    ));
  }
  return ImportPlan(
    sheet: parsed.sheet,
    title: parsed.title,
    student: parsed.student,
    courses: courses,
    warnings: parsed.warnings,
    periodLabels: labels,
    newPeriods: labels.where((l) => !existing.contains(l)).toList(),
    reusePeriods: labels.where(existing.contains).toList(),
    weeks: weekSpan(parsed),
    totalLessons: totalLessons(parsed),
  );
}

/// 按给定顺序确保这些节次存在（名称相同的直接复用）。
///
/// 返回 (label -> id 的映射, 新建出来的节次列表)。
/// 时间一律留空，由用户自己填——导入不替用户猜作息。
(Map<String, String>, List<Period>) ensurePeriods(Store store, List<String> labels) {
  final settings = store.settings();
  final periods = List<Period>.from(settings.periods);
  final usedIds = periods.map((p) => p.id).toSet();
  final byLabel = <String, Period>{};
  for (final p in periods) {
    byLabel.putIfAbsent(p.label.trim(), () => p);
  }

  String nextId() {
    var n = 1;
    while (usedIds.contains('p$n')) {
      n++;
    }
    final id = 'p$n';
    usedIds.add(id);
    return id;
  }

  final mapping = <String, String>{};
  final created = <Period>[];
  for (final raw in labels) {
    final label = raw.trim();
    if (label.isEmpty) continue;
    final hit = byLabel[label];
    if (hit != null) {
      mapping[label] = hit.id;
      continue;
    }
    final id = nextId();
    final period = Period(id: id, label: label, start: '', end: '');
    periods.add(period);
    byLabel[label] = period;
    mapping[label] = id;
    created.add(period);
  }
  settings.periods = periods;
  store.saveSettings(settings);
  return (mapping, created);
}

class ImportResult {
  ImportResult({
    required this.mode,
    required this.added,
    required this.weeks,
    required this.createdPeriods,
    required this.backupFile,
  });

  final String mode;
  final int added;
  final List<int> weeks;
  final List<String> createdPeriods;
  final String backupFile;
}

/// 把解析出来的课按周写进去。merge 追加，overwrite 覆盖整周。
ImportResult applyImport(
  Store store,
  ImportPlan plan,
  ParsedTimetable parsed,
  String mode,
) {
  if (mode != 'merge' && mode != 'overwrite') {
    throw ArgumentError('未知的导入方式：$mode');
  }
  // 导入前先自动留一份，手滑了能退回来
  final backupFile = safetyBackup(store);

  final (mapping, created) = ensurePeriods(store, plan.periodLabels);
  final byWeek = <int, List<Lesson>>{};
  for (final c in parsed.courses) {
    final startId = mapping[periodLabelText(c.periodFrom)];
    final endLabel = periodLabelText(c.periodTo);
    final endId = mapping[endLabel];
    if (startId == null) continue;
    final note = c.className.isEmpty
        ? '${c.weekText}周'
        : '${c.className} ${c.weekText}周';
    final item = Lesson(
      id: '',
      day: c.day,
      slot: startId,
      spanEnd: (endId != null && endId != startId) ? endId : '',
      name: c.name,
      location: c.room,
      teacher: c.teacher,
      note: note,
      color: '',
    );
    for (final w in c.weeks) {
      byWeek.putIfAbsent(w, () => <Lesson>[]).add(item);
    }
  }

  final courses = store.courses();
  var added = 0;
  final touched = <int>[];
  final weeks = byWeek.keys.toList()..sort();
  for (final week in weeks) {
    final fresh = <Lesson>[];
    var i = 0;
    for (final lesson in byWeek[week]!) {
      fresh.add(lesson.copyWith(id: '${store.newId('c')}${i++}'));
    }
    if (mode == 'overwrite') {
      courses.setWeek(week, fresh);
    } else {
      courses.setWeek(week, <Lesson>[...courses.week(week), ...fresh]);
    }
    added += fresh.length;
    touched.add(week);
  }
  store.saveCourses(courses);

  return ImportResult(
    mode: mode,
    added: added,
    weeks: touched,
    createdPeriods: created.map((p) => p.label).toList(),
    backupFile: backupFile,
  );
}
