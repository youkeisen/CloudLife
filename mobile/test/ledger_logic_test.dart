/// 记账纯逻辑的测试（v1.7.0，需求文档第 3 条）。全部用虚构数据。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/ledger_icons.dart';
import 'package:my_day_phone/ledger_logic.dart';
import 'package:my_day_phone/models.dart';

LedgerRecord rec({
  String id = 'r1',
  double amount = 10,
  String categoryId = 'cat-food',
  String date = '2026-09-19',
  String note = '',
  String createdAt = '2026-09-19T10:00:00',
  String kind = ledgerKindExpense,
}) {
  return LedgerRecord(
    id: id,
    amount: amount,
    categoryId: categoryId,
    date: date,
    note: note,
    createdAt: createdAt,
    kind: kind,
  );
}

void main() {
  group('日期工具', () {
    test('monthKeyOf / dateKeyOf 补零', () {
      expect(monthKeyOf(DateTime(2026, 9, 1)), '2026-09');
      expect(dateKeyOf(DateTime(2026, 9, 5)), '2026-09-05');
    });

    test('parseDateKey 认得正常日期', () {
      expect(parseDateKey('2026-09-19'), DateTime(2026, 9, 19));
      expect(parseDateKey('2026-9-9'), DateTime(2026, 9, 9));
    });

    test('parseDateKey 拦掉不存在的日子和乱写的', () {
      expect(parseDateKey('2026-02-31'), isNull);
      expect(parseDateKey('2026-13-01'), isNull);
      expect(parseDateKey('2026-00-01'), isNull);
      expect(parseDateKey('今天'), isNull);
      expect(parseDateKey(''), isNull);
    });

    test('shiftMonth 跨年', () {
      expect(shiftMonth(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 1));
      expect(shiftMonth(DateTime(2026, 12, 1), 1), DateTime(2027, 1, 1));
      expect(shiftMonth(DateTime(2026, 6, 1), 12), DateTime(2027, 6, 1));
    });
  });

  group('金额格式', () {
    test('补两位小数', () {
      expect(formatAmount(486.5), '486.50');
      expect(formatAmount(32), '32.00');
      expect(formatAmount(0), '0.00');
    });

    test('千分位', () {
      expect(formatAmount(1234.5), '1,234.50');
      expect(formatAmount(1234567.891), '1,234,567.89');
      expect(formatAmount(999.999), '1,000.00');
    });

    test('浮点尾巴不会冒出来', () {
      // 0.1 + 0.2 = 0.30000000000000004
      expect(formatAmount(0.1 + 0.2), '0.30');
    });

    test('负数带减号', () {
      expect(formatAmount(-12.5), '-12.50');
    });
  });

  group('月度汇总', () {
    test('只算这个月的账', () {
      final s = summarizeMonth(<LedgerRecord>[
        rec(id: 'a', amount: 10, date: '2026-09-01'),
        rec(id: 'b', amount: 20, date: '2026-09-02'),
        rec(id: 'c', amount: 99, date: '2026-08-31'), // 上月，不算
        rec(id: 'd', amount: 88, date: '2026-10-01'), // 下月，不算
      ], '2026-09');
      expect(s.expense, 30);
      expect(s.count, 2);
      expect(s.days, 2);
    });

    test('区分支出和收入', () {
      final s = summarizeMonth(<LedgerRecord>[
        rec(id: 'a', amount: 100, date: '2026-09-01'),
        rec(id: 'b', amount: 3000, date: '2026-09-10', kind: ledgerKindIncome),
      ], '2026-09');
      expect(s.expense, 100);
      expect(s.income, 3000);
      expect(s.balance, 2900);
    });

    test('日均按「有记账的天数」算，不是自然月天数', () {
      final s = summarizeMonth(<LedgerRecord>[
        rec(id: 'a', amount: 30, date: '2026-09-20'),
        rec(id: 'b', amount: 30, date: '2026-09-20'), // 同一天
        rec(id: 'c', amount: 40, date: '2026-09-21'),
      ], '2026-09');
      expect(s.days, 2, reason: '9/20 和 9/21 两天');
      expect(s.expense, 100);
      expect(s.dailyExpense, 50);
    });

    test('空月份不炸：全 0，日均 0（不除以 0）', () {
      final s = summarizeMonth(<LedgerRecord>[], '2026-09');
      expect(s.expense, 0);
      expect(s.income, 0);
      expect(s.count, 0);
      expect(s.dailyExpense, 0);
    });

    test('最大单笔只看支出', () {
      expect(maxExpenseOf(<LedgerRecord>[
        rec(id: 'a', amount: 50, date: '2026-09-01'),
        rec(id: 'b', amount: 9999, date: '2026-09-02', kind: ledgerKindIncome),
        rec(id: 'c', amount: 80, date: '2026-09-03'),
      ], '2026-09'), 80);
    });

    test('最大单笔：没有支出时是 0', () {
      expect(maxExpenseOf(<LedgerRecord>[
        rec(id: 'a', amount: 100, date: '2026-09-01', kind: ledgerKindIncome),
      ], '2026-09'), 0);
    });
  });

  group('按日期分组', () {
    test('日期倒序，今天在最上', () {
      final g = groupByDay(<LedgerRecord>[
        rec(id: 'a', date: '2026-09-18'),
        rec(id: 'b', date: '2026-09-20'),
        rec(id: 'c', date: '2026-09-19'),
      ], '2026-09');
      expect(g.map((e) => e.date).toList(),
          <String>['2026-09-20', '2026-09-19', '2026-09-18']);
    });

    test('组内按创建时间倒序', () {
      final g = groupByDay(<LedgerRecord>[
        rec(id: 'early', date: '2026-09-19', createdAt: '2026-09-19T08:00:00'),
        rec(id: 'late', date: '2026-09-19', createdAt: '2026-09-19T20:00:00'),
      ], '2026-09');
      expect(g.single.records.first.id, 'late');
    });

    test('当日小计 = 收入 - 支出', () {
      final g = groupByDay(<LedgerRecord>[
        rec(id: 'a', amount: 12.5, date: '2026-09-19'),
        rec(id: 'b', amount: 26, date: '2026-09-19'),
      ], '2026-09');
      expect(g.single.dayTotal, -38.5);
      expect(g.single.dayExpense, 38.5);
    });

    test('只收这个月的', () {
      final g = groupByDay(<LedgerRecord>[
        rec(id: 'a', date: '2026-09-19'),
        rec(id: 'b', date: '2026-08-19'),
      ], '2026-09');
      expect(g, hasLength(1));
    });

    test('空月份返回空表', () {
      expect(groupByDay(<LedgerRecord>[], '2026-09'), isEmpty);
    });
  });

  group('日期 / 月份显示', () {
    test('dayLabel 带星期', () {
      // 2026-09-19 是周六
      expect(dayLabel('2026-09-19'), '09月19日 · 周六');
    });

    test('dayLabel 解析不出来就原样返回', () {
      expect(dayLabel('乱七八糟'), '乱七八糟');
    });

    test('monthLabel', () {
      expect(monthLabel('2026-09'), '2026年9月');
      expect(monthLabel('2026-12'), '2026年12月');
      expect(monthLabel('坏数据'), '坏数据');
    });
  });

  group('分类校验', () {
    test('空名字不行', () {
      expect(validateCategoryName(''), isNotNull);
      expect(validateCategoryName('   '), isNotNull);
    });

    test('超过 6 个字不行', () {
      expect(validateCategoryName('一二三四五六'), isNull);
      expect(validateCategoryName('一二三四五六七'), isNotNull);
    });

    test('重名不行（自己不算重名）', () {
      final cats = <LedgerCategory>[
        LedgerCategory(id: 'c1', name: '餐饮'),
        LedgerCategory(id: 'c2', name: '交通'),
      ];
      expect(validateCategoryName('餐饮', all: cats), isNotNull);
      expect(validateCategoryName('餐饮', selfId: 'c1', all: cats), isNull,
          reason: '改自己的名字不该报重名');
      expect(validateCategoryName('购物', all: cats), isNull);
    });
  });

  group('金额校验', () {
    test('必须大于 0', () {
      expect(validateAmount(null), isNotNull);
      expect(validateAmount(0), isNotNull);
      expect(validateAmount(-1), isNotNull);
      expect(validateAmount(0.01), isNull);
    });

    test('上限', () {
      expect(validateAmount(9999999), isNull);
      expect(validateAmount(10000000), isNotNull);
    });
  });

  group('分类排序与默认表', () {
    test('按 sort 排', () {
      final out = sortedCategories(<LedgerCategory>[
        LedgerCategory(id: 'b', name: '乙', sort: 20),
        LedgerCategory(id: 'a', name: '甲', sort: 10),
        LedgerCategory(id: 'c', name: '丙', sort: 30),
      ]);
      expect(out.map((e) => e.id).toList(), <String>['a', 'b', 'c']);
    });

    test('sort 相同时按名字排（顺序稳定）', () {
      final out = sortedCategories(<LedgerCategory>[
        LedgerCategory(id: 'b', name: '乙', sort: 0),
        LedgerCategory(id: 'a', name: '甲', sort: 0),
      ]);
      expect(out.map((e) => e.name).toList(), <String>['乙', '甲']);
    });

    test('默认分类表：7 个、id 唯一、图标都在册', () {
      final cats = defaultLedgerCategories();
      expect(cats, hasLength(7));
      expect(cats.map((c) => c.id).toSet(), hasLength(7), reason: 'id 不能重复');
      for (final c in cats) {
        expect(c.name, isNotEmpty);
        expect(ledgerIconKeys, contains(c.icon),
            reason: '${c.name} 的图标 ${c.icon} 不在可选表里');
      }
    });

    test('默认分类里没有真实个人信息（零预置）', () {
      // 只要不是「芜湖」「安徽」这类跟凯森有关的地名/校名就行
      final names = defaultLedgerCategories().map((c) => c.name).join();
      for (final bad in <String>['芜湖', '安徽', '杨成川', '凯森']) {
        expect(names.contains(bad), isFalse);
      }
    });
  });

  group('分类图标映射', () {
    test('在册的都能取到图标', () {
      for (final k in ledgerIconKeys) {
        expect(ledgerIcon(k), isNotNull);
        expect(ledgerIconLabel(k), isNotEmpty);
      }
    });

    test('认不出的标识回落到「其他」，不崩', () {
      expect(ledgerIcon('这是将来才加的图标'), isNotNull);
      expect(ledgerIconLabel('这是将来才加的图标'), '其他');
    });
  });

  group('分类下的记账条数', () {
    test('只数对应分类的', () {
      final recs = <LedgerRecord>[
        rec(id: 'a', categoryId: 'cat-food'),
        rec(id: 'b', categoryId: 'cat-food'),
        rec(id: 'c', categoryId: 'cat-fun'),
      ];
      expect(recordCountOf(recs, 'cat-food'), 2);
      expect(recordCountOf(recs, 'cat-none'), 0);
    });
  });

  group('分类名字改动之后的连带处理', () {
    test('findCategory 找得到 / 找不到返回 null', () {
      final cats = <LedgerCategory>[
        LedgerCategory(id: 'c1', name: '餐饮'),
        LedgerCategory(id: 'c2', name: '交通'),
      ];
      expect(findCategory(cats, 'c2')?.name, '交通');
      expect(findCategory(cats, '不存在'), isNull);
    });

    test('账的 categoryId 指向的分类被删掉时，算「没有分类」', () {
      final recs = <LedgerRecord>[rec(id: 'a', categoryId: 'cat-food')];
      // 分类还在 → 有
      expect(
        findCategory(<LedgerCategory>[LedgerCategory(id: 'cat-food', name: '餐饮')],
            recs.first.categoryId),
        isNotNull,
      );
      // 分类删了 → 找不到，界面该显示「未分类」
      expect(findCategory(const <LedgerCategory>[], recs.first.categoryId), isNull);
    });
  });

  group('金额方向的语义（signed / isIncome）', () {
    test('支出记成负、收入记成正', () {
      expect(rec(amount: 10).signed, -10);
      expect(rec(amount: 10, kind: ledgerKindIncome).signed, 10);
    });

    test('金额本身永远是正数（方向归 kind 管）', () {
      // 从坏数据里读出来的负数会被掰正
      final r = LedgerRecord.fromJson(<String, dynamic>{
        'id': 'x', 'amount': -50, 'categoryId': 'cat-food',
        'date': '2026-09-19', 'kind': 'expense',
      });
      expect(r.amount, 50);
      expect(r.signed, -50);
      expect(r.isIncome, isFalse);
    });
  });
}
