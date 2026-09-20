/// 系统级小工具：电池优化白名单、跳系统设置（v1.6.0，需求文档第 8 条）。
///
/// 只做安卓；别的平台一律当「已放行」，界面上就不会显示多余的提示。
/// 独立成一个文件是为了让设置页不直接依赖 MethodChannel 细节，也好在
/// 测试里替换掉。
library;

import 'dart:io';

import 'package:flutter/services.dart';

class SystemTweaks {
  SystemTweaks._();

  static const MethodChannel _ch = MethodChannel('cloudlife/system');

  /// 是否已经忽略电池优化（= 已放进白名单）。
  /// 非安卓或有任何异常都返回 true（当作放行），避免误报。
  static Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    try {
      final v = await _ch.invokeMethod<bool>('isBatteryOptimizationDisabled');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 把系统设置里的「电池优化」页面弹出来。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod<void>('requestIgnoreBatteryOptimizations');
  }

  /// 打开本应用的系统设置页（电池页面打不开时的兜底）。
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod<void>('openAppSettings');
  }
}
