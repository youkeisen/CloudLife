/// 本地通知：备忘录定时提醒（v1.5.0）+ 上课提醒（v1.6.0）。
///
/// - 用 flutter_local_notifications 的定时通知，安卓上由系统闹钟调度，
///   App 被杀也能响（插件自带开机重排）；
/// - 用「非精确闹钟」模式，不申请精确闹钟权限，省一堆兼容坑；
/// - 通知 id 用各自 id 的哈希，取消/重排都按它来。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    // 用户在国内，直接按东八区排（不引原生时区库，少一半体积）。
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        const InitializationSettings(android: androidInit));
    // Android 13+ 要运行时申请通知权限
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    _ready = true;
  }

  static int _idOf(String noteId) => noteId.hashCode & 0x7fffffff;

  static const AndroidNotificationDetails _noteDetails =
      AndroidNotificationDetails(
    'note_reminder',
    '备忘录提醒',
    channelDescription: '备忘录的定时提醒通知',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const AndroidNotificationDetails _lessonDetails =
      AndroidNotificationDetails(
    'lesson_reminder',
    '上课提醒',
    channelDescription: '上课前按设置的提前量提醒',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// 排一条提醒。[when] 应该是未来的本地时间。
  static Future<void> scheduleFor(
    String noteId,
    String title,
    DateTime when, {
    String body = '到时间啦，点开看看',
    bool lesson = false,
  }) async {
    await init();
    await _plugin.zonedSchedule(
      _idOf(noteId),
      title.isEmpty ? '备忘录提醒' : title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(android: lesson ? _lessonDetails : _noteDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// 按 id 排一条（上课提醒用：id 由 lesson_reminder 算好）。
  static Future<void> scheduleRaw(
    int id,
    String title,
    String body,
    DateTime when,
  ) async {
    await init();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(android: _lessonDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// 取消某条备忘录的提醒（删备忘录、清空提醒时间时调用）。
  static Future<void> cancel(String noteId) async {
    await init();
    await _plugin.cancel(_idOf(noteId));
  }

  /// 按通知 id 取消（上课提醒用）。
  static Future<void> cancelId(int id) async {
    await init();
    await _plugin.cancel(id);
  }
}
