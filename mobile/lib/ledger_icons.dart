/// 记账的分类图标与默认分类表（v1.7.0，需求文档第 3 条）。
///
/// 数据里存的 icon 是**字符串标识**（如 `food`），不存图片：
/// 一来数据要能跟备份走，二来图标随主题变，不该固化进数据。
/// 这里做标识 → Material 图标的映射。
library;

import 'package:flutter/material.dart';

import 'models.dart';

/// 可选的图标标识表（分类管理里换图标就从这里挑）。
///
/// 顺序就是选择器里的展示顺序：先「吃穿住行」这些日常的，再其他的。
const List<String> ledgerIconKeys = <String>[
  'food', 'drink', 'goods', 'transport', 'fun', 'study',
  'cloth', 'home', 'medical', 'phone', 'gift', 'travel',
  'salary', 'bonus', 'other',
];

const Map<String, IconData> _ledgerIcons = <String, IconData>{
  'food': Icons.restaurant,
  'drink': Icons.local_cafe,
  'goods': Icons.shopping_basket,
  'transport': Icons.directions_bus,
  'fun': Icons.sports_esports,
  'study': Icons.menu_book,
  'cloth': Icons.checkroom,
  'home': Icons.home,
  'medical': Icons.medical_services,
  'phone': Icons.smartphone,
  'gift': Icons.card_giftcard,
  'travel': Icons.luggage,
  'salary': Icons.account_balance_wallet,
  'bonus': Icons.redeem,
  'other': Icons.more_horiz,
};

/// 图标标识 → Material 图标。认不出的标识一律回落到「其他」，
/// 这样数据里出现将来才加的图标时界面也不会崩。
IconData ledgerIcon(String key) => _ledgerIcons[key] ?? Icons.more_horiz;

/// 图标标识的中文名（选择器里显示）。
const Map<String, String> ledgerIconLabels = <String, String>{
  'food': '吃饭',
  'drink': '喝的',
  'goods': '日用',
  'transport': '交通',
  'fun': '娱乐',
  'study': '学习',
  'cloth': '衣服',
  'home': '居家',
  'medical': '医疗',
  'phone': '通讯',
  'gift': '礼物',
  'travel': '旅行',
  'salary': '工资',
  'bonus': '奖金',
  'other': '其他',
};

String ledgerIconLabel(String key) => ledgerIconLabels[key] ?? '其他';

/// 首次使用记账时建的那套通用分类（零预置：都是日常通用项，
/// 不含任何跟凯森个人有关的内容）。
///
/// id 用固定字符串而不是随机 id，这样同一个默认分类在不同设备上
/// 是同一个 id，将来要做同步/合并不至于重出来两份。
List<LedgerCategory> defaultLedgerCategories() {
  const defs = <(String, String, String)>[
    ('cat-food', '餐饮', 'food'),
    ('cat-drink', '奶茶饮料', 'drink'),
    ('cat-goods', '日用', 'goods'),
    ('cat-transport', '交通', 'transport'),
    ('cat-fun', '娱乐', 'fun'),
    ('cat-study', '学习', 'study'),
    ('cat-other', '其他', 'other'),
  ];
  return <LedgerCategory>[
    for (var i = 0; i < defs.length; i++)
      LedgerCategory(
        id: defs[i].$1,
        name: defs[i].$2,
        icon: defs[i].$3,
        sort: i * 10,
      ),
  ];
}
