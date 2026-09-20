/// 功能模块页：把课程 / 天气 / 备忘录这些功能收进来，以后新增的也放这里。
///
/// 点卡片进入对应页面——这些页面原本是底栏的 Tab，现在是独立整页，
/// 所以进来时要自己套 Scaffold + GlassBackdrop（玻璃化的规矩：独立整页得垫背景）。
library;

import 'package:flutter/material.dart';

import '../store.dart';
import '../weather_api.dart';
import 'courses_page.dart';
import 'glass.dart';
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
      builder: (_) => GlassBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(title)),
          body: body,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <_Feature>[
      _Feature(
        key: 'feat-courses',
        title: '课程',
        desc: '每周课表、节次、导入 xlsx / pdf',
        icon: Icons.calendar_month_outlined,
        onTap: () => _open(context, '课程', CoursesPage(store: store)),
      ),
      _Feature(
        key: 'feat-weather',
        title: '天气',
        desc: '实况、24 小时、未来 7 天',
        icon: Icons.cloud_outlined,
        onTap: () => _open(context, '天气', WeatherPage(store: store, api: api)),
      ),
      _Feature(
        key: 'feat-notes',
        title: '备忘录',
        desc: '笔记与清单，可置顶归档',
        icon: Icons.edit_note_outlined,
        onTap: () => _open(context, '备忘录', NotesPage(store: store)),
      ),
      _Feature(
        key: 'feat-ledger',
        title: '记账',
        desc: '记每笔收支，按月看合计',
        icon: Icons.account_balance_wallet_outlined,
        onTap: () => _open(context, '记账', LedgerPage(store: store)),
      ),
    ];

    return ListView(
      key: const ValueKey('page-features'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: <Widget>[
        Text('功能模块',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text('以后新加的功能都会放这里',
            style: TextStyle(fontSize: 12, color: cs.outline)),
        const SizedBox(height: 12),
        for (final f in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              key: ValueKey(f.key),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: f.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(f.icon, size: 22, color: cs.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(f.title,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(f.desc,
                                style:
                                    TextStyle(fontSize: 12, color: cs.outline)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: cs.outline),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Feature {
  _Feature({
    required this.key,
    required this.title,
    required this.desc,
    required this.icon,
    required this.onTap,
  });

  final String key;
  final String title;
  final String desc;
  final IconData icon;
  final VoidCallback onTap;
}
