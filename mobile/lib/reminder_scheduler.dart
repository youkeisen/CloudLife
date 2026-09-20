/// 提醒的统一调度入口（v1.6.0）。
///
/// 三处会触发重排：App 启动、改完课程、改完提醒设置。都走这里的
/// [rescheduleAll]，免得同一套逻辑散落三份、哪天改漏一处。
///
/// 策略：**备忘录提醒全量重排 + 上课提醒全量重排，每次只排未来 7 天**。
/// 用「全量覆盖」而不是「增量新增」，是因为课表可能被删、被改时间、
/// 被换节次——增量会留下已经作废的旧通知。
library;

import 'lesson_reminder.dart';
import 'notification_service.dart';
import 'store.dart';

class ReminderScheduler {
  ReminderScheduler(this.store);

  final Store store;

  /// 重排所有提醒。任何一步失败都吞掉——提醒排不上不该影响用 App。
  Future<void> rescheduleAll({DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      await NotificationService.init();
    } catch (_) {
      return;
    }
    await _rescheduleNotes(at);
    await _rescheduleLessons(at);
  }

  Future<void> _rescheduleNotes(DateTime now) async {
    try {
      final notes = store.notes().notes;
      for (final n in notes) {
        final when = DateTime.tryParse(n.remindAt);
        // 已经过时的老提醒先撤掉，免得堆在系统里
        if (when == null || !when.isAfter(now)) {
          if (n.remindAt.isNotEmpty) {
            await NotificationService.cancel(n.id);
          }
          continue;
        }
        await NotificationService.scheduleFor(n.id, n.title, when);
      }
    } catch (_) {/* 排不上就算了 */}
  }

  Future<void> _rescheduleLessons(DateTime now) async {
    try {
      final settings = store.settings();
      final courses = store.courses();
      // 先把上一轮排的上课提醒全撤掉（id 是每节课固定的，直接按 id 取消）
      for (final week in courses.weeks.keys) {
        for (final l in courses.week(week)) {
          await NotificationService.cancelId(
              'lesson:${l.id}'.hashCode & 0x7fffffff);
        }
      }
      final list = lessonReminders(
        settings: settings,
        courses: courses,
        from: now,
        days: 7,
      );
      for (final r in list) {
        await NotificationService.scheduleRaw(
            r.noteId, r.title, r.body, r.when);
      }
    } catch (_) {/* 排不上就算了 */}
  }
}

/// 便捷函数：给一个 store，重排所有提醒。
/// 界面里改完东西随手调它，不用自己 new 一个对象。
Future<void> rescheduleAllReminders(Store store, {DateTime? now}) =>
    ReminderScheduler(store).rescheduleAll(now: now);
