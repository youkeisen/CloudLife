import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../store.dart';
import '../weather_api.dart';
import 'courses_page.dart';
import 'design.dart';
import 'features_page.dart';
import 'home_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';
import 'weather_page.dart';

/// 主框架：三个入口（首页 / 功能 / 设置）+ 底部导航。
///
/// v2.0 起**不再有全局 AppBar** —— 每个页面自己在内容顶部画页头
/// （首页是「问候语 + 周次胶囊」，功能/设置是「大标题 + 副标题 + 周次胶囊」），
/// 这样首页能省掉重复的大标题，把 90px 让给内容。
///
/// 底部栏也从「大蓝胶囊」改成**白底 + 顶部指示条**：导航不该是页面上最重的元素。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    this.onSettingsChanged,
    this.pickZip,
    this.pickDir,
    this.api,
  });

  final Store store;

  /// 设置页有改动时向上通知（MyApp 重读设置，让外观等立即生效）。
  final VoidCallback? onSettingsChanged;

  /// 测试钩子：透传给设置页（选备份 zip 的假实现）。
  final Future<List<int>?> Function()? pickZip;

  /// 测试钩子：透传给设置页（选备份目录的假实现）。
  final Future<String?> Function()? pickDir;

  /// 测试钩子：透传给设置页/功能页（假天气接口）。
  final WeatherApi? api;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<String> _labels = <String>['首页', '功能', '设置'];
  static const List<IconData> _icons = <IconData>[
    Icons.home_outlined,
    Icons.grid_view_rounded,
    Icons.settings_outlined,
  ];
  static const List<IconData> _iconsOn = <IconData>[
    Icons.home_rounded,
    Icons.grid_view_rounded,
    Icons.settings_rounded,
  ];

  /// 首页点了某条备忘录：直接打开那条。
  void _openNoteFromHome(String noteId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteEditPage(store: widget.store, noteId: noteId),
    ));
  }

  /// 首页小卡片/「全部 ›」跳到对应的整页。
  void _pushPage(String title, Widget body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
      ),
    ));
  }

  /// 底栏里的一个入口。
  Widget _tabItem(int i) {
    final tone = Tone.of(context);
    final on = _index == i;
    final color = on ? tone.primary : tone.ink400;
    return Expanded(
      child: InkWell(
        key: ValueKey('tab-${_labels[i]}'),
        onTap: () => setState(() => _index = i),
        child: Stack(
          children: <Widget>[
            // 顶部指示条：激活态靠它表达，不用整块蓝底抢注意力。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: const CurveCubic(),
                  width: on ? 26 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: tone.primary,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: const CurveCubic(),
                    offset: Offset(0, on ? -0.04 : 0),
                    child: Icon(
                      on ? _iconsOn[i] : _icons[i],
                      size: 22,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部导航：白底半透明 + 背景模糊 + 顶部 1px 描边，高 60（另加安全区）。
  ///
  /// 背景色必须包住**含安全区在内的整个高度**：以前色画在安全区
  /// Padding 的里面，底下那条露出页面内容（文字从导航下面透过去）。
  Widget _tabBar() {
    final tone = Tone.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.surface.withValues(alpha: .88),
            border: Border(top: BorderSide(color: tone.ink200)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: SizedBox(
              height: 60,
              child: Row(
                children: <Widget>[
                  _tabItem(0),
                  _tabItem(1),
                  _tabItem(2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        store: widget.store,
        api: widget.api,
        onOpenNote: _openNoteFromHome,
        onOpenWeather: () =>
            _pushPage('天气', WeatherPage(store: widget.store, api: widget.api)),
        onOpenNotes: () => _pushPage('备忘录', NotesPage(store: widget.store)),
        onOpenCourses: () => _pushPage('课程', CoursesPage(store: widget.store)),
      ),
      FeaturesPage(store: widget.store, api: widget.api, pickZip: widget.pickZip),
      SettingsPage(
        store: widget.store,
        onChanged: widget.onSettingsChanged,
        pickZip: widget.pickZip,
        pickDir: widget.pickDir,
        api: widget.api,
      ),
    ];
    return Scaffold(
      backgroundColor: Tone.of(context).bg,
      extendBody: true,
      // 没有 AppBar：内容自己在最上面画页头，这里只避开状态栏。
      body: SafeArea(
        top: true,
        bottom: false,
        child: KeyedSubtree(
          key: ValueKey<String>(_labels[_index]),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: _tabBar(),
    );
  }
}
