/// 记账主页（v1.7.0，需求文档第 3 条）。
///
/// 按设计稿（桌面文档 image2）的「页面一·记账主页」做，但配色沿用
/// CloudLife 现有的浅色风格，不照抄设计稿的深色稿：
///   · 顶部：月份切换（‹ 2026年9月 ›）
///   · 本月合计卡：支出大字 + 笔数 / 日均 / 最大单笔
///   · 日期分组流水列表：每组带当日小计，条目可点开改、可删
///   · 右下 FAB「＋」去记一笔
library;

import 'package:flutter/material.dart';

import '../ledger_icons.dart';
import '../ledger_logic.dart';
import '../models.dart';
import '../store.dart';
import 'ledger_edit_page.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key, required this.store, this.initialMonth});

  final Store store;

  /// 测试钩子：固定初始月份（`YYYY-MM`）。
  final String? initialMonth;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late String _month;

  @override
  void initState() {
    super.initState();
    // 首次打开落在这个月；记账数据要先种好默认分类
    widget.store.ensureLedgerSeed();
    _month = widget.initialMonth ?? monthKeyOf(DateTime.now());
  }

  Ledger get _ledger => widget.store.ledger();

  void _shiftMonth(int delta) {
    final first = DateTime(
      int.parse(_month.substring(0, 4)),
      int.parse(_month.substring(5, 7)),
      1,
    );
    setState(() => _month = monthKeyOf(shiftMonth(first, delta)));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1400),
      ));
  }

  Future<void> _openNew() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => LedgerEditPage(store: widget.store, defaultDate: _todayInMonth()),
    ));
    // **回来就刷新，不看返回值**：编辑页里还能进「分类管理」改名字、
    // 删分类，那时候用户是直接按返回键退出的，不会带上「改动过」的标记；
    // 而主页的流水是按分类名显示的，不刷新就会挂着已经删掉的名字。
    // 重读一次 JSON 就是几毫秒的事，不值得为省这点去纠结标记传没传对。
    if (mounted) setState(() {});
  }

  /// 新增时默认日期：看的是哪个月就默认那个月，当月就默认今天。
  String _todayInMonth() {
    final today = dateKeyOf(DateTime.now());
    if (today.startsWith(_month)) return today;
    return '$_month-01';
  }

  Future<void> _openEdit(LedgerRecord r) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => LedgerEditPage(store: widget.store, record: r),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _deleteRecord(LedgerRecord r, LedgerCategory? cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这笔账？'),
        content: Text('${cat?.name ?? '未分类'}　¥${formatAmount(r.amount)}'
            '${r.note.isEmpty ? '' : '\n${r.note}'}'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('del-record-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('del-record-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final l = _ledger;
    l.records = l.records.where((x) => x.id != r.id).toList();
    widget.store.saveLedger(l);
    if (mounted) {
      setState(() {});
      _toast('已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ledger = _ledger;
    final cats = <String, LedgerCategory>{
      for (final c in ledger.categories) c.id: c,
    };
    final summary = summarizeMonth(ledger.records, _month);
    final maxExpense = maxExpenseOf(ledger.records, _month);
    final groups = groupByDay(ledger.records, _month);

    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            _monthBar(cs),
            Expanded(
              child: ListView(
                key: const ValueKey('ledger-list'),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                children: <Widget>[
                  _summaryCard(cs, summary, maxExpense),
                  const SizedBox(height: 10),
                  if (groups.isEmpty)
                    _emptyHint(cs)
                  else
                    for (final g in groups) _dayGroup(cs, g, cats),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 20,
          child: FloatingActionButton(
            key: const ValueKey('ledger-fab'),
            onPressed: _openNew,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  /// 顶部月份切换条。
  Widget _monthBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const ValueKey('ledger-prev-month'),
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: '上个月',
          ),
          Expanded(
            child: Text(
              monthLabel(_month),
              key: const ValueKey('ledger-month-label'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            key: const ValueKey('ledger-next-month'),
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: '下个月',
          ),
        ],
      ),
    );
  }

  /// 本月合计卡。
  Widget _summaryCard(ColorScheme cs, MonthSummary s, double maxExpense) {
    return Card(
      key: const ValueKey('ledger-summary'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('本月支出',
                style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 4),
            Text(
              '¥${formatAmount(s.expense)}',
              key: const ValueKey('ledger-total'),
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w700, height: 1.1),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _stat(cs, '笔数', '${s.count}'),
                _stat(cs, '日均', '¥${formatAmount(s.dailyExpense)}'),
                _stat(cs, '最大单笔', '¥${formatAmount(maxExpense)}'),
              ],
            ),
            if (s.income > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text('本月收入 ¥${formatAmount(s.income)}',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(ColorScheme cs, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// 一个日期分组。
  Widget _dayGroup(
    ColorScheme cs,
    DayGroup g,
    Map<String, LedgerCategory> cats,
  ) {
    return Column(
      key: ValueKey('ledger-day-${g.date}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: <Widget>[
              Text(dayLabel(g.date),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('当日 ¥${formatAmount(g.dayExpense)}',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (var i = 0; i < g.records.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                _recordTile(cs, g.records[i], cats[g.records[i].categoryId]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _recordTile(ColorScheme cs, LedgerRecord r, LedgerCategory? cat) {
    final icon = ledgerIcon(cat?.icon ?? 'other');
    final name = cat?.name ?? '未分类';
    return InkWell(
      key: ValueKey('ledger-record-${r.id}'),
      onTap: () => _openEdit(r),
      onLongPress: () => _deleteRecord(r, cat),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  if (r.note.isNotEmpty)
                    Text(r.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.outline)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // 收入显示成 +，支出显示成 -，颜色区分（红涨绿跌的国内习惯不适用，
              // 这里按「钱出去了」用醒目色、「钱进来了」用低调色）
              '${r.isIncome ? '+' : '-'}${formatAmount(r.amount)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: r.isIncome ? cs.tertiary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint(ColorScheme cs) {
    return Padding(
      key: const ValueKey('ledger-empty'),
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 28),
      child: Column(
        children: <Widget>[
          Icon(Icons.receipt_long_outlined, size: 46, color: cs.outline),
          const SizedBox(height: 12),
          const Text('这个月还没有记账',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('点右下角的「＋」记第一笔',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ),
    );
  }
}
