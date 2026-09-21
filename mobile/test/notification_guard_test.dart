// v1.7.4：「到时间没提醒」相关的守卫测试。
//
// 背景（凯森 2026-09-20 反馈）：他说没退出软件，但到点通知栏没弹。
// 查下来是三个独立的问题叠在一起，这个文件各守一个：
//   1. 通知权限被拒后无人知晓 —— 系统静默丢掉通知，App 侧完全无感
//   2. 精确闹钟没开 —— 非精确闹钟会被安卓攒起来延后触发
//   3. 重排是「先全撤、后重排」—— 中途失败会导致通知全没了且不报错
//
// 全部用假数据 + 桌面测试环境，不碰真通知插件、不碰真实个人信息。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_day_phone/lesson_reminder.dart';
import 'package:my_day_phone/models.dart';
import 'package:my_day_phone/notification_service.dart';

void main() {
  group('通知权限查询（v1.7.4）', () {
    tearDown(() => NotificationService.debugSetPermissions());

    test('被拒时返回 false —— 这是「到点不提醒」的第一嫌疑', () async {
      NotificationService.debugSetPermissions(enabled: false);
      expect(await NotificationService.notificationsEnabled(), isFalse);
    });

    test('已开启时返回 true', () async {
      NotificationService.debugSetPermissions(enabled: true);
      expect(await NotificationService.notificationsEnabled(), isTrue);
    });

    test('精确闹钟没开时返回 false', () async {
      NotificationService.debugSetPermissions(enabled: true, exact: false);
      expect(await NotificationService.exactAlarmsAllowed(), isFalse);
    });

    test('精确闹钟已开时返回 true', () async {
      NotificationService.debugSetPermissions(enabled: true, exact: true);
      expect(await NotificationService.exactAlarmsAllowed(), isTrue);
    });

    test('还原钩子后又走真实平台判断（桌面非安卓 → true）', () async {
      NotificationService.debugSetPermissions(enabled: false);
      NotificationService.debugSetPermissions();
      expect(await NotificationService.notificationsEnabled(), isTrue);
    });
  });

  // 排通知的模式不是纯逻辑，但「该用哪种」这个判断可以在这里守住：
  // 桌面环境拿不到安卓插件，但也不该因此报「权限没有」——
  // 非安卓一律当作放行（true），免得在桌面上误报提示。
  group('闹钟模式降级（v1.7.4）', () {
    tearDown(() => NotificationService.debugSetPermissions());

    test('非安卓一律当作放行，不抛异常也不误报', () async {
      NotificationService.debugSetPermissions();
      // 不抛就是通过；true = 「当作允许」，界面上不会显示多余提示
      expect(await NotificationService.exactAlarmsAllowed(), isTrue);
      expect(await NotificationService.notificationsEnabled(), isTrue);
    });

    test('显式设成不允许时（模拟安卓上被拒）能查出来', () async {
      NotificationService.debugSetPermissions(enabled: true, exact: false);
      expect(await NotificationService.exactAlarmsAllowed(), isFalse);
    });
  });

  // 第三条：重排策略。原来「先把所有课的通知 cancel 掉，再逐条 schedule」，
  // schedule 中途失败（闹钟数超限、插件抽风）会被 catch 吞掉，
  // 结果是旧的全撤了、新的没排上 —— 用户那边看起来就是提醒莫名其妙全消失。
  // 现在改成「先算好列表，算不出东西就不动旧的」。
  group('重排不再「先全撤后重排」（v1.7.4）', () {
    Settings s({int lead = 15, String week1 = '2026-09-07'}) =>
        (Settings.initial()
          ..week1Monday = week1
          ..lessonRemindMinutes = lead
          ..periods = <Period>[
            Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:55'),
          ]);

    Courses c() => Courses(weeks: <int, List<Lesson>>{
          1: <Lesson>[
            Lesson(id: 'l1', day: 1, slot: 'p1', name: '高数', location: '1#102'),
          ],
        });

    test('正常情况能算出提醒列表（非空 → 才动旧通知）', () {
      final list = lessonReminders(
        settings: s(),
        courses: c(),
        // 基准取周日晚上，这样周一那节课的提醒还在未来
        from: DateTime(2026, 9, 6, 20, 0),
        days: 7,
      );
      expect(list, isNotEmpty);
    });

    test('关掉提醒 → 列表为空，此时不该去撤旧通知', () {
      final list = lessonReminders(
        settings: s(lead: -1),
        courses: c(),
        from: DateTime(2026, 9, 6, 20, 0),
        days: 7,
      );
      expect(list, isEmpty,
          reason: '空列表是「故意不排」，不是「排失败」，所以直接返回、不动旧通知');
    });

    test('没设第 1 周周一 → 列表为空（同样是「不排」，不是「排失败」）', () {
      final list = lessonReminders(
        settings: s(week1: ''),
        courses: c(),
        from: DateTime(2026, 9, 6, 20, 0),
        days: 7,
      );
      expect(list, isEmpty);
    });
  });

  // 凯森的操作路径：周日晚上看课表，明天（第 4 周周一）就该提醒。
  // 这条守的是「跨到下一周时也能算出提醒」，别因为周次切换漏掉。
  group('跨周边界（v1.7.4）', () {
    test('周日算未来的周一：能算出下周那节课的提醒', () {
      final settings = Settings.initial()
        ..week1Monday = '2026-08-31' // 第 1 周周一
        ..lessonRemindMinutes = 15
        ..periods = <Period>[
          Period(id: 'p1', label: '第 1 节', start: '08:10', end: '08:55'),
        ];
      final courses = Courses(weeks: <int, List<Lesson>>{
        4: <Lesson>[
          Lesson(id: 'l1', day: 1, slot: 'p1', name: '工程制图', location: '1#303'),
        ],
      });
      // 2026-09-20 是周日，2026-09-21 是第 4 周周一
      final list = lessonReminders(
        settings: settings,
        courses: courses,
        from: DateTime(2026, 9, 20, 20, 0),
        days: 7,
      );
      expect(list, isNotEmpty, reason: '周日晚上要能算出明天的课');
      expect(list.first.when, DateTime(2026, 9, 21, 7, 55),
          reason: '08:10 上课、提前 15 分钟 → 07:55 提醒');
      expect(list.first.title, contains('工程制图'));
      expect(list.first.body, contains('1#303'));
    });
  });

  // v1.7.6：修闪退。
  // 凯森 2026-09-20 反馈「时间到了没有弹通知并且软件闪退了」。
  // 两个原因都改在代码里了，这里守住「别再退回去」：
  //   ① 通知小图标必须是纯白剪影 drawable，不能用彩色 launcher 图标
  //   ② 无界面引擎（开机重排）不能申请权限 —— 没有 Activity 会崩
  group('v1.7.6 闪退修复的守卫', () {
    test('通知小图标用的是 drawable/ic_notification（纯白剪影）', () {
      final src = File('lib/notification_service.dart').readAsStringSync();
      expect(src.contains("@drawable/ic_notification"), isTrue,
          reason: '通知小图标必须是纯白剪影，用彩色 launcher 图标会显示成白方块，'
              '部分国产 ROM 还会在弹通知时崩进程');
      expect(src.contains("'@mipmap/ic_launcher'"), isFalse,
          reason: '不要再把彩色 launcher 图标当通知小图标');
    });

    test('通知图标是矢量 drawable（不要退回 PNG）', () {
      // 为什么最终用 XML 矢量而不是 PNG：
      // 一开始做的是 5 张 PNG（drawable-{m,h,x,xx,xxx}dpi/ic_notification.png），
      // 源 PNG 明明是对的（上框 + 实心倒三角，30.6% 不透明），
      // 但打进 APK 之后被 AAPT 的 PNG 优化重编码成了「细描边空心框」，
      // 形状全丢 —— 通知栏 24dp 下那种细线根本看不见。
      // 矢量不走 PNG 优化，形状 100% 保真，所以定稿用矢量。
      final v = File('android/app/src/main/res/drawable/ic_notification.xml');
      expect(v.existsSync(), isTrue,
          reason: '缺 drawable/ic_notification.xml（矢量通知图标）');
      final text = v.readAsStringSync();
      expect(text.contains('<vector'), isTrue, reason: '必须是矢量 drawable');
      expect(text.contains('M4,5 L20,5'), isTrue, reason: '云朵主体的圆角框不见了');
      expect(text.contains('M7.5,14.5 L16.5,14.5 L12,20.5 Z'), isTrue,
          reason: '云朵的尖（实心倒三角）不见了');
      // 通知图标不能自带颜色，安卓只取 alpha 再染色
      expect(text.contains('#FFFFFFFF'), isTrue,
          reason: '填充色必须是纯白（系统只取 alpha 通道再自行染色）');

      // 同名 PNG 不能再存在，否则会盖住矢量 / 又被优化坏
      for (final d in <String>['', '-mdpi', '-hdpi', '-xhdpi', '-xxhdpi', '-xxxhdpi']) {
        final png = File(
            'android/app/src/main/res/drawable$d/ic_notification.png');
        expect(png.existsSync(), isFalse,
            reason: 'drawable$d/ic_notification.png 不该存在，'
                '矢量版已经取代它了（PNG 会被 AAPT 优化坏形状）');
      }
    });

    test('有 keep.xml 守住通知图标，否则 release 会把它剔掉', () {
      // Dart 侧是用**字符串** '@drawable/ic_notification' 引用的，
      // 构建期的资源分析器看不见 → release 打包会当成没人用的资源丢掉。
      // 证据：build/app/outputs/mapping/release/resources.txt 里写的是
      //   drawable:ic_notification:2131099676 is not reachable.
      //
      // 注意：values/ 里写 <item> 当锚点是**没用的**（踩过这个坑）——
      // <item> 是「定义一个新资源」，不是「引用一次」，锚点自己也会被删。
      // 正解是 res/raw/keep.xml 的 tools:keep。
      final keep = File('android/app/src/main/res/raw/keep.xml');
      expect(keep.existsSync(), isTrue,
          reason: '缺 res/raw/keep.xml，通知图标会被资源压缩器删掉');
      final text = keep.readAsStringSync();
      expect(text.contains('tools:keep'), isTrue,
          reason: 'keep.xml 里必须有 tools:keep 声明');
      expect(text.contains('@drawable/ic_notification'), isTrue,
          reason: 'keep.xml 必须保住 ic_notification');
    });

    test('存在 initHeadless：无界面引擎不申请权限', () {
      final src = File('lib/notification_service.dart').readAsStringSync();
      expect(src.contains('initHeadless'), isTrue,
          reason: '开机重排跑在无 Activity 的引擎上，申请权限会崩进程');
      // 申请权限那句必须被开关包着
      expect(src.contains('_requestPermissionOnInit'), isTrue,
          reason: '申请权限要有开关控制，否则无界面引擎上会崩');
    });

    test('开机重排走 headless 模式', () {
      final src = File('lib/boot_reschedule.dart').readAsStringSync();
      expect(src.contains('headless: true'), isTrue,
          reason: 'bootMain 是无界面引擎，必须走 headless');
    });

    test('重排有防重入保护（同一引擎内不并发跑）', () {
      final src = File('lib/reminder_scheduler.dart').readAsStringSync();
      expect(src.contains('_inFlight'), isTrue,
          reason: 'App 启动/改设置/改课表可能同时触发重排，并发会重复排通知');
    });
  });

  // ---------- v1.8.2：每天重复的提醒不能被当成过期撤掉 ----------
  //
  // 这是「加每天选项」最容易踩的坑：重排那段原本的逻辑是
  // 「remindAt 已经过去 → 撤掉通知」，这对单次是对的，
  // 但每天重复的提醒存的本来就是**很久以前的**那个时刻 ——
  // 照原逻辑一重排（每次 App 启动都会）就把它撤了，用户第二天就收不到了。
  group('每天重复的提醒（v1.8.2）', () {
    late String src;

    setUpAll(() {
      src = File('lib/reminder_scheduler.dart').readAsStringSync();
    });

    test('重排时对每天的提醒单独处理，不跟单次共用「过期就撤」', () {
      expect(src.contains('remindDaily'), isTrue,
          reason: '重排里必须先判断是不是每天，否则过期分支会把它撤掉');
      expect(src.contains('nextDailyOccurrence'), isTrue,
          reason: '每天的要现算下一次时刻（插件只排未来的时间）');
      expect(src.contains('repeatDaily: true'), isTrue,
          reason: '排的时候要带上每天重复参数');
    });

    test('每天那条分支在「过期撤销」之前就 continue 掉', () {
      // 用位置判断：daily 分支必须出现在 `!when.isAfter(now)` 这个过期判断之前。
      final dailyAt = src.indexOf('if (n.remindDaily)');
      final expiredAt = src.indexOf('!when.isAfter(now)');
      expect(dailyAt, greaterThan(-1), reason: '找不到每天的分支');
      expect(expiredAt, greaterThan(-1), reason: '找不到过期判断');
      expect(dailyAt, lessThan(expiredAt),
          reason: '顺序反了的话每天的提醒会先被撤掉，第二天就不响了');
    });

    test('通知层确实用了按时间重复（DateTimeComponents.time）', () {
      final notif = File('lib/notification_service.dart').readAsStringSync();
      expect(notif.contains('matchDateTimeComponents'), isTrue,
          reason: '不带这个参数就只响一次');
      expect(notif.contains('DateTimeComponents.time'), isTrue,
          reason: '按「时:分」重复才是每天，DateTimeComponents 别的值语义不同');
    });
  });
}

