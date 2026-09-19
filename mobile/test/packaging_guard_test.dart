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
}
