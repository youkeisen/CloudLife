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
      title: '云生活',
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
  final dark = brightness == Brightness.dark;
  // Liquid Glass：所有容器半透明 + 大圆角 + 无实体投影层级，
  // 玻璃质感靠 Glass 组件的模糊与描边，主题只负责把底色调透。
  const glassCardLight = Color(0x99FFFFFF);
  const glassCardDark = Color(0x8C22252E);
  final glassCard = dark ? glassCardDark : glassCardLight;
  final outline = dark ? const Color(0x24FFFFFF) : const Color(0x66FFFFFF);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      color: glassCard,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: outline),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xE622252E) : const Color(0xF2FFFFFF),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark ? const Color(0x59FFFFFF) : const Color(0x66FFFFFF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0x661E2028) : const Color(0x66FFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 66,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xD922252E) : const Color(0xE6202228),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1),
  );
}
