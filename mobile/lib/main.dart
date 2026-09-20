import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'reminder_scheduler.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据放在手机的应用私有目录里，不上云、不进公共空间。
  final docs = await getApplicationDocumentsDirectory();
  final store = Store(Directory(p.join(docs.path, 'MyDay')));
  store.init();

  // 先把界面跑起来！通知初始化/重排提醒放后台做——v1.5.0 放在 runApp 前，
  // 插件一慢就卡白屏（凯森反馈过）。
  runApp(MyDayApp(store: store));

  // 备忘录提醒 + 上课提醒一起重排（v1.6.0：上课提醒只排未来 7 天，
  // 每次启动续一周，安卓通知数量上限扛得住）。
  unawaited(rescheduleAllReminders(store).catchError((_) {}));
}
