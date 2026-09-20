/// 开机后的后台重排入口（v1.6.0，需求文档第 8 条）。
///
/// 由安卓侧的 `BootReceiver` / `BootRescheduleWorker` 拉起一个无界面
/// Flutter 引擎执行这里 —— **不弹界面、不建前台服务**，跑完就退出。
///
/// 做的事和 App 启动时一样：读本地数据，把未来一周的上课提醒和还没到的
/// 备忘录提醒重新排进系统闹钟。之所以要重排，是因为安卓重启会清掉
/// AlarmManager 里已排的闹钟（flutter_local_notifications 自带的开机重排
/// 只认它自己收得到的那部分，我们自己再补一遍更稳）。
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'reminder_scheduler.dart';
import 'store.dart';

/// 必须是顶层函数 + `vm:entry-point`，否则 release 包里会被 tree-shake 掉，
/// 开机时找不到入口就静默失败。
@pragma('vm:entry-point')
Future<void> bootMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final docs = await getApplicationDocumentsDirectory();
    final store = Store(Directory(p.join(docs.path, 'MyDay')));
    store.init();
    // **headless: true** —— 这里是无界面引擎，没有 Activity。
    // 走这个模式才不会去申请通知权限（v1.7.6 修的闪退：
    // 无 Activity 时申请权限会崩进程，表现就是「通知没弹 + App 崩了」）。
    await rescheduleAllReminders(store, headless: true);
  } catch (_) {
    // 开机阶段失败不能崩，也不能吵用户
  }
  // 安卓侧不等待返回值，跑完自然结束即可（引擎由 Kotlin 定时销毁）。
}
