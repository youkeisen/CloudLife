/// 「记一笔」录入页（v1.7.0，需求文档第 3 条）。
///
/// 按设计稿（桌面文档 image2）的「页面二·记一笔」做：
///   · 金额区：¥ + 大字号数字 + 光标，点一下能改
///   · 备注行：点点·二分奶茶（选填）
///   · 日期行：默认今天，点开日历改
///   · 分类网格：从 categories 读，长按进分类管理
///   · 自带的数字键盘：1-9 / 0 / 00 / . / 删除 / 清空 / +
///   · 完成：写入并返回
///
/// 配色沿用 CloudLife 浅色风格，键盘照着做但不是设计稿的深色。
library;

import 'package:flutter/material.dart';

import '../ledger_icons.dart';
import '../ledger_logic.dart';
import '../models.dart';
import '../store.dart';
import 'design.dart';
import 'ledger_categories_sheet.dart';

class LedgerEditPage extends StatefulWidget {
  const LedgerEditPage({
    super.key,
    required this.store,
    this.record,
    this.defaultDate,
  });

  final Store store;

  /// 传了就是编辑已有的一笔；不传是新增。
  final LedgerRecord? record;

  /// 新增时的默认日期（`YYYY-MM-DD`）；不传用今天。
  final String? defaultDate;

  @override
  State<LedgerEditPage> createState() => _LedgerEditPageState();
}

class _LedgerEditPageState extends State<LedgerEditPage> {
  /// 金额的输入缓存。用字符串而不是 double——「32.」这种中间状态
  /// 直接存 double 会丢掉小数点，用户没法继续往下敲。
  String _amount = '';
  late TextEditingController _noteCtrl;
  late String _date;
  String _categoryId = '';
  String _kind = ledgerKindExpense;
  String? _error;

  bool get _isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _noteCtrl = TextEditingController(text: r?.note ?? '');
    _date = r?.date ?? widget.defaultDate ?? dateKeyOf(DateTime.now());
    _kind = r?.kind ?? ledgerKindExpense;
    if (r != null) {
      // 编辑已有的：把金额塞回输入缓存（去掉末尾多余的 0，看着干净）
      _amount = _trimZeros(r.amount);
      _categoryId = r.categoryId;
    }
    _ensureCategory();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  static String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }

  /// 保证总有个选中的分类（新增时默认第一个）。
  void _ensureCategory() {
    final cats = sortedCategories(widget.store.ledger().categories);
    if (cats.isEmpty) {
      _categoryId = '';
      return;
    }
    if (cats.any((c) => c.id == _categoryId)) return;
    _categoryId = cats.first.id;
  }

  // ---------- 键盘 ----------

  void _tapKey(String k) {
    setState(() {
      _error = null;
      switch (k) {
        case 'del':
          if (_amount.isNotEmpty) {
            _amount = _amount.substring(0, _amount.length - 1);
          }
        case 'clear':
          _amount = '';
        case '.':
          if (_amount.isEmpty) {
            _amount = '0.';
          } else if (!_amount.contains('.')) {
            _amount = '$_amount.';
          }
        case '00':
          if (_amount.isEmpty) break;
          // 「0」后面不能再跟 00（0.00 这种没意义）
          if (_amount == '0') break;
          _amount = _amount.contains('.')
              ? (_decimalLen(_amount) >= 2 ? _amount : '$_amount' '00')
              : '$_amount' '00';
        default:
          // 数字
          if (_amount == '0') {
            _amount = k; // 0 开头时直接替换，避免 0123
            break;
          }
          if (_amount.contains('.') && _decimalLen(_amount) >= 2) break; // 最多两位小数
          if (!_amount.contains('.') && _amount.length >= 7) break; // 整数部分最多 7 位
          _amount = '$_amount$k';
      }
    });
  }

  static int _decimalLen(String s) {
    final i = s.indexOf('.');
    return i < 0 ? 0 : s.length - i - 1;
  }

  double? get _parsedAmount {
    if (_amount.isEmpty || _amount == '.') return null;
    final v = double.tryParse(_amount);
    if (v == null) return null;
    // 按分四舍五入，别把 0.1+0.2 的浮点尾巴存进去
    return (v * 100).round() / 100;
  }

  // ---------- 保存 ----------

  void _save() {
    final amount = _parsedAmount;
    final amountErr = validateAmount(amount);
    if (amountErr != null) {
      setState(() => _error = amountErr);
      return;
    }
    if (_categoryId.isEmpty) {
      setState(() => _error = '先建一个分类再记账');
      return;
    }
    final l = widget.store.ledger();
    final note = _noteCtrl.text.trim();
    if (_isEditing) {
      final i = l.records.indexWhere((x) => x.id == widget.record!.id);
      if (i >= 0) {
        l.records[i] = l.records[i].copyWith(
          amount: amount,
          categoryId: _categoryId,
          date: _date,
          note: note,
          kind: _kind,
        );
      }
    } else {
      l.records.add(LedgerRecord(
        id: widget.store.newId('lr'),
        amount: amount!,
        categoryId: _categoryId,
        date: _date,
        note: note,
        createdAt: Store.nowIso(),
        kind: _kind,
      ));
    }
    widget.store.saveLedger(l);
    Navigator.pop(context, true);
  }

  Future<void> _pickDate() async {
    final base = parseDateKey(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = dateKeyOf(picked));
    }
  }

  Future<void> _openCategories() async {
    await showLedgerCategoriesSheet(context, widget.store);
    if (!mounted) return;
    // 只刷自己：主页那边从编辑页返回时会无条件重读数据。
    setState(_ensureCategory);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cats = sortedCategories(widget.store.ledger().categories);

    // 编辑页是独立路由：底下没有壳子的渐变背景，**必须自己垫一层**，
    // 否则透明的 Scaffold 会露出路由遮罩的黑底（和 v1.1.0 备忘录编辑页
    // 同一类 bug，这里一开始漏了 —— 2026-09-20 凯森反馈「进记账界面变黑」）。
    return PageSurface(
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '改一笔' : '记一笔'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('ledger-save'),
            onPressed: _save,
            child: const Text('完成'),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('ledger-edit-body'),
        padding: const EdgeInsets.fromLTRB(Sp.gutter, 4, Sp.gutter, 16),
        children: <Widget>[
          _amountCard(cs),
          const SizedBox(height: 10),
          _dateRow(cs),
          const SizedBox(height: 10),
          _categoryGrid(cs, cats),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!,
                key: const ValueKey('ledger-error'),
                style: Type.sm.copyWith(color: cs.error)),
          ],
          const SizedBox(height: 12),
          _keypad(cs),
        ],
      ),
      ),
    );
  }

  /// 金额 + 备注 + 收支方向。
  Widget _amountCard(ColorScheme cs) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('金额', style: Type.sm.copyWith(color: cs.outline)),
                const Spacer(),
                SegmentedButton<String>(
                  key: const ValueKey('ledger-kind'),
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                        value: ledgerKindExpense, label: Text('支出')),
                    ButtonSegment<String>(
                        value: ledgerKindIncome, label: Text('收入')),
                  ],
                  selected: <String>{_kind},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStateProperty.all(Type.sm),
                  ),
                  onSelectionChanged: (s) =>
                      setState(() => _kind = s.first),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text('¥', style: Type.h2.copyWith(color: cs.outline)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _amount.isEmpty ? '0' : _amount,
                    key: const ValueKey('ledger-amount'),
                    style: Type.display.copyWith(
                      color: _amount.isEmpty ? cs.outline : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('ledger-note'),
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: '备注（选填）',
                isDense: true,
              ),
              maxLength: 40,
              buildCounter: (_,
                      {required currentLength, required isFocused, maxLength}) =>
                  null,
            ),
          ],
        ),
      ),
    );
  }

  /// 日期行。
  Widget _dateRow(ColorScheme cs) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: const ValueKey('ledger-date'),
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: <Widget>[
              Text('日期', style: Type.body.copyWith(color: cs.onSurface)),
              const Spacer(),
              Text(dayLabel(_date),
                  key: const ValueKey('ledger-date-text'),
                  style: Type.sm.copyWith(color: cs.outline)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 17, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }

  /// 分类网格（4 列）。长按任意格子进分类管理。
  Widget _categoryGrid(ColorScheme cs, List<LedgerCategory> cats) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (cats.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: TextButton(
                    key: const ValueKey('ledger-new-cat'),
                    onPressed: _openCategories,
                    child: const Text('还没有分类，点这里新建'),
                  ),
                ),
              )
            else
              GridView.count(
                key: const ValueKey('ledger-cat-grid'),
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.92,
                children: <Widget>[
                  for (final c in cats) _catCell(cs, c),
                ],
              ),
            Center(
              child: TextButton.icon(
                key: const ValueKey('ledger-manage-cats'),
                onPressed: _openCategories,
                icon: const Icon(Icons.tune, size: 16),
                label: Text('管理分类', style: Type.sm),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catCell(ColorScheme cs, LedgerCategory c) {
    final on = c.id == _categoryId;
    return InkWell(
      key: ValueKey('ledger-cat-${c.id}'),
      onTap: () => setState(() => _categoryId = c.id),
      onLongPress: _openCategories,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: on ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: on ? Border.all(color: cs.primary, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(ledgerIcon(c.icon),
                size: 22,
                color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.xs.copyWith(
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 自带数字键盘：1-9 / 删除 ｜ 4-5-6 / 清空 ｜ 7-8-9 / + ｜ . 0 00 完成。
  ///
  /// 摆法对齐设计稿：左边三列是数字，右边一列是功能键。
  Widget _keypad(ColorScheme cs) {
    Widget key(String label, String action,
        {String? keyId, Color? fg, Color? bg, VoidCallback? onTap}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: bg ?? cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: keyId == null ? null : ValueKey<String>(keyId),
              borderRadius: BorderRadius.circular(12),
              onTap: onTap ?? () => _tapKey(action),
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    label,
                    style: Type.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: fg ?? cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: <Widget>[
            Row(children: <Widget>[
              key('1', '1', keyId: 'key-1'),
              key('2', '2', keyId: 'key-2'),
              key('3', '3', keyId: 'key-3'),
              key('删除', 'del', keyId: 'key-del', fg: cs.outline),
            ]),
            Row(children: <Widget>[
              key('4', '4', keyId: 'key-4'),
              key('5', '5', keyId: 'key-5'),
              key('6', '6', keyId: 'key-6'),
              key('清空', 'clear', keyId: 'key-clear', fg: cs.outline),
            ]),
            Row(children: <Widget>[
              key('7', '7', keyId: 'key-7'),
              key('8', '8', keyId: 'key-8'),
              key('9', '9', keyId: 'key-9'),
              key('+', 'plus',
                  keyId: 'key-plus',
                  fg: cs.outline,
                  onTap: () => setState(() => _error = null)),
            ]),
            Row(children: <Widget>[
              key('.', '.', keyId: 'key-dot'),
              key('0', '0', keyId: 'key-0'),
              key('00', '00', keyId: 'key-00'),
              key('完成', '', keyId: 'key-done',
                  fg: cs.onPrimary, bg: cs.primary, onTap: _save),
            ]),
          ],
        ),
      ),
    );
  }
}
