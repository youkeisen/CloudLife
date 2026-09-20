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

  /// 测试用开关（v1.7.3）：设成 true 后，[hasManageExternalStorage] 假装
  /// 当前平台是安卓，并走 [_fakeHasStorage] 的返回值。
  /// 桌面测试跑不到真安卓，没这个钩子就没法测「没权限 → 弹引导框」那条路。
  static bool debugFakeAndroid = false;
  static bool _fakeHasStorage = false;

  /// 测试里设权限状态；传 null 还原成「按真实平台判断」。
  static void debugSetStoragePermission(bool? granted) {
    if (granted == null) {
      debugFakeAndroid = false;
      return;
    }
    debugFakeAndroid = true;
    _fakeHasStorage = granted;
  }

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

  // ---------- 所有文件访问（v1.7.3） ----------
  //
  // 背景：安卓 10+ 的分区存储下，普通 File IO 写不进 /storage/emulated/0/**
  // （「下载」「文档」这些共享目录）。凯森 2026-09-20 选备份位置时报
  // `PathAccessException: ... Operation not permitted, errno = 1`。
  // 拿到这个权限后才能直接写共享目录。

  /// 是否已拿到「所有文件访问」权限。
  /// 非安卓一律 true（别的平台没这个概念，界面上不显示多余提示）；
  /// 安卓 11 以下原生侧也返回 true（旧机型不需要这个权限）。
  static Future<bool> hasManageExternalStorage() async {
    if (debugFakeAndroid) return _fakeHasStorage;
    if (!Platform.isAndroid) return true;
    try {
      final v = await _ch.invokeMethod<bool>('hasManageExternalStorage');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到系统的「所有文件访问」授权页。
  /// **这是敏感权限，系统不给一键授权**，只能把用户带到页面让他自己点。
  static Future<void> requestManageExternalStorage() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod<void>('requestManageExternalStorage');
  }

  /// 打开系统设置里的「闹钟和提醒」页（v1.7.4）。
  /// 用来让用户给本应用开精确闹钟权限——没有它，提醒会被系统延后触发。
  static Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod<void>('openExactAlarmSettings');
  }

  // ---------- 自启动（v1.8.0） ----------
  //
  // 为什么要有这一项：国产 ROM（小米 / 华为 / OPPO / vivo / 荣耀…）额外加了一层
  // 「自启动」开关。关着的时候系统重启后 App 不会被拉起来，
  // 开机补提醒（BootReceiver）就完全没机会跑 —— 表现是「手机重启后再也不提醒」。
  //
  // 难点：安卓**没有标准 Intent**，每家 ROM 的自启动页包名类名都不同，
  // 也**没有任何 API 能查开关状态**。所以只能跳过去让用户自己开。

  /// 跳 ROM 的自启动管理页。
  /// 返回 true = 跳到了专门的自启动页；
  /// 返回 false = 这台手机找不到那种页面，已退到「应用详情」页兜底
  /// （原生/Pixel 之类的机器没有自启动概念，就是这种情况）。
  static Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final v = await _ch.invokeMethod<bool>('openAutoStartSettings');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}
