/// 功能页（v2.0 重排）：原来是一列四张长卡，一屏看不全。
///
/// 现在改成 **2×2 宫格** —— 四个模块一屏都在，每格带彩色图标和一条关键数据
/// （本周几节课 / 当前温度 / 几条备忘 / 本月花了多少）。下面补一排快捷操作。
library;

import 'package:flutter/material.dart';

import '../ledger_logic.dart';
import '../models.dart';
import '../notes_logic.dart';
import '../store.dart';
import '../weather_api.dart';
import '../week.dart';
import 'courses_page.dart';
import 'design.dart';
import 'ledger_edit_page.dart';
import 'ledger_page.dart';
import 'notes_page.dart';
import 'weather_page.dart';

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({
    super.key,
    required this.store,
    this.api,
    this.pickZip,
  });

  final Store store;
  final WeatherApi? api;
  final Future<List<int>?> Function()? pickZip;

  void _open(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
      ),
    ));
  }

  /// 「写备忘」：建一条空的直接进编辑页（和备忘录页的「新建」同一条路）。
  void _newNote(BuildContext context) {
    final notes = store.notes();
    final n = newEmptyNote(notes, id: store.newId('n'), nowIso: Store.nowIso());
    store.saveNotes(notes);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteEditPage(store: store, noteId: n.id),
    ));
  }

  /// 天气那格的关键数据：优先用缓存里的实况。
  String _weatherStat() {
    final city = store.settings().weatherCity;
    if (!city.isSet) return '还没选城市';
    final payload = store.weatherCache().payload;
    if (payload == null) return city.name;
    final cur = asMap(payload['current']);
    final temp = asDoubleOrNull(cur['temp']);
    final text = asString(cur['text']);
    if (temp == null) return city.name;
    final t = temp == temp.roundToDouble() ? '${temp.round()}' : '$temp';
    return <String>[city.name, '$t°', text]
        .where((x) => x.isNotEmpty)
        .join(' ');
  }

  /// 记账那格：本月支出。
  String _ledgerStat() {
    final l = store.ledger();
    final thisMonth = monthKeyOf(DateTime.now());
    final s = summarizeMonth(l.records, thisMonth);
    if (s.count == 0) return '本月还没有记账';
    return '本月支出 ¥${formatAmount(s.expense)}';
  }

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    final week = weekOf(DateTime.now(), store.settings().week1Monday);
    final lessonCount = week == null ? 0 : store.courses().week(week).length;

    final tiles = <Widget>[
      _FeatureTile(
        key: const ValueKey('feat-courses'),
        icon: Icons.calendar_month_outlined,
        tint: tone.primarySoft,
        tintColor: tone.primary,
        title: '课程',
        desc: '每周课表 · 节次 · 导入 xlsx / pdf',
        stat: '本周 $lessonCount 节',
        onTap: () => _open(context, '课程', CoursesPage(store: store)),
      ),
      _FeatureTile(
        key: const ValueKey('feat-weather'),
        icon: Icons.cloud_outlined,
        tint: tone.accentSoft,
        tintColor: tone.accent,
        title: '天气',
        desc: '实况 · 24 小时 · 未来 7 天',
        stat: _weatherStat(),
        onTap: () => _open(context, '天气', WeatherPage(store: store, api: api)),
      ),
      _FeatureTile(
        key: const ValueKey('feat-notes'),
        icon: Icons.edit_note_outlined,
        tint: tone.successSoft,
        tintColor: tone.success,
        title: '备忘录',
        desc: '笔记与清单 · 可置顶归档',
        stat: '${store.notes().notes.where((n) => !n.archived).length} 条',
        onTap: () => _open(context, '备忘录', NotesPage(store: store)),
      ),
      _FeatureTile(
        key: const ValueKey('feat-ledger'),
        icon: Icons.account_balance_wallet_outlined,
        tint: tone.warnSoft,
        tintColor: tone.warn,
        title: '记账',
        desc: '记每笔收支 · 按月看合计',
        stat: _ledgerStat(),
        onTap: () => _open(context, '记账', LedgerPage(store: store)),
      ),
    ];

    return ListView(
      key: const ValueKey('page-features'),
      padding: const EdgeInsets.only(bottom: Sp.bottomInset),
      children: <Widget>[
        PageHead(
          title: '功能',
          subtitle: '4 个模块 · 数据本地优先',
          weekText: week == null ? '教学周未设置' : '第 $week 教学周',
          weekStrong: week != null,
          weekKey: week == null
              ? const ValueKey('week-pill-off')
              : const ValueKey('week-pill'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s4 + 2, Sp.gutter, 0),
          child: Column(
            children: <Widget>[
              _row(tiles[0], tiles[1]),
              const SizedBox(height: Sp.s3),
              _row(tiles[2], tiles[3]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.s5, Sp.gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHead(title: '快捷操作'),
              Row(
                children: <Widget>[
                  QuickButton(
                    icon: Icons.add,
                    label: '记一笔',
                    onTap: () => _open(context, '记一笔', LedgerEditPage(store: store)),
                  ),
                  const SizedBox(width: Sp.s3),
                  QuickButton(
                    icon: Icons.edit_outlined,
                    label: '写备忘',
                    onTap: () => _newNote(context),
                  ),
                  const SizedBox(width: Sp.s3),
                  QuickButton(
                    icon: Icons.refresh,
                    label: '刷新天气',
                    onTap: () => _open(
                      context,
                      '天气',
                      WeatherPage(store: store, api: api),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 宫格的一行：两张等高。
  Widget _row(Widget a, Widget b) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: a),
            const SizedBox(width: Sp.s3),
            Expanded(child: b),
          ],
        ),
      );
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.tintColor,
    required this.title,
    required this.desc,
    required this.stat,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color tintColor;
  final String title;
  final String desc;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = Tone.of(context);
    return Card2(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconPlate(icon: icon, size: 38, radius: 11, iconSize: 20, tint: tint, tintColor: tintColor),
          const SizedBox(height: Sp.s2),
          Text(title, style: Type.h3.copyWith(color: tone.ink900)),
          const SizedBox(height: 4),
          Text(
            desc,
            style: Type.xs.copyWith(color: tone.ink400, height: 1.45),
          ),
          const SizedBox(height: Sp.s2),
          const Spacer(),
          Text(
            stat,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.num(Type.xs).copyWith(
              color: tone.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
