import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据放在手机的应用私有目录里，不上云、不进公共空间。
  final docs = await getApplicationDocumentsDirectory();
  final store = Store(Directory(p.join(docs.path, 'MyDay')));
  store.init();

  runApp(MyDayApp(store: store));
}
