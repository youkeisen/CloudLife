import 'package:flutter/material.dart';

import '../store.dart';
import '../week.dart';
import 'courses_page.dart';
import 'home_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';
import '../weather_api.dart';
import 'weather_page.dart';

/// 底部五 Tab 的主框架：首页 / 课程 / 天气 / 备忘录 / 设置。
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

  /// 测试钩子：透传给设置页（假天气接口）。
  final WeatherApi? api;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<String> _labels = <String>['首页', '课程', '天气', '备忘录', '设置'];
  static const List<IconData> _icons = <IconData>[
    Icons.home_outlined,
    Icons.calendar_month_outlined,
    Icons.cloud_outlined,
    Icons.edit_note_outlined,
    Icons.settings_outlined,
  ];
  static const List<IconData> _iconsOn = <IconData>[
    Icons.home,
    Icons.calendar_month,
    Icons.cloud,
    Icons.edit_note,
    Icons.settings,
  ];

  String get _title => _labels[_index];

  /// 首页点了某条备忘录：切到备忘录 Tab 并直接打开那条（对齐电脑版行为）。
  void _openNoteFromHome(String noteId) {
    setState(() => _index = 3);
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

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(store: widget.store, onOpenNote: _openNoteFromHome),
      CoursesPage(store: widget.store),
      WeatherPage(store: widget.store),
      NotesPage(store: widget.store),
      SettingsPage(
        store: widget.store,
        onChanged: widget.onSettingsChanged,
        pickZip: widget.pickZip,
        api: widget.api,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        centerTitle: false,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <Widget>[
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(
              icon: Icon(_icons[i]),
              selectedIcon: Icon(_iconsOn[i]),
              label: _labels[i],
            ),
        ],
      ),
    );
  }
}
