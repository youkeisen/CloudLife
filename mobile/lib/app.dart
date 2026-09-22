import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'store.dart';
import 'ui/design.dart';
import 'ui/home_shell.dart';
import 'weather_api.dart';

class MyDayApp extends StatefulWidget {
  const MyDayApp({super.key, required this.store, this.pickZip, this.pickDir, this.api});

  final Store store;

  /// 测试钩子：透传给设置页（选备份 zip 的假实现）。
  final Future<List<int>?> Function()? pickZip;

  /// 测试钩子：透传给设置页（选备份目录的假实现）。
  final Future<String?> Function()? pickDir;

  /// 测试钩子：透传给设置页/功能页（假天气接口）。
  final WeatherApi? api;

  /// 主色：靛蓝（v2.0 换掉刺眼的纯蓝）。深浅色各一档，色值在 [Tone] 里。
  static const Color seedLight = Color(0xFF2B54C8);
  static const Color seedDark = Color(0xFF6B8CF0);

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
      title: 'CloudLife',
      debugShowCheckedModeBanner: false,
      // 界面中文化：日期选择器的 Cancel/OK、星期缩写、月份名等内置文案。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeModeFromSetting(widget.store.settings().theme),
      home: HomeShell(
        store: widget.store,
        onSettingsChanged: _onSettingsChanged,
        pickZip: widget.pickZip,
        pickDir: widget.pickDir,
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

/// 主题（v2.0）：令牌全部来自 [Tone] / [Type] / [R]。
///
/// 底色是**不透明实色** —— 任何 Scaffold 都自带正确底色，
/// 不会再有「忘了垫背景变黑屏」那类 bug。
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final tone = dark ? Tone.dark : Tone.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: dark ? MyDayApp.seedDark : MyDayApp.seedLight,
    brightness: brightness,
  ).copyWith(
    primary: tone.primary,
    onPrimary: tone.onPrimary,
    primaryContainer: tone.primarySoft,
    onPrimaryContainer: tone.primary,
    secondary: tone.primary,
    onSecondary: tone.onPrimary,
    tertiary: tone.accent,
    error: tone.danger,
    onError: tone.onPrimary,
    surface: tone.surface,
    onSurface: tone.ink900,
    onSurfaceVariant: tone.ink500,
    outline: tone.ink400,
    outlineVariant: tone.ink200,
    surfaceContainerHighest: tone.ink100,
    surfaceContainerHigh: tone.ink100,
    surfaceContainerLow: tone.surfaceSunk,
    surfaceContainerLowest: tone.surface,
  );

  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: tone.bg,
    // 正文默认色 = 主文字色，没显式给颜色的 Text 都落在这一档。
    textTheme: base.textTheme.apply(
      bodyColor: tone.ink900,
      displayColor: tone.ink900,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tone.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      centerTitle: true,
      // 二级页标题：17 / Bold 居中（原型里的 nav-bar）。
      titleTextStyle: Type.h3
          .copyWith(fontSize: 17, color: tone.ink900, letterSpacing: -0.17),
      iconTheme: IconThemeData(color: tone.ink700, size: 22),
      actionsIconTheme: IconThemeData(color: tone.ink700, size: 22),
    ),
    cardTheme: CardThemeData(
      color: tone.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tone.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg)),
      titleTextStyle: Type.h2.copyWith(color: tone.ink900),
      contentTextStyle: Type.body.copyWith(color: tone.ink700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tone.surface,
      modalBackgroundColor: tone.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: tone.surface,
      hintStyle: Type.body.copyWith(color: tone.ink300),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.sm),
        borderSide: BorderSide(color: tone.ink200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.sm),
        borderSide: BorderSide(color: tone.ink200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.sm),
        borderSide: BorderSide(color: tone.primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tone.ink100,
      selectedColor: tone.primarySoft,
      side: BorderSide(color: tone.ink200),
      labelStyle: Type.sm.copyWith(color: tone.ink500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
      showCheckmark: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tone.ink900,
      contentTextStyle: Type.body.copyWith(color: tone.surface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
    ),
    dividerTheme: DividerThemeData(color: tone.ink100, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: tone.primary,
      textColor: tone.ink900,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (s) => s.contains(WidgetState.selected) ? tone.onPrimary : tone.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (s) => s.contains(WidgetState.selected) ? tone.primary : tone.ink100,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
        (s) => s.contains(WidgetState.selected) ? tone.primary : tone.ink200,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (s) => s.contains(WidgetState.selected) ? tone.primary : null,
      ),
      side: BorderSide(color: tone.ink300, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: tone.primary),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tone.primary,
      selectionColor: tone.primarySoft,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tone.primary,
      foregroundColor: tone.onPrimary,
      elevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.lg)),
      ),
    ),
  );
}
