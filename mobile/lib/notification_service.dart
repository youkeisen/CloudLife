/// 本地通知：备忘录定时提醒（v1.5.0）+ 上课提醒（v1.6.0）。
///
/// - 用 flutter_local_notifications 的定时通知，安卓上由系统闹钟调度，
///   App 被杀也能响（插件自带开机重排）；
/// - 用「非精确闹钟」模式，不申请精确闹钟权限，省一堆兼容坑；
/// - 通知 id 用各自 id 的哈希，取消/重排都按它来。
library;

import 'dart:io' show Platform;

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
    // 通知小图标必须是**纯白剪影**（安卓只取 alpha 通道、再按需染色）。
    // v1.7.6：原来用的是 @mipmap/ic_launcher（彩色图），
    // 在通知栏里会显示成白方块，部分国产 ROM 还会因图标不合规**崩进程** ——
    // 凯森 2026-09-20 反馈「到点没弹通知并且闪退」，
    // 闪退就发生在通知要弹出的那一刻。
    // 现在用专门的 drawable/ic_notification.png（由
    // tools/make_notification_icon.py 从 Cloud logo 的倒三角生成）。
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    await _plugin.initialize(
        const InitializationSettings(android: androidInit));
    // Android 13+ 要运行时申请通知权限。
    //
    // **v1.7.6 修闪退**：申请权限必须有 Activity 才能弹框。开机的
    // BootReceiver 会拉一个**无界面引擎**跑重排（见 BootRescheduleWorker），
    // 那里没有 Activity，调这个方法会直接崩 —— 表现就是「通知没弹、App 崩了」。
    // 所以用一个开关把它关掉：只有真正带界面的调用方（main / 设置页）才申请。
    if (_requestPermissionOnInit) {
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      } catch (_) {
        // 申请失败不该影响后面排通知
      }
    }
    _ready = true;
  }

  /// 初始化时要不要顺手申请通知权限（默认要）。
  /// 开机重排（无界面引擎）会先把它设成 false —— 那里没有 Activity。
  static bool _requestPermissionOnInit = true;

  /// 给「无界面引擎」用的初始化：不申请权限、不弹任何框（v1.7.6）。
  static Future<void> initHeadless() async {
    _requestPermissionOnInit = false;
    await init();
  }

  /// 测试钩子（v1.7.4）：`flutter test` 跑在桌面上，没有真的通知插件。
  /// 设了就把下面三个查询方法短路成这里给的值，好测「权限被拒要提示」那条路。
  /// 传 null 还原成走真实插件。
  static bool? debugForceEnabled;
  static bool? debugForceExact;

  static void debugSetPermissions({bool? enabled, bool? exact}) {
    debugForceEnabled = enabled;
    debugForceExact = exact;
  }

  /// 通知是否真的能弹出来（v1.7.4）。
  ///
  /// **这是「到时间不提醒」最隐蔽的原因**：安卓 13+ 的 `POST_NOTIFICATIONS`
  /// 只在 [init] 里申请一次。用户第一次装的时候要是点了「不允许」，
  /// 之后 App 再也不会问，排进去的通知会被系统**静默丢掉**——
  /// 界面上一点提示都没有，看着就像「提醒功能坏了」。
  /// 非安卓没有这个概念，直接 true。
  static Future<bool> notificationsEnabled() async {
    if (debugForceEnabled != null) return debugForceEnabled!;
    if (!Platform.isAndroid) return true;
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true; // 查不出来就当没事，别误报
    }
  }

  /// 系统是否允许本应用排**精确**闹钟（v1.7.4）。
  ///
  /// 我们用的是 `inexactAllowWhileIdle`（非精确），安卓会把这类闹钟
  /// **批量攒起来延后触发**，省电模式下可能晚十几分钟甚至更久。
  /// 这个查询只用来在设置页提示「想让提醒准点可以开精确闹钟」，
  /// 不查也不影响排通知。
  static Future<bool> exactAlarmsAllowed() async {
    if (debugForceExact != null) return debugForceExact!;
    if (!Platform.isAndroid) return true;
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 再申请一次通知权限（v1.7.4）。
  /// 用户之前点过「不允许」的话，再调一次也不一定弹（系统可能直接拒），
  /// 所以设置页那边还要给「去系统设置开」的兜底入口。
  static Future<bool> requestPermissionAgain() async {
    if (!Platform.isAndroid) return true;
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      return await notificationsEnabled();
    } catch (_) {
      return false;
    }
  }

  /// 查系统里**实际排着的**通知（v1.7.5）。
  ///
  /// 这是排查「到点不响」最有用的一个量：它问的是系统本身，
  /// 而不是我们「以为自己排了」。如果这里是 0，说明问题在排的环节；
  /// 如果这里有一堆，说明排成功了、是权限/拦截把通知压住了。
  ///
  /// **非安卓返回 null**（而不是空列表）：桌面/测试环境压根没有系统闹钟，
  /// 返回 `[]` 会让界面显示成「系统里一条都没有」，把用户往错误方向带。
  /// null 让界面说「查不到」。
  ///
  /// 查不到的原因会记在 [lastPendingError] 里，界面上可以显示出来 ——
  /// 只有「查不到」三个字的话，下次再出问题还是得重新猜一遍（v1.7.6）。
  static String? lastPendingError;

  static Future<List<PendingNotificationRequest>?> pendingRequests() async {
    if (!Platform.isAndroid) return null;
    try {
      await init();
      return await _plugin.pendingNotificationRequests();
    } catch (e) {
      lastPendingError = e.toString();
      return null;
    }
  }

  static int _idOf(String noteId) => noteId.hashCode & 0x7fffffff;

  static const AndroidNotificationDetails _noteDetails =
      AndroidNotificationDetails(
    'note_reminder',
    '备忘录提醒',
    channelDescription: '备忘录的定时提醒通知',
    importance: Importance.high,
    priority: Priority.high,
    // v1.7.6：显式指定纯白剪影小图标，别让它回退到彩色 launcher 图标
    icon: '@drawable/ic_notification',
  );

  static const AndroidNotificationDetails _lessonDetails =
      AndroidNotificationDetails(
    'lesson_reminder',
    '上课提醒',
    channelDescription: '上课前按设置的提前量提醒',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@drawable/ic_notification',
  );

  /// 排一条提醒时用哪种闹钟模式（v1.7.4）。
  ///
  /// 原来是死用 `inexactAllowWhileIdle`，安卓会把非精确闹钟**攒起来延后触发**，
  /// 省电模式下晚十几分钟很常见——用户看到的就是「到点没提醒，过一会儿才冒出来」。
  /// 现在优先用 `exactAllowWhileIdle`（准点 + 待机也响）；只有在拿不到
  /// 精确闹钟权限时才退回非精确，保证低版本/受限ROM上照样能响。
  static Future<AndroidScheduleMode> _mode() async {
    if (debugForceExact != null) {
      return debugForceExact!
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    }
    if (!Platform.isAndroid) return AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final ok = await android?.canScheduleExactNotifications() ?? false;
      return ok
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

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
      androidScheduleMode: await _mode(),
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
      androidScheduleMode: await _mode(),
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
