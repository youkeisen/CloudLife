// MainActivity 里 `cloudlife/system` 通道的守卫。
//
// 为什么要有这个文件：这些跳转全是「字符串对字符串」——
// Dart 侧 `invokeMethod('xxx')` 的名字必须和 Kotlin 侧 `when (call.method)`
// 的分支一字不差，写错的后果是 `MissingPluginException`，
// 而且**只有真机点到那个按钮才会炸**，桌面测试和 analyze 都抓不到。
//
// 所以这里直接读源码文本，把「两边名字对得上」钉死。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final kt = File(
      '$root/android/app/src/main/kotlin/com/youkeisen/my_day_phone/MainActivity.kt');
  final dart = File('$root/lib/system_tweaks.dart');

  late String ktText;
  late String dartText;

  setUpAll(() {
    ktText = kt.readAsStringSync();
    dartText = dart.readAsStringSync();
  });

  test('源文件和 Dart 侧都在', () {
    expect(kt.existsSync(), isTrue, reason: '找不到 ${kt.path}');
    expect(dart.existsSync(), isTrue, reason: '找不到 ${dart.path}');
  });

  // 逐个 method 名核对两边都有。
  // 「血泪表」：每加一个新 method 就得在这里补一行，
  // 否则漏一个字两边就断了。
  for (final method in <String>[
    'isBatteryOptimizationDisabled',
    'requestIgnoreBatteryOptimizations',
    'openAppSettings',
    'hasManageExternalStorage',
    'requestManageExternalStorage',
    'openExactAlarmSettings',
    'openAutoStartSettings',
  ]) {
    test('通道方法 $method 两边名字对得上', () {
      expect(ktText.contains('"$method"'), isTrue,
          reason: 'MainActivity.kt 里没有 "$method" 这个分支');
      expect(dartText.contains("'$method'"), isTrue,
          reason: 'system_tweaks.dart 里没有调 "$method"');
    });
  }

  // ---------- v1.8.0：自启动 ----------
  //
  // 背景（凯森 2026-09-21 要的）：国产 ROM 关着自启动时，
  // 手机重启后 App 起不来，开机补提醒（BootReceiver）根本没有机会跑。
  // 安卓**没有标准的自启动 Intent**，只能按厂商挨个试，所以这张表
  // 不能丢，也不能拼错包名。

  test('自启动：覆盖了主流国产 ROM', () {
    final body = ktText.substring(ktText.indexOf('autoStartCandidates'));
    for (final rom in <String>[
      'com.vivo.permissionmanager', // vivo（凯森这台 S10）
      'com.miui.securitycenter', // 小米 / Redmi
      'com.coloros.safecenter', // OPPO / 一加 / realme
      'com.huawei.systemmanager', // 华为 EMUI
      'com.hihonor.systemmanager', // 荣耀 MagicOS
    ]) {
      expect(body.contains(rom), isTrue, reason: '自启动候选里少了 $rom');
    }
  });

  test('自启动：按机型把自家厂商排前面', () {
    expect(ktText.contains('sortedByDescending'), isTrue,
        reason: '不排序的话，vivo 的机器可能先撞上一个不存在的 OPPO 页面');
    expect(ktText.contains('romHints'), isTrue);
  });

  test('自启动：先 resolve 再 start（不能靠抛异常判断页面存不存在）', () {
    final body = ktText.substring(ktText.indexOf('private fun tryOpen'));
    expect(body.contains('resolveActivity'), isTrue,
        reason: '直接 startActivity 猜错一堆会一路抛 ActivityNotFoundException');
  });

  test('自启动：全都试不出来时有兜底', () {
    final body = ktText.substring(ktText.indexOf('openAutoStartSettings(): Boolean'));
    expect(body.contains('openAppSettings()'), isTrue,
        reason: '原生 ROM 没有自启动页，不兜底的话点了按钮毫无反应');
  });
}
