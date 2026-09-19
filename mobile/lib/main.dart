import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'notification_service.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据放在手机的应用私有目录里，不上云、不进公共空间。
  final docs = await getApplicationDocumentsDirectory();
  final store = Store(Directory(p.join(docs.path, 'MyDay')));
  store.init();

  // 备忘录定时提醒：初始化通知 + 把还没到点的提醒重新排上
  await NotificationService.init();
  for (final n in store.notes().notes) {
    final at = DateTime.tryParse(n.remindAt);
    if (at != null && at.isAfter(DateTime.now())) {
      await NotificationService.scheduleFor(n.id, n.title, at);
    }
  }

  runApp(MyDayApp(store: store));
}
