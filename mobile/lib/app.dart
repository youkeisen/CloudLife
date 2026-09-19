import 'package:flutter/material.dart';

import 'store.dart';
import 'ui/home_shell.dart';
import 'weather_api.dart';

class MyDayApp extends StatefulWidget {
  const MyDayApp({super.key, required this.store, this.pickZip, this.api});

  final Store store;

  /// 测试钩子：透传给设置页（选备份 zip 的假实现）。
  final Future<List<int>?> Function()? pickZip;

  /// 测试钩子：透传给设置页（假天气接口）。
  final WeatherApi? api;

  /// 主色跟电脑版保持一致：浅色 #4B5BF7，深色亮一档 #7B86FF。
  static const Color seedLight = Color(0xFF4B5BF7);
  static const Color seedDark = Color(0xFF7B86FF);

  @override
  State<MyDayApp> createState() => _MyDayAppState();
}

class _MyDayAppState extends State<MyDayApp> {
  /// 设置页改了外观（或还原了备份）后走到这里，重读设置重建整棵树。
  void _onSettingsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyDay',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeModeFromSetting(widget.store.settings().theme),
      home: HomeShell(
        store: widget.store,
        onSettingsChanged: _onSettingsChanged,
        pickZip: widget.pickZip,
        api: widget.api,
      ),
    );
  }
}

/// settings.theme 的取值与电脑版一致：system / light / dark。
ThemeMode themeModeFromSetting(String v) {
  switch (v) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brightness == Brightness.dark
        ? MyDayApp.seedDark
        : MyDayApp.seedLight,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF17181C)
        : const Color(0xFFF4F5F8),
  );
}
