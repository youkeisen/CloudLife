/// 分类管理底部弹层（v1.7.0，需求文档第 3 条）。
///
/// 按设计稿（桌面文档 image2）的「页面三·分类管理」做：
///   · 顶部标题「分类管理」+ 右上「完成」
///   · 4 列网格，每格是「图标 + 名字」
///   · 最后一格是「＋ 新建」
///   · 点格子改名 + 换图标；长按出「删除」
///   · 删一个还有账的分类要先说清楚会影响多少笔
///
/// 这里的增删改都是**立刻落盘**（弹层里没有「取消」的概念），
/// 所以每次操作完都要把整个 Ledger 存回去。
library;

import 'package:flutter/material.dart';

import '../ledger_icons.dart';
import '../ledger_logic.dart';
import '../models.dart';
import '../store.dart';

/// 打开分类管理弹层。关掉时返回 true 表示「分类动过了」，
/// 调用方可以据此刷新选中的分类。
Future<bool?> showLedgerCategoriesSheet(BuildContext context, Store store) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LedgerCategoriesSheet(store: store),
  );
}

class _LedgerCategoriesSheet extends StatefulWidget {
  const _LedgerCategoriesSheet({required this.store});

  final Store store;

  @override
  State<_LedgerCategoriesSheet> createState() => _LedgerCategoriesSheetState();
}

class _LedgerCategoriesSheetState extends State<_LedgerCategoriesSheet> {
  /// 有没有动过分类（关弹层时回传，让「记一笔」页刷新选中项）。
  bool _changed = false;

  Ledger get _ledger => widget.store.ledger();

  void _save(Ledger l) {
    widget.store.saveLedger(l);
    _changed = true;
    if (mounted) setState(() {});
  }

  // ---------- 新建 / 改名 ----------

  /// 新建或编辑一个分类。传 [existing] 就是改名/换图标。
  Future<void> _editCategory({LedgerCategory? existing}) async {
    final all = _ledger.categories;
    final result = await showDialog<_CatDraft>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing, all: all),
    );
    if (result == null) return;

    final l = _ledger;
    if (existing == null) {
      // 新分类的 sort 排在最后（现有最大 +10）
      var maxSort = 0;
      for (final c in l.categories) {
        if (c.sort > maxSort) maxSort = c.sort;
      }
      l.categories.add(LedgerCategory(
        id: widget.store.newId('lc'),
        name: result.name,
        icon: result.icon,
        sort: maxSort + 10,
      ));
    } else {
      final i = l.categories.indexWhere((c) => c.id == existing.id);
      if (i < 0) return;
      l.categories[i] = l.categories[i]
          .copyWith(name: result.name, icon: result.icon);
    }
    _save(l);
  }

  // ---------- 删除 ----------

  Future<void> _deleteCategory(LedgerCategory c) async {
    final n = recordCountOf(_ledger.records, c.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${c.name}」？'),
        content: Text(n == 0
            ? '这个分类下还没有记过账，删掉不影响别的。'
            : '这个分类下还有 $n 笔账，删掉之后这些账会变成「未分类」，'
                '金额和日期都还在，不会丢。'),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('del-cat-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('del-cat-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final l = _ledger;
    l.categories = l.categories.where((x) => x.id != c.id).toList();
    _save(l); // 账不跟着删，只是 categoryId 指向不到了 → 界面显示「未分类」
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cats = sortedCategories(_ledger.categories);

    // 弹层最高占屏幕八成，分类多了能在里面滚。
    final maxH = MediaQuery.of(context).size.height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 抓手条
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: <Widget>[
                const Text('分类管理',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  key: const ValueKey('cats-done'),
                  onPressed: () => Navigator.pop(context, _changed),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
          Flexible(
            child: GridView.count(
              key: const ValueKey('cats-grid'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
              children: <Widget>[
                for (final c in cats) _cell(cs, c),
                _newCell(cs),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              '点一下改名或换图标，长按删除',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(ColorScheme cs, LedgerCategory c) {
    final n = recordCountOf(_ledger.records, c.id);
    return InkWell(
      key: ValueKey('cat-${c.id}'),
      onTap: () => _editCategory(existing: c),
      onLongPress: () => _deleteCategory(c),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(ledgerIcon(c.icon), size: 22, color: cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            if (n > 0)
              Text('$n 笔',
                  style: TextStyle(fontSize: 9, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  Widget _newCell(ColorScheme cs) {
    return InkWell(
      key: const ValueKey('cat-new'),
      onTap: () => _editCategory(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.add, size: 22, color: cs.primary),
            const SizedBox(height: 4),
            Text('新建',
                style: TextStyle(fontSize: 11, color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

/// 弹窗里填好的内容。
class _CatDraft {
  _CatDraft(this.name, this.icon);
  final String name;
  final String icon;
}

/// 新建 / 改分类的弹窗：名字 + 图标选择。
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.existing, required this.all});

  final LedgerCategory? existing;
  final List<LedgerCategory> all;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late TextEditingController _ctrl;
  late String _icon;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?.name ?? '');
    _icon = widget.existing?.icon ?? 'other';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    final err = validateCategoryName(
      name,
      selfId: widget.existing?.id,
      all: widget.all,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _CatDraft(name, _icon));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? '新建分类' : '改分类'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              key: const ValueKey('cat-name'),
              controller: _ctrl,
              autofocus: true,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: '名字',
                hintText: '例如 水果',
                isDense: true,
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Text('图标', style: TextStyle(fontSize: 12, color: cs.outline)),
            const SizedBox(height: 6),
            Wrap(
              key: const ValueKey('cat-icons'),
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final k in ledgerIconKeys)
                  Tooltip(
                    message: ledgerIconLabel(k),
                    child: InkWell(
                      key: ValueKey('cat-icon-$k'),
                      onTap: () => setState(() => _icon = k),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _icon == k
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: _icon == k
                              ? Border.all(color: cs.primary, width: 1.5)
                              : null,
                        ),
                        child: Icon(ledgerIcon(k),
                            size: 20,
                            color: _icon == k
                                ? cs.onPrimaryContainer
                                : cs.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey('cat-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('cat-submit'),
          onPressed: _submit,
          child: Text(isNew ? '建' : '改'),
        ),
      ],
    );
  }
}
