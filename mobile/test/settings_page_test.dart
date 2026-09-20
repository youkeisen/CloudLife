// 设置页的测试：四块表单落盘、外观联动主题、节次增删改、我的地点增删切换、
// 备份导出 / 还原（含坏文件与二次确认）/ 清空（必须输入「清空」两个字）。
// 数据全部虚构；备份还原用真 zip 字节（archive 打包），不碰系统文件选择器。
library;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:my_day_phone/app.dart';
import 'package:my_day_phone/backup.dart' show backupDataFiles;
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/notification_service.dart';
import 'package:my_day_phone/store.dart';
import 'package:my_day_phone/system_tweaks.dart';
import 'package:my_day_phone/ui/settings_page.dart';
import 'package:my_day_phone/weather_api.dart';

/// 假接口：不联网，固定返回一个虚构城市。
class FakeApi extends WeatherApi {
  @override
  Future<List<CitySuggestion>> searchCities(String name) async =>
      <CitySuggestion>[
        CitySuggestion(name: '测试城', admin: '测试省', latitude: 30.5, longitude: 117.3),
      ];
}

void main() {
  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myday-settings-test-');
    store = Store(tmp)..init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Map<String, dynamic> settingsJson() =>
      jsonDecode(File('${tmp.path}/settings.json').readAsStringSync())
          as Map<String, dynamic>;

  /// 用 MyDayApp 整壳来泵：外观联动、onChanged 传递都走真路径。
  Future<void> pumpApp(WidgetTester tester,
      {Future<List<int>?> Function()? pickZip, WeatherApi? api}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MyDayApp(
      store: store,
      pickZip: pickZip,
      api: api,
    ));
    await tester.pumpAndSettle();
    // 切到设置 Tab
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
  }

  /// 只泵设置页本身（不经过 MyDayApp），轻量一些。
  Future<void> pumpPage(
    WidgetTester tester, {
    Future<List<int>?> Function()? pickZip,
    Future<String?> Function()? pickDir,
    WeatherApi? api,
    Future<TimeOfDay?> Function(TimeOfDay initial)? pickTime,
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsPage(
            store: store,
            pickZip: pickZip,
            pickDir: pickDir,
            api: api,
            pickTime: pickTime),
      ),
    ));
    await tester.pumpAndSettle();
  }

  void seedPlaces() {
    final s = store.settings()
      ..weatherCities = <Place>[
        Place(id: 'p1', name: '甲城', latitude: 30.1, longitude: 117.1),
        Place(id: 'p2', name: '乙城', latitude: 31.2, longitude: 118.2),
      ]
      ..weatherCity = City(name: '甲城', latitude: 30.1, longitude: 117.1);
    store.saveSettings(s);
  }

  Period periodAt(int i) => store.settings().periods[i];

  testWidgets('四个区块都渲染', (tester) async {
    await pumpPage(tester);

    expect(find.text('基本'), findsOneWidget);
    expect(find.text('天气'), findsOneWidget);
    expect(find.text('作息与节次（全部自定义）'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);
    // v1.6.0（需求文档第 8 条）：多了「后台运行与提醒」卡片
    expect(find.text('后台运行与提醒'), findsOneWidget);
    // v1.4.4 起：称呼输入框按凯森要求加回来了；学期名/校区仍是删掉状态
    expect(find.byKey(const ValueKey('s-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('s-semester')), findsNothing);
    expect(find.byKey(const ValueKey('s-campus')), findsNothing);
  });

  group('v1.6.0 需求文档新条目', () {
    testWidgets('第 7 条：天气「自动刷新」下拉去掉了，只显示固定的每 10 分钟', (tester) async {
      await pumpPage(tester);
      // 旧的下拉（key s-refresh）没有了
      expect(find.byKey(const ValueKey('s-refresh')), findsNothing);
      // 换成一行只读文案
      expect(find.byKey(const ValueKey('s-refresh-fixed')), findsOneWidget);
      expect(find.text('每 10 分钟'), findsOneWidget);
      // 默认值就是 10 分钟
      expect(store.settings().refreshMinutes, 10);
    });

    testWidgets('第 1 条：上课提醒下拉能选，落盘并写进 JSON', (tester) async {
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('s-lesson-remind')), findsOneWidget);
      // 默认提前 15 分钟
      expect(find.text('提前 15 分钟'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('s-lesson-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提前 30 分钟').last);
      await tester.pumpAndSettle();

      expect(store.settings().lessonRemindMinutes, 30);
      expect(settingsJson()['lessonRemindMinutes'], 30);
    });

    testWidgets('第 1 条：可以选「不提醒」', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('s-lesson-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不提醒').last);
      await tester.pumpAndSettle();
      expect(store.settings().lessonRemindMinutes, -1);
    });

    testWidgets('第 9 条：选备份位置 → 落盘，备份 zip 落到该目录', (tester) async {
      final target = Directory.systemTemp.createTempSync('myday-backup-dest-');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync(recursive: true);
      });

      await pumpPage(tester, pickDir: () async => target.path);
      await tester.tap(find.byKey(const ValueKey('btn-backup-dir')));
      await tester.pumpAndSettle();
      expect(store.settings().backupDir, target.path);

      // 备份：zip 应该出现在自定义目录里，而不是默认的 backups/
      await tester.tap(find.byKey(const ValueKey('btn-backup')));
      await tester.pumpAndSettle();
      final zips = target
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'))
          .toList();
      expect(zips.length, 1, reason: 'zip 要落到用户选的位置');
      expect(zips.first.lengthSync(), greaterThan(0));
      expect(Directory('${tmp.path}/backups').existsSync(), isFalse,
          reason: '不该再往默认位置写');
    });

    testWidgets('第 9 条：可以恢复默认备份位置', (tester) async {
      final target = Directory.systemTemp.createTempSync('myday-backup-dest2-');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync(recursive: true);
      });
      await pumpPage(tester, pickDir: () async => target.path);
      await tester.tap(find.byKey(const ValueKey('btn-backup-dir')));
      await tester.pumpAndSettle();
      expect(store.settings().backupDir, target.path);

      await tester.tap(find.byKey(const ValueKey('btn-backup-dir-reset')));
      await tester.pumpAndSettle();
      expect(store.settings().backupDir, '');
      expect(find.byKey(const ValueKey('btn-backup-dir-reset')), findsNothing);
    });

    testWidgets('第 9 条：选了写不进去的目录 → 提示且不落盘', (tester) async {
      // 造一个「文件」当目录用，写进去必然失败
      final notADir = File('${tmp.path}/not-a-dir');
      notADir.writeAsStringSync('x');

      await pumpPage(tester, pickDir: () async => notADir.path);
      await tester.tap(find.byKey(const ValueKey('btn-backup-dir')));
      await tester.pumpAndSettle();

      expect(store.settings().backupDir, '',
          reason: '写不进去的目录不该被记住');
      expect(find.textContaining('写不进去'), findsOneWidget);
    });

    testWidgets('第 8 条：后台运行卡片有电池优化引导', (tester) async {
      await pumpPage(tester);
      // 卡片默认收起 → 先展开
      await tester.tap(find.byKey(const ValueKey('s-bg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('btn-battery-opt')), findsOneWidget);
      // 说明文案（「自启动」那段只在安卓上显示，测试跑在桌面 VM 上，
      // 所以这里只断言必然存在的说明句，平台相关的文案不强求）
      expect(find.textContaining('交给系统的闹钟'), findsOneWidget);
    });

    // ---------- v1.7.4：通知权限提示 ----------
    // 背景（凯森 2026-09-20）：「到时间为什么课程没有提醒通知，
    // 我没退出软件，通知栏没有弹通知」。查下来权限被拒是头号嫌疑——
    // 系统会把通知静默丢掉，App 侧完全无感，界面上必须能看出来。

    testWidgets('v1.7.4 通知被拒：卡片展开显示警告 + 按钮可点', (tester) async {
      SystemTweaks.debugSetStoragePermission(true); // 借用开关让 _checkNotifPerm 生效
      NotificationService.debugSetPermissions(enabled: false, exact: false);
      addTearDown(() {
        SystemTweaks.debugSetStoragePermission(null);
        NotificationService.debugSetPermissions();
      });

      await pumpPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('s-bg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('s-notif-warning')), findsOneWidget,
          reason: '权限被拒必须显眼提示，否则用户根本不知道为啥不响');
      expect(find.textContaining('通知权限被关掉了'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-notif-perm')), findsOneWidget);
      // 精确闹钟那一项也在（没开 → 按钮可点）
      expect(find.byKey(const ValueKey('btn-exact-alarm')), findsOneWidget);
      expect(find.textContaining('精确定时'), findsOneWidget);
    });

    testWidgets('v1.7.4 通知已开：不显示警告，按钮变「已开启」且禁用', (tester) async {
      SystemTweaks.debugSetStoragePermission(true);
      NotificationService.debugSetPermissions(enabled: true, exact: true);
      addTearDown(() {
        SystemTweaks.debugSetStoragePermission(null);
        NotificationService.debugSetPermissions();
      });

      await pumpPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('s-bg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('s-notif-warning')), findsNothing,
          reason: '权限正常就别吓唬人');
      final btn = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('btn-notif-perm')));
      expect(btn.onPressed, isNull, reason: '已开启就不该还能点');
      expect(find.text('已开启'), findsWidgets);
    });

    testWidgets('v1.7.5 自检按钮：点一下能查出系统里排了几条', (tester) async {
      await pumpPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('s-bg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('btn-check-pending')), findsOneWidget);
      expect(find.textContaining('点右侧查一下'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('btn-check-pending')));
      await tester.pumpAndSettle();

      // 桌面环境没有真通知插件 → 查不到，显示「查不到（不影响使用）」，
      // 关键是**不能崩**，也不能误报成「系统里一条都没有」
      expect(find.textContaining('查不到'), findsOneWidget);
    });

    // ---------- v1.7.6：一键发测试通知 ----------
    // 「到点不提醒」以前没法当场验证（最快等几分钟、最慢等到第二天那节课），
    // 排查一轮要一天。有这个按钮点一下就知道通知链路通不通。
    testWidgets('v1.7.6 有「测试通知」按钮，点了不崩', (tester) async {
      await pumpPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('s-bg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('btn-test-notification')), findsOneWidget,
          reason: '缺测试通知按钮 —— 「通知能不能弹」就没法当场验证');
      expect(find.textContaining('通知栏应该立刻弹出'), findsOneWidget);

      // 桌面环境没有真通知插件，点下去可能失败，但**绝不能崩**
      await tester.tap(find.byKey(const ValueKey('btn-test-notification')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // ---------- v1.7.3：备份位置的「所有文件访问」权限引导 ----------
    // 背景：凯森 2026-09-20 反馈「位置设定不了」，
    // 报 `Operation not permitted` —— 安卓 10+ 写共享目录要先有这个权限。

    testWidgets('v1.7.3 没权限时：点「选择」先弹引导框，不去选目录', (tester) async {
      SystemTweaks.debugSetStoragePermission(false);
      addTearDown(() => SystemTweaks.debugSetStoragePermission(null));

      var picked = false;
      await pumpPage(tester); // 不注入 pickDir —— 走真实权限分支
      // 用真实 getDirectoryPath 会弹系统框，这里只验证引导框先出现，
      // 所以点完立刻 pump（不要 settle，否则会等系统框）
      await tester.tap(find.byKey(const ValueKey('btn-backup-dir')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('dlg-storage-permission')), findsOneWidget,
          reason: '没权限要先弹引导框');
      expect(find.textContaining('所有文件访问'), findsWidgets);
      expect(picked, isFalse);
      // 收尾：关掉对话框，避免影响后续
      await tester.tap(
          find.byKey(const ValueKey('dlg-storage-permission-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('v1.7.3 引导框点「先不用」：不落盘、不跳转', (tester) async {
      SystemTweaks.debugSetStoragePermission(false);
      addTearDown(() => SystemTweaks.debugSetStoragePermission(null));

      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('btn-backup-dir')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(
          find.byKey(const ValueKey('dlg-storage-permission-cancel')));
      await tester.pumpAndSettle();

      expect(store.settings().backupDir, '', reason: '没选成就不该落盘');
      expect(find.byKey(const ValueKey('dlg-storage-permission')), findsNothing);
    });

    testWidgets('v1.7.3 有权限时：不弹引导框，直接走选目录', (tester) async {
      SystemTweaks.debugSetStoragePermission(true);
      addTearDown(() => SystemTweaks.debugSetStoragePermission(null));

      final target = Directory.systemTemp.createTempSync('myday-perm-ok-');
      addTearDown(() {
        if (target.existsSync()) target.deleteSync(recursive: true);
      });
      await pumpPage(tester, pickDir: () async => target.path);
      await tester.tap(find.byKey(const ValueKey('btn-backup-dir')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dlg-storage-permission')), findsNothing,
          reason: '有权限就不该打扰用户');
      expect(store.settings().backupDir, target.path);
    });

    testWidgets('v1.7.3 设过位置但权限被撤：点「立即备份」也先引导', (tester) async {
      SystemTweaks.debugSetStoragePermission(false);
      addTearDown(() => SystemTweaks.debugSetStoragePermission(null));

      final s = store.settings()..backupDir = tmp.path;
      store.saveSettings(s);

      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('btn-backup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('dlg-storage-permission')), findsOneWidget,
          reason: '权限没了要提醒，而不是丢个天书报错');
      await tester.tap(
          find.byKey(const ValueKey('dlg-storage-permission-cancel')));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('基本卡片默认展开，点标题收起再展开（v1.3.7）', (tester) async {
    await pumpPage(tester);
    // 默认展开：能看到第 1 周周一日期
    expect(find.text('第 1 周周一日期'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('s-basic-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 周周一日期'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('s-basic-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 周周一日期'), findsOneWidget);
  });

  testWidgets('卡片收放状态重进后保留（v1.4.0）', (tester) async {
    await pumpPage(tester);
    // 收起基本卡
    await tester.tap(find.byKey(const ValueKey('s-basic-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 周周一日期'), findsNothing);

    // 模拟重进：重新泵页面，收起状态要记着
    await pumpPage(tester);
    expect(find.text('第 1 周周一日期'), findsNothing);
  });

  testWidgets('选第 1 周周一日期：日期选择器 → 落盘', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('s-week1')));
    await tester.pumpAndSettle();

    // 日历默认落在今天所在的月份，直接选 15 日
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    // 注意：pumpPage 用的是裸 MaterialApp，没接本地化代理，
    // 所以这里的按钮还是英文 OK；走 MyDayApp 的 pumpApp 才是「确定」。
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final saved = store.settings().week1Monday;
    expect(saved, isNotEmpty);
    expect(saved.endsWith('-15'), isTrue, reason: '应该落在 15 日：$saved');
    expect(saved.length, 10, reason: '格式是 YYYY-MM-DD：$saved');
  });

  testWidgets('每周起始日切周日 → weekStartsOn = 7', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('s-weekstart')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周日').last);
    await tester.pumpAndSettle();

    expect(store.settings().weekStartsOn, 7);
    expect(settingsJson()['weekStartsOn'], 7);
  });

  testWidgets('外观切深色：落盘 + 整个 App 立刻变深色', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('s-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();

    expect(store.settings().theme, 'dark');
    expect(settingsJson()['theme'], 'dark');
    final ctx = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx).brightness, Brightness.dark, reason: '设置完外观整棵树要重建');
  });

  testWidgets('v1.6.0：自动刷新改成固定 10 分钟，下拉没了', (tester) async {
    await pumpPage(tester);
    // 需求文档第 7 条：把设置里天气的「自动刷新」选项去掉，默认 10 分钟刷新
    expect(find.byKey(const ValueKey('s-refresh')), findsNothing);
    expect(store.settings().refreshMinutes, 10);
    expect(settingsJson()['refreshMinutes'], 10);
  });

  group('节次', () {
    /// v1.3.5 起「作息与节次」卡片默认收起，先点标题展开再操作
    Future<void> openPeriods(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('s-periods-toggle')));
      await tester.pumpAndSettle();
    }

    testWidgets('卡片默认收起，点标题展开、再点收起', (tester) async {
      final s = store.settings()
        ..periods = <Period>[
          Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:55'),
        ];
      store.saveSettings(s);
      await pumpPage(tester);

      // 收起状态：看不到节次行和添加按钮，但有摘要
      expect(find.byKey(const ValueKey('s-add-period')), findsNothing);
      expect(find.text('1 个节次'), findsOneWidget);

      await openPeriods(tester);
      expect(find.byKey(const ValueKey('s-add-period')), findsOneWidget);
      expect(find.text('08:10'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('s-periods-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('s-add-period')), findsNothing);
    });

    testWidgets('空列表有引导，点添加加一条', (tester) async {
      await pumpPage(tester);
      await openPeriods(tester);
      expect(find.byKey(const ValueKey('s-periods-empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('s-add-period')));
      await tester.pumpAndSettle();
      expect(store.settings().periods.length, 1);
      expect(find.byKey(const ValueKey('s-periods-empty')), findsNothing);
      final p = periodAt(0);
      expect(p.label, '');
      expect(p.id, startsWith('p'));
    });

    testWidgets('连点三次加三条，id 不重复', (tester) async {
      await pumpPage(tester);
      await openPeriods(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('s-add-period')));
        await tester.pumpAndSettle();
      }
      final periods = store.settings().periods;
      expect(periods.length, 3);
      expect(periods.map((p) => p.id).toSet().length, 3);
    });

    testWidgets('编辑名称与起止时间落盘（时间用选择器选）', (tester) async {
      // 注入假时间选择器：第一次选开始 08:10，第二次选结束 08:50
      final answers = <TimeOfDay>[
        const TimeOfDay(hour: 8, minute: 10),
        const TimeOfDay(hour: 8, minute: 50),
      ];
      await pumpPage(
        tester,
        pickTime: (TimeOfDay initial) async => answers.removeAt(0),
      );
      await openPeriods(tester);
      await tester.tap(find.byKey(const ValueKey('s-add-period')));
      await tester.pumpAndSettle();
      final pid = periodAt(0).id;

      await tester.enterText(find.byKey(ValueKey('s-period-label-$pid')), '第 1 节');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('s-period-start-$pid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('s-period-end-$pid')));
      await tester.pumpAndSettle();

      final p = periodAt(0);
      expect(p.label, '第 1 节');
      expect(p.start, '08:10');
      expect(p.end, '08:50');
    });

    testWidgets('滚轮时间选择：确定后时间回填到输入框（真实对话框，不走注入）', (tester) async {
      final s = store.settings()
        ..periods = <Period>[
          Period(id: 'p1', label: '第 1 节', start: '(', end: ')'),
        ];
      store.saveSettings(s);
      await pumpPage(tester); // 不注入 pickTime → 走真实的两列滚轮对话框
      await openPeriods(tester);

      // 手输时代的乱值 ( / ) 要被清掉，显示占位提示
      expect(find.text('('), findsNothing);
      expect(find.text(')'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('s-period-start-p1')));
      await tester.pumpAndSettle();
      // 对话框打开（默认 08:00），直接点确定
      await tester.tap(find.byKey(const ValueKey('wheel-ok')));
      await tester.pumpAndSettle();
      expect(find.text('08:00'), findsOneWidget, reason: '确定后时间要回填到输入框');
      expect(periodAt(0).start, '08:00', reason: '选择结果要落盘');
    });

    testWidgets('删除节次落盘', (tester) async {
      final s = store.settings()
        ..periods = <Period>[
          Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:50'),
          Period(id: 'p2', label: '第 2 节', start: '09:00', end: '09:40'),
        ];
      store.saveSettings(s);
      await pumpPage(tester);
      await openPeriods(tester);

      await tester.tap(find.byKey(const ValueKey('s-period-del-p2')));
      await tester.pumpAndSettle();
      final periods = store.settings().periods;
      expect(periods.length, 1);
      expect(periods.first.id, 'p1');
    });
  });

  group('我的地点', () {
    testWidgets('列表带当前标记；切乙城 → 当前城市更新落盘', (tester) async {
      seedPlaces();
      await pumpPage(tester);
      // 当前地点的「切换」按钮存在但禁用
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('s-place-use-p1'))).onPressed,
          isNull);
      await tester.tap(find.byKey(const ValueKey('s-place-use-p2')));
      await tester.pumpAndSettle();

      expect(store.settings().weatherCity.name, '乙城');
      expect(store.settings().weatherCity.latitude!, closeTo(31.2, 1e-9));
    });

    testWidgets('删除当前地点顺位到第一个', (tester) async {
      seedPlaces();
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('s-place-del-p1')));
      await tester.pumpAndSettle();

      expect(store.settings().weatherCities.map((p) => p.id), <String>['p2']);
      expect(store.settings().weatherCity.name, '乙城', reason: '删了当前城市顺位到第一个');
    });

    testWidgets('删除非当前地点不影响当前城市', (tester) async {
      seedPlaces();
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('s-place-del-p2')));
      await tester.pumpAndSettle();

      expect(store.settings().weatherCities.map((p) => p.id), <String>['p1']);
      expect(store.settings().weatherCity.name, '甲城');
    });

    testWidgets('添加地点：搜索 → 点结果 → 加入并设为当前', (tester) async {
      seedPlaces();
      await pumpPage(tester, api: FakeApi());
      await tester.tap(find.byKey(const ValueKey('s-add-place')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('s-place-q')), '测试城');
      await tester.tap(find.byKey(const ValueKey('s-place-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('s-place-result-测试城')));
      await tester.pumpAndSettle();

      final s = store.settings();
      expect(s.weatherCities.length, 3);
      expect(s.weatherCity.name, '测试城');
      expect(s.weatherCities.any((p) => p.id.startsWith('p')), isTrue,
          reason: '新地点的 id 用 store.newId 生成');
    });
  });

  group('备份 / 还原 / 清空', () {
    testWidgets('立即备份：backups/ 里出现 zip', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('btn-backup')));
      await tester.pumpAndSettle();

      final backups = Directory('${tmp.path}/backups');
      expect(backups.existsSync(), isTrue);
      final zips = backups
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.zip'))
          .toList();
      expect(zips.length, 1);
      expect(zips.first.lengthSync(), greaterThan(0));
    });

    testWidgets('还原：选了合法 zip → 确认 → 四份数据覆盖', (tester) async {
      // 造一份「旧备份」：先在另一个目录里 seed，再打包
      final tmp2 = Directory.systemTemp.createTempSync('myday-settings-restore-');
      addTearDown(() {
        if (tmp2.existsSync()) tmp2.deleteSync(recursive: true);
      });
      final old = Store(tmp2)..init();
      final s = old.settings()
        ..displayName = '备份里的称呼'
        ..week1Monday = '2026-08-31';
      old.saveSettings(s);
      final raw = buildBackupZipForTest(old);

      // 当前数据是另一套
      final cur = store.settings()..displayName = '当前数据';
      store.saveSettings(cur);

      await pumpPage(tester, pickZip: () async => raw);
      await tester.tap(find.byKey(const ValueKey('btn-restore')));
      await tester.pumpAndSettle();
      expect(find.text('用这份备份覆盖当前全部数据？还原前会自动给现在的数据留一份备份。'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('btn-confirm-restore')));
      await tester.pumpAndSettle();

      expect(store.settings().displayName, '备份里的称呼');
      expect(store.settings().week1Monday, '2026-08-31');
      // 还原前自动留了一份
      final backups = Directory('${tmp.path}/backups');
      expect(
          backups
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.zip'))
              .length,
          1);
    });

    testWidgets('还原取消：不覆盖', (tester) async {
      final raw = buildBackupZipForTest(store);
      final cur = store.settings()..displayName = '当前数据';
      store.saveSettings(cur);

      await pumpPage(tester, pickZip: () async => raw);
      await tester.tap(find.byKey(const ValueKey('btn-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(store.settings().displayName, '当前数据');
    });

    testWidgets('还原坏 zip：提示文案与电脑版一致，数据不动', (tester) async {
      await pumpPage(tester, pickZip: () async => <int>[1, 2, 3]);
      await tester.tap(find.byKey(const ValueKey('btn-restore')));
      await tester.pumpAndSettle();

      expect(find.textContaining('不是有效的备份文件'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-confirm-restore')), findsNothing);
    });

    testWidgets('清空：必须输入「清空」两个字，确认后回到默认且先备份', (tester) async {
      final s = store.settings()..displayName = '有数据';
      store.saveSettings(s);
      store.saveNotes(Notes(notes: [Note(id: 'n1', title: '测试备忘录')]));

      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('btn-reset')));
      await tester.pumpAndSettle();

      // 先输错：提示但不执行
      await tester.enterText(find.byKey(const ValueKey('reset-word')), '清除');
      await tester.tap(find.byKey(const ValueKey('btn-confirm-reset')));
      await tester.pump();
      expect(find.text('请先输入「清空」两个字'), findsOneWidget);
      expect(store.settings().displayName, '有数据', reason: '输错字不能清');

      // 输对：确认清空
      await tester.enterText(find.byKey(const ValueKey('reset-word')), '清空');
      await tester.tap(find.byKey(const ValueKey('btn-confirm-reset')));
      await tester.pumpAndSettle();

      expect(store.settings().displayName, '');
      expect(store.notes().notes, isEmpty);
      expect(store.courses().weeks, isEmpty);
      final backups = Directory('${tmp.path}/backups');
      expect(
          backups
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.zip'))
              .length,
          1, reason: '清空前自动备份了一份');
    });

    testWidgets('清空取消：数据不动', (tester) async {
      final s = store.settings()..displayName = '有数据';
      store.saveSettings(s);

      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('btn-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(store.settings().displayName, '有数据');
    });
  });
}

/// 测试辅助：给指定 store 打一个备份 zip 字节。
/// 真正的打包逻辑由 backup_test.dart 覆盖，这里只需要一份合法备份。
List<int> buildBackupZipForTest(Store s) {
  final manifest = <String, dynamic>{
    'app': 'MyDay',
    'version': 1,
    'exportedAt': '2026-09-19T01:00:00+08:00',
    'files': backupDataFiles,
  };
  final archive = Archive();
  void add(String name, Object obj) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(obj));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('manifest.json', manifest);
  for (final name in backupDataFiles) {
    add(name, s.read(name.substring(0, name.length - 5)));
  }
  return ZipEncoder().encode(archive)!;
}
