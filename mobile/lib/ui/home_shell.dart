import 'dart:ui';

import 'package:flutter/material.dart';

import '../store.dart';
import '../weather_api.dart';
import '../week.dart';
import 'features_page.dart';
import 'glass.dart';
import 'home_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';

/// 主框架：底部悬浮胶囊栏（首页 / 功能 / ＋ / 设置）。
///
/// 课程、天气、备忘录都收进「功能」页里了，底栏只留三个主入口 +
/// 一个凸起的「＋」（快速新建备忘录）——参考图上那种悬浮式底栏。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    this.onSettingsChanged,
    this.pickZip,
    this.api,
  });

  final Store store;

  /// 设置页有改动时向上通知（MyApp 重读设置，让外观等立即生效）。
  final VoidCallback? onSettingsChanged;

  /// 测试钩子：透传给设置页（选备份 zip 的假实现）。
  final Future<List<int>?> Function()? pickZip;

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
    Icons.widgets_outlined,
    Icons.settings_outlined,
  ];
  static const List<IconData> _iconsOn = <IconData>[
    Icons.home,
    Icons.widgets,
    Icons.settings,
  ];

  String get _title => _labels[_index];

  /// 首页点了某条备忘录：直接打开那条（不再切 Tab，备忘录已经收进功能页）。
  void _openNoteFromHome(String noteId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteEditPage(store: widget.store, noteId: noteId),
    ));
  }

  /// 顶栏右侧那个「第几教学周」的小圆牌；教学周没设置时显示灰色提示。
  Widget _weekPill() {
    final week = weekOf(DateTime.now(), widget.store.settings().week1Monday);
    if (week == null) {
      return Container(
        key: const ValueKey('week-pill-off'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('教学周未设置', style: TextStyle(fontSize: 12)),
      );
    }
    return Container(
      key: const ValueKey('week-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('第 $week 教学周', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _barItem(int i) {
    final cs = Theme.of(context).colorScheme;
    final on = _index == i;
    return Expanded(
      child: InkWell(
        key: ValueKey('tab-${_labels[i]}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _index = i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(on ? _iconsOn[i] : _icons[i],
                size: 22, color: on ? cs.primary : cs.outline),
            const SizedBox(height: 2),
            Text(_labels[i],
                style: TextStyle(
                  fontSize: 11,
                  color: on ? cs.primary : cs.outline,
                  fontWeight: on ? FontWeight.w500 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }

  /// 底栏：一块悬浮的玻璃胶囊，三个入口平分宽度。
  Widget _floatingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Glass(
        radius: 26,
        blur: 26,
        child: SizedBox(
          height: 62,
          child: Row(
            children: <Widget>[
              _barItem(0),
              _barItem(1),
              _barItem(2),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(store: widget.store, onOpenNote: _openNoteFromHome),
      FeaturesPage(store: widget.store, api: widget.api, pickZip: widget.pickZip),
      SettingsPage(
        store: widget.store,
        onChanged: widget.onSettingsChanged,
        pickZip: widget.pickZip,
        api: widget.api,
      ),
    ];
    // 整个壳子坐在渐变背景上，玻璃面板才能透出颜色（Liquid Glass）。
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: AppBar(
          title: Text(_title),
          centerTitle: false,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.25),
              ),
            ),
          ),
          actions: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: _weekPill()),
            ),
          ],
        ),
        body: KeyedSubtree(
          key: ValueKey<String>(_labels[_index]),
          child: pages[_index],
        ),
        bottomNavigationBar: _floatingBar(),
      ),
    );
  }
}
