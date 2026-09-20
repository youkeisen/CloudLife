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

/// 正在跑的那次重排（v1.7.6）。
///
/// 为什么需要：App 启动、改设置、改课表、开机广播都可能几乎同时触发重排。
/// 并发跑同一套「全量重排」会重复排通知、加重插件负担，也更容易撞上
/// 「先撤后加」的中间态。所以**同时只允许一次**，后来的直接复用前一次的结果。
Future<void>? _inFlight;

class ReminderScheduler {
  ReminderScheduler(this.store);

  final Store store;

  /// 重排所有提醒。任何一步失败都吞掉——提醒排不上不该影响用 App。
  ///
  /// [headless] 为 true 时（开机广播拉起的无界面引擎），初始化走
  /// [NotificationService.initHeadless]：**不申请权限**。
  /// 没有 Activity 时申请权限会崩进程（v1.7.6 修的闪退）。
  Future<void> rescheduleAll({DateTime? now, bool headless = false}) async {
    // 已经有在跑的就跟着它，不重复排（v1.7.6）
    final running = _inFlight;
    if (running != null) return running;

    final task = _doReschedule(now ?? DateTime.now(), headless);
    _inFlight = task;
    try {
      await task;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _doReschedule(DateTime at, bool headless) async {
    try {
      if (headless) {
        await NotificationService.initHeadless();
      } else {
        await NotificationService.init();
      }
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

      // v1.7.4：**先算出要排哪几条，再动旧的**。
      //
      // 原来的写法是「先把所有课的通知全 cancel 掉，再逐条 schedule」。
      // 万一 schedule 中途抛异常（闹钟数量超限、插件抽风），catch 会把它吞掉，
      // 结果是**旧的全撤了、新的一条没排上**——用户那边看起来就是
      // 「本来能响的提醒突然全没了」，而且没有任何报错。
      // 现在先算好列表，算出来是空的就直接 return，不动旧的。
      final list = lessonReminders(
        settings: settings,
        courses: courses,
        from: now,
        days: 7,
      );
      if (list.isEmpty) return;

      // 只撤「旧列表里有、新列表里没有」的那些，以及改了时间的。
      // 按 id 比对，排过的一律重排（时间可能变了）。
      final wanted = <int>{for (final r in list) r.noteId};
      for (final week in courses.weeks.keys) {
        for (final l in courses.week(week)) {
          final id = 'lesson:${l.id}'.hashCode & 0x7fffffff;
          if (wanted.contains(id)) continue; // 还要排的，交给下面覆盖
          await NotificationService.cancelId(id);
        }
      }
      for (final r in list) {
        await NotificationService.scheduleRaw(
            r.noteId, r.title, r.body, r.when);
      }
    } catch (_) {/* 排不上就算了 */}
  }
}

/// 便捷函数：给一个 store，重排所有提醒。
/// 界面里改完东西随手调它，不用自己 new 一个对象。
Future<void> rescheduleAllReminders(Store store,
        {DateTime? now, bool headless = false}) =>
    ReminderScheduler(store).rescheduleAll(now: now, headless: headless);
