package com.youkeisen.my_day_phone

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint

/// 开机后排提醒的「无界面引擎」（v1.6.0，需求文档第 8 条）。
///
/// 做法：开机时拿一个 FlutterEngine 起来（Dart 入口是 `bootMain`，
/// 见 `lib/boot_reschedule.dart`），让它自己读本地数据、把未来一周的
/// 上课提醒 + 备忘录提醒排进系统闹钟，然后**立刻把引擎销毁**。
/// 全程不弹界面、不占前台服务，符合凯森「不要常驻通知」的要求。
///
/// 兜底设计：真正的重排主力是「每次打开 App」，开机这一发只补最近一周；
/// 所以这里失败也不影响用，最多是重启后第一次打开 App 前少几条提醒。
object BootRescheduleWorker {
    fun schedule(context: Context) {
        // 引擎起来 + Dart 跑完重排大概几百毫秒；给 8 秒硬上限
        // （系统给开机广播的总预算是 10 秒）。
        val engine = FlutterEngine(context)
        try {
            engine.dartExecutor.executeDartEntrypoint(bootEntrypoint())
        } catch (_: Throwable) {
            engine.destroy()
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                engine.destroy()
            } catch (_: Throwable) {
                // 忽略
            }
        }, 8000)
    }

    /// Dart 侧在 `boot_reschedule.dart` 里用 `@pragma('vm:entry-point')`
    /// 标了 `bootMain`；Flutter 会把它编进同一个包里。
    private fun bootEntrypoint(): DartEntrypoint =
        DartEntrypoint("package:my_day_phone/boot_reschedule.dart", "bootMain")
}
