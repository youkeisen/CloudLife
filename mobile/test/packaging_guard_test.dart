// 打包配置的守卫：正式包（main 清单）必须能联网。
//
// 背景（v1.0.0 的真 bug）：Flutter 模板只在 debug/profile 清单里有 INTERNET 权限，
// `flutter run` 一切正常，但 release APK 没有联网权限——天气取不到、城市搜不到。
// 这个测试就是防止它再悄悄丢掉。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // 测试文件在 <项目>/test，往上两级是项目根
  final projectRoot = Directory.current.path;
  final mainManifest = File(
      '$projectRoot/android/app/src/main/AndroidManifest.xml');

  test('主 AndroidManifest 声明了 INTERNET 权限', () {
    expect(mainManifest.existsSync(), isTrue,
        reason: '找不到 ${mainManifest.path}');
    final text = mainManifest.readAsStringSync();
    expect(text.contains('android.permission.INTERNET'), isTrue,
        reason: '正式包没有联网权限，天气和城市搜索会全部失败');
  });

  test('应用名称是 MyDay（不是模板默认的包名）', () {
    final text = mainManifest.readAsStringSync();
    expect(text.contains('android:label="my_day_phone"'), isFalse,
        reason: '桌面上显示的名字不该是项目包名');
  });

  // 【v1.7.5】定时通知的接收器必须声明。
  //
  // 背景（真 bug，凯森 2026-09-20 反馈「课表提醒和备忘录定时都没有通知」）：
  // flutter_local_notifications 用 AlarmManager 排闹钟，到点时靠
  // ScheduledNotificationReceiver 收到广播再把通知弹出来。
  // **插件自带的 manifest 里没有这两个 receiver，必须由 App 声明。**
  // 漏了的话闹钟照样响、广播照样发，但没人接 —— 通知永远不出现，
  // 而且**没有任何报错**，权限和电池优化全都正常也没用。
  //
  // 这个测试就是防止它再被删掉/漏掉。
  test('声明了定时通知的 ScheduledNotificationReceiver', () {
    final text = mainManifest.readAsStringSync();
    expect(
        text.contains(
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'),
        isTrue,
        reason: '缺这个 receiver，定时通知到点也不会弹（闹钟响了没人接）');
  });

  test('声明了开机恢复通知的 ScheduledNotificationBootReceiver', () {
    final text = mainManifest.readAsStringSync();
    expect(
        text.contains(
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver'),
        isTrue,
        reason: '缺这个 receiver，手机重启后排好的提醒不会恢复');
    // 它必须挂 BOOT_COMPLETED，否则开机广播收不到
    expect(text.contains('android.intent.action.BOOT_COMPLETED'), isTrue,
        reason: 'BootReceiver 要监听开机广播才有效');
  });

  test('通知相关的权限都在（通知本身 / 精确闹钟 / 开机）', () {
    final text = mainManifest.readAsStringSync();
    for (final perm in <String>[
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ]) {
      expect(text.contains(perm), isTrue, reason: '缺权限：$perm');
    }
  });

  // v1.7.6 的真正根因：R8 把 Gson 需要的泛型签名擦掉了。
//
// 凯森开了 USB 调试，抓到崩溃记录才定位到：
//   Unable to start receiver ...ScheduledNotificationReceiver:
//   java.lang.RuntimeException: Missing type parameter.
//   at FlutterLocalNotificationsPlugin.loadScheduledNotifications(...)
//
// 插件源码第 508 行：
//   new TypeToken<ArrayList<NotificationDetails>>() {}.getType()
// Gson 靠匿名 TypeToken 子类的 **Signature 属性**（泛型签名）反射拿类型。
// R8 默认擦掉它 → Gson 读不到类型参数 → 抛异常 → receiver 崩 → 进程没了。
// 表现就是「通知永远不弹 + App 闪退」，设置页查「已排提醒」也一起崩。
//
// 这个坑**编译器不管、测试照过**，只能靠下面的规则 + 真机崩溃记录来抓。
  group('R8 混淆必须保住 Gson 的类型信息（v1.7.6 真凶）', () {
    final proguard = File('android/app/proguard-rules.pro');
    final gradle = File('android/app/build.gradle.kts');

    test('proguard-rules.pro 存在', () {
      expect(proguard.existsSync(), isTrue,
          reason: '缺 proguard-rules.pro —— R8 会擦掉 Gson 需要的泛型签名，'
              '导致通知到点时 receiver 崩溃、通知永远不弹');
    });

    test('保住了泛型签名 Signature（最关键的一条）', () {
      final text = proguard.readAsStringSync();
      expect(text.contains('-keepattributes Signature'), isTrue,
          reason: '缺 -keepattributes Signature。Gson 的 TypeToken 全靠这条 '
              '拿到 ArrayList<NotificationDetails> 的类型参数，'
              '没了它就抛 "Missing type parameter"');
    });

    test('保住了 flutter_local_notifications 的模型类', () {
      final text = proguard.readAsStringSync();
      expect(text.contains('com.dexterous.flutterlocalnotifications'), isTrue,
          reason: '没有保住插件的模型类，NotificationDetails 会被重命名，'
              'Gson 反序列化就对不上了');
    });

    test('保住了 Gson 本身和它的扩展点', () {
      final text = proguard.readAsStringSync();
      expect(text.contains('com.google.gson'), isTrue, reason: 'Gson 自身要保住');
      // 插件的 RuntimeTypeAdapterFactory 走 TypeAdapterFactory 这条
      expect(text.contains('TypeAdapterFactory'), isTrue,
          reason: '没有保住 TypeAdapterFactory，插件的多态样式解析会失效');
      expect(text.contains('TypeToken'), isTrue,
          reason: 'TypeToken 的匿名子类是 Gson 反射拿类型的入口，必须保住');
    });

    test('release 构建挂上了这份规则', () {
      final text = gradle.readAsStringSync();
      expect(text.contains('proguard-rules.pro'), isTrue,
          reason: 'build.gradle.kts 里没挂 proguard-rules.pro，'
              '规则写了也不会生效');
      expect(text.contains('isMinifyEnabled'), isTrue,
          reason: '没显式开启 minifyEnabled，混淆配置可能不生效');
    });
  });
}
